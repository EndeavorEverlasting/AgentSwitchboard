[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot "tmux-gnhf-workstation.example.json"),
    [string]$ArtifactRoot,
    [string]$RoutingEvidencePath,
    [ValidateRange(10, 300)]
    [int]$WaitSeconds = 60,
    [switch]$NonInteractive,
    [switch]$SkipLaunch,
    [string]$WslExe = "wsl.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This runtime proof collector requires PowerShell 7. Open pwsh and rerun."
}

function Write-ProofEvent {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateSet("PASS", "SKIP", "FAIL", "INFO")][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [hashtable]$Data = @{}
    )

    $event = [ordered]@{
        at = (Get-Date).ToString("o")
        step = $Step
        state = $State
        message = $Message
        data = $Data
    }
    $script:events.Add([pscustomobject]$event)
    $color = switch ($State) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "SKIP" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$State] $Step - $Message" -ForegroundColor $color
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 30
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true); $process.WaitForExit() } catch {}
        throw "Command timed out after ${TimeoutSeconds}s: $FilePath $($ArgumentList -join ' ')"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Invoke-WslBash {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutSeconds = 30
    )

    return Invoke-BoundedProcess -FilePath $WslExe -ArgumentList @(
        "-d", $Distribution, "-e", "bash", "-lc", $Command
    ) -TimeoutSeconds $TimeoutSeconds
}

function Wait-ForCondition {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [int]$PollMilliseconds = 1000
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-TmuxClientLines {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$SessionName
    )

    $result = Invoke-WslBash -Distribution $Distribution -Command "tmux list-clients -F '#{session_name}|#{client_tty}' 2>/dev/null || true" -TimeoutSeconds 10
    return @(
        $result.Stdout -split '\r?\n' |
            Where-Object { $_ -and $_ -like "${SessionName}|*" }
    )
}

function Get-TmuxWindowLines {
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$SessionName
    )

    $result = Invoke-WslBash -Distribution $Distribution -Command "tmux list-windows -t '$SessionName' -F '#{window_id}|#{window_index}|#{window_name}'" -TimeoutSeconds 15
    if ($result.ExitCode -ne 0) {
        throw "Unable to list tmux windows. $($result.Output)"
    }
    return @($result.Stdout -split '\r?\n' | Where-Object { $_ })
}

function Get-RoutingSummary {
    param([string]$Path)

    if (-not $Path) {
        return [ordered]@{
            supplied = $false
            selectedAgent = $null
            selectedModel = $null
            tokenAvailability = $null
            switchReason = $null
            evidenceHash = $null
        }
    }

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $raw = Get-Content -LiteralPath $resolved -Raw
    $data = $raw | ConvertFrom-Json -Depth 50
    $containers = @($data)
    foreach ($name in @("selection", "routing", "decision", "result", "tokenManagement")) {
        if ($data.PSObject.Properties.Name -contains $name -and $null -ne $data.$name) {
            $containers += $data.$name
        }
    }

    function Find-Value {
        param([object[]]$Candidates, [string[]]$Names)
        foreach ($candidate in $Candidates) {
            foreach ($name in $Names) {
                if ($candidate.PSObject.Properties.Name -contains $name) {
                    $value = $candidate.$name
                    if ($null -ne $value -and [string]$value) { return $value }
                }
            }
        }
        return $null
    }

    return [ordered]@{
        supplied = $true
        selectedAgent = Find-Value -Candidates $containers -Names @("selectedAgent", "agentId", "agent")
        selectedModel = Find-Value -Candidates $containers -Names @("selectedModel", "modelId", "model")
        tokenAvailability = Find-Value -Candidates $containers -Names @("tokenAvailability", "availableTokens", "remainingTokens", "tokenRemaining")
        switchReason = Find-Value -Candidates $containers -Names @("switchReason", "reasonCode", "reason")
        evidenceHash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    }
}

function Read-OperatorObservation {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Step
    )

    if ($NonInteractive) {
        Write-ProofEvent -Step $Step -State "SKIP" -Message "operator_observation_not_requested"
        return $false
    }

    $response = Read-Host "$Prompt Type YES to attest, or press Enter to leave unproven"
    if ($response -eq "YES") {
        Write-ProofEvent -Step $Step -State "PASS" -Message "operator_attested"
        return $true
    }

    Write-ProofEvent -Step $Step -State "SKIP" -Message "operator_did_not_attest"
    return $false
}

$events = [System.Collections.Generic.List[object]]::new()
$failureReason = $null
$markerWindowId = $null
$proof = [ordered]@{
    floorSafe = $false
    targetedValidation = $false
    safeStart = $false
    launcherAttached = $false
    surfaceReadyObserved = $false
    agentCommandAck = $false
    behaviorObserved = $false
    detachObserved = $false
    persistenceObserved = $false
    reattachObserved = $false
    runtimeArtifactCollected = $false
    liveRuntime = $false
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported manifest schemaVersion: $($manifest.schemaVersion)."
}

$distribution = [string]$manifest.distribution
$sessionName = [string]$manifest.workspace.sessionName
if ($distribution -notmatch '^[A-Za-z0-9._-]+$' -or $sessionName -notmatch '^[A-Za-z0-9_-]+$') {
    throw "Manifest contains an unsafe distribution or tmux session name."
}

$installRoot = [System.IO.Path]::GetFullPath(
    [Environment]::ExpandEnvironmentVariables([string]$manifest.workspace.installRoot)
)
$startScript = Join-Path $installRoot "Start-TmuxGnhfWorkspace.ps1"
$statusScript = Join-Path $installRoot "Get-TmuxGnhfWorkspaceStatus.ps1"

if (-not $ArtifactRoot) {
    $runtimeRoot = Join-Path $installRoot "runtime-proof"
    $ArtifactRoot = Join-Path $runtimeRoot (Get-Date -Format "yyyyMMdd-HHmmss")
}
$ArtifactRoot = [System.IO.Path]::GetFullPath($ArtifactRoot)
New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
$proofPath = Join-Path $ArtifactRoot "runtime-proof.json"
$eventPath = Join-Path $ArtifactRoot "runtime-events.jsonl"

$route = Get-RoutingSummary -Path $RoutingEvidencePath
$selectedAgent = if ($route.selectedAgent) { [string]$route.selectedAgent } else { [string]$manifest.gnhf.defaultAgent }
if ($selectedAgent -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Selected agent name is unsafe: $selectedAgent"
}

$repoRoot = $null
$branch = $null
$head = $null

try {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command git -ErrorAction Stop }
    $rootResult = Invoke-BoundedProcess -FilePath $git.Source -ArgumentList @("rev-parse", "--show-toplevel")
    if ($rootResult.ExitCode -ne 0) { throw "Unable to resolve repository root. $($rootResult.Output)" }
    $repoRoot = $rootResult.Stdout.Trim()

    $statusResult = Invoke-BoundedProcess -FilePath $git.Source -ArgumentList @("-C", $repoRoot, "status", "--short")
    $statusLines = @($statusResult.Stdout -split '\r?\n' | Where-Object { $_ })
    if ($statusLines.Count -gt 0) {
        throw "Repository floor is dirty. Preserve unknown work and rerun from a clean checkout."
    }
    $branch = (Invoke-BoundedProcess -FilePath $git.Source -ArgumentList @("-C", $repoRoot, "branch", "--show-current")).Stdout.Trim()
    $head = (Invoke-BoundedProcess -FilePath $git.Source -ArgumentList @("-C", $repoRoot, "rev-parse", "HEAD")).Stdout.Trim()
    $proof.floorSafe = $true
    Write-ProofEvent -Step "repo-floor" -State "PASS" -Message "clean_checkout" -Data @{ branch = $branch; head = $head }

    $validator = Join-Path $PSScriptRoot "Test-TmuxGnhfWorkspaceContracts.ps1"
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $validationResult = Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $validator
    ) -TimeoutSeconds 180
    if ($validationResult.ExitCode -ne 0) {
        throw "Targeted workstation contracts failed. $($validationResult.Output)"
    }
    $proof.targetedValidation = $true
    Write-ProofEvent -Step "targeted-validation" -State "PASS" -Message "workstation_contracts_passed"

    foreach ($required in @($startScript, $statusScript)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required repo-generated runtime script is missing: $required. Run the installer with -Apply first."
        }
    }

    $preStatus = & $statusScript
    Write-ProofEvent -Step "pre-runtime-status" -State "INFO" -Message "status_collected" -Data @{
        keepAliveRunning = [bool]$preStatus.keepAliveRunning
        sessionAvailable = [bool]$preStatus.sessionAvailable
        windows = @($preStatus.windows)
    }

    if (-not $SkipLaunch) {
        & $startScript
        $proof.safeStart = $true
        Write-ProofEvent -Step "safe-start" -State "PASS" -Message "repo_owned_start_script_completed"
    }
    else {
        Write-ProofEvent -Step "safe-start" -State "SKIP" -Message "launch_skipped_by_operator"
    }

    $attached = Wait-ForCondition -TimeoutSeconds $WaitSeconds -Condition {
        $status = & $statusScript
        $clients = Get-TmuxClientLines -Distribution $distribution -SessionName $sessionName
        return ([bool]$status.keepAliveRunning -and [bool]$status.sessionAvailable -and $clients.Count -gt 0)
    }
    if (-not $attached) { throw "Workspace did not reach attached state within $WaitSeconds seconds." }
    $proof.launcherAttached = $true
    Write-ProofEvent -Step "launcher-attach" -State "PASS" -Message "tmux_client_attached"

    $proof.surfaceReadyObserved = Read-OperatorObservation -Step "surface-ready" -Prompt "In the WezTerm window, confirm the Bash prompt and tmux status line are visible."

    $agentProbe = Invoke-WslBash -Distribution $distribution -Command "command -v '$selectedAgent' && '$selectedAgent' --version" -TimeoutSeconds 45
    if ($agentProbe.ExitCode -eq 0 -and $agentProbe.Stdout) {
        $proof.agentCommandAck = $true
        Write-ProofEvent -Step "agent-command-ack" -State "PASS" -Message "agent_version_acknowledged" -Data @{
            selectedAgent = $selectedAgent
            selectedModel = $route.selectedModel
            tokenAvailability = $route.tokenAvailability
            routingEvidenceSupplied = $route.supplied
        }
    }
    else {
        Write-ProofEvent -Step "agent-command-ack" -State "FAIL" -Message "agent_probe_failed" -Data @{ selectedAgent = $selectedAgent; output = $agentProbe.Output }
    }

    $proof.behaviorObserved = Read-OperatorObservation -Step "behavior-observed" -Prompt "Inside tmux, open the selected agent and perform one harmless interaction that does not modify files, accounts, or personal data. Confirm that input and response were actually observed."

    if ($NonInteractive) {
        Write-ProofEvent -Step "persistence-cycle" -State "SKIP" -Message "interactive_detach_required"
    }
    else {
        $markerResult = Invoke-WslBash -Distribution $distribution -Command "tmux new-window -d -P -F '#{window_id}' -t '${sessionName}:' -n runtime-proof" -TimeoutSeconds 15
        if ($markerResult.ExitCode -ne 0 -or -not $markerResult.Stdout) {
            throw "Unable to create the disposable tmux marker window. $($markerResult.Output)"
        }
        $markerWindowId = $markerResult.Stdout.Trim()
        $beforeWindows = Get-TmuxWindowLines -Distribution $distribution -SessionName $sessionName
        Write-ProofEvent -Step "persistence-marker" -State "PASS" -Message "disposable_window_created" -Data @{ markerWindowId = $markerWindowId }

        [void](Read-Host "In WezTerm, press Ctrl+B, release, then D to detach. Return to this PowerShell window and press Enter")

        $detached = Wait-ForCondition -TimeoutSeconds $WaitSeconds -Condition {
            return (Get-TmuxClientLines -Distribution $distribution -SessionName $sessionName).Count -eq 0
        }
        if (-not $detached) { throw "tmux client did not detach within $WaitSeconds seconds." }
        $proof.detachObserved = $true
        Write-ProofEvent -Step "detach" -State "PASS" -Message "no_tmux_clients_attached"

        $detachedStatus = & $statusScript
        $detachedWindows = Get-TmuxWindowLines -Distribution $distribution -SessionName $sessionName
        if (-not $detachedStatus.keepAliveRunning -or -not $detachedStatus.sessionAvailable -or -not ($detachedWindows | Where-Object { $_ -like "${markerWindowId}|*" })) {
            throw "tmux session or marker window did not survive detach."
        }
        $proof.persistenceObserved = $true
        Write-ProofEvent -Step "detached-persistence" -State "PASS" -Message "session_and_marker_survived_detach"

        & $startScript
        $reattached = Wait-ForCondition -TimeoutSeconds $WaitSeconds -Condition {
            return (Get-TmuxClientLines -Distribution $distribution -SessionName $sessionName).Count -gt 0
        }
        if (-not $reattached) { throw "Workspace did not reattach within $WaitSeconds seconds." }

        $afterWindows = Get-TmuxWindowLines -Distribution $distribution -SessionName $sessionName
        if (-not ($afterWindows | Where-Object { $_ -like "${markerWindowId}|*" })) {
            throw "The disposable marker window was not present after reattach."
        }
        $proof.reattachObserved = $true
        Write-ProofEvent -Step "reattach" -State "PASS" -Message "same_tmux_session_and_marker_reattached" -Data @{
            beforeWindowCount = $beforeWindows.Count
            afterWindowCount = $afterWindows.Count
        }

        [void](Invoke-WslBash -Distribution $distribution -Command "tmux kill-window -t '$markerWindowId'" -TimeoutSeconds 15)
        Write-ProofEvent -Step "cleanup" -State "PASS" -Message "disposable_marker_removed"
        $markerWindowId = $null
    }
}
catch {
    $failureReason = $_.Exception.Message
    Write-ProofEvent -Step "runtime-proof" -State "FAIL" -Message $failureReason
}
finally {
    if ($markerWindowId) {
        try { [void](Invoke-WslBash -Distribution $distribution -Command "tmux kill-window -t '$markerWindowId' 2>/dev/null || true" -TimeoutSeconds 15) } catch {}
    }

    $proof.runtimeArtifactCollected = $true
    $proof.liveRuntime = (
        $proof.floorSafe -and
        $proof.targetedValidation -and
        ($proof.safeStart -or $SkipLaunch) -and
        $proof.launcherAttached -and
        $proof.surfaceReadyObserved -and
        $proof.agentCommandAck -and
        $proof.behaviorObserved -and
        $proof.detachObserved -and
        $proof.persistenceObserved -and
        $proof.reattachObserved
    )

    $proofLevel = if ($proof.liveRuntime) {
        "live-runtime-observed"
    }
    elseif ($proof.persistenceObserved -and $proof.reattachObserved) {
        "live-session-persistence"
    }
    elseif ($proof.launcherAttached -and $proof.agentCommandAck) {
        "launcher-and-command-ack"
    }
    elseif ($proof.targetedValidation) {
        "targeted-static-validation"
    }
    else {
        "preflight-only"
    }

    $result = [ordered]@{
        schemaVersion = 1
        completedAt = (Get-Date).ToString("o")
        status = if ($failureReason) { "failed" } else { "completed" }
        proofLevel = $proofLevel
        proofCeiling = if ($proof.liveRuntime) { "operator-observed live runtime for terminal/session/agent interaction only" } else { "no higher than $proofLevel" }
        failureReason = $failureReason
        runtimeState = [ordered]@{
            distribution = $distribution
            sessionName = $sessionName
            selectedAgent = $selectedAgent
            routing = $route
            repositoryBranch = $branch
            repositoryHead = $head
        }
        proof = $proof
        events = @($events)
    }

    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $proofPath -Encoding utf8NoBOM
    $events | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress } | Set-Content -LiteralPath $eventPath -Encoding utf8NoBOM
    Write-Host "[PASS] Runtime proof artifact: $proofPath" -ForegroundColor Green
    Write-Host "[PASS] Runtime event log:     $eventPath" -ForegroundColor Green
    Write-Host "Proof level reached: $proofLevel" -ForegroundColor Cyan
}

if ($failureReason) {
    throw $failureReason
}
