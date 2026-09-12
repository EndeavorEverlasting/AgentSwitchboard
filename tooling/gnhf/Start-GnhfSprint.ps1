[CmdletBinding(DefaultParameterSetName = "PromptFile")]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$Agent,
    [Parameter(Mandatory, ParameterSetName = "PromptFile")][string]$PromptPath,
    [Parameter(Mandatory, ParameterSetName = "PromptText")][string]$Prompt,
    [string]$Name = "gnhf-sprint",
    [ValidateRange(1, 100)][int]$MaxIterations = 6,
    [ValidateRange(0, 1000000000)][int]$MaxTokens = 500000,
    [Parameter(Mandatory)][string]$StopWhen,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranch,
    [switch]$RepairCurrentGnhfBranch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Resolve-AgentSpec {
    param(
        [Parameter(Mandatory)][string]$RequestedAgent,
        [Parameter(Mandatory)]$State
    )

    $normalized = $RequestedAgent.ToLowerInvariant()
    if ($normalized.StartsWith("acp:")) {
        return $RequestedAgent
    }

    $knownNative = @("claude", "codex", "copilot", "pi", "rovodev", "opencode")
    if ($knownNative -contains $normalized -and $normalized -notin @("copilot", "opencode")) {
        return $normalized
    }

    $property = $State.agents.PSObject.Properties[$normalized]
    if (-not $property) {
        throw "Unknown agent '$RequestedAgent'. Use a native GNHF agent name or an acp:<command> specification."
    }

    $agentRecord = $property.Value
    if (-not $agentRecord.available) {
        throw "Agent '$RequestedAgent' is not ready. Evidence: $($agentRecord.evidence)"
    }

    return [string]$agentRecord.agentSpec
}

function Get-BoundedGnhfHelp {
    param(
        [Parameter(Mandatory)][string]$CommandPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [ValidateRange(5, 60)][int]$TimeoutSeconds = 15
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $WorkingDirectory

    if ($CommandPath.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
        $psi.FileName = "pwsh.exe"
        [void]$psi.ArgumentList.Add("-NoLogo")
        [void]$psi.ArgumentList.Add("-NoProfile")
        [void]$psi.ArgumentList.Add("-NonInteractive")
        [void]$psi.ArgumentList.Add("-File")
        [void]$psi.ArgumentList.Add($CommandPath)
    }
    elseif ($CommandPath.EndsWith(".cmd", [StringComparison]::OrdinalIgnoreCase) -or $CommandPath.EndsWith(".bat", [StringComparison]::OrdinalIgnoreCase)) {
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
        [void]$psi.ArgumentList.Add("/d")
        [void]$psi.ArgumentList.Add("/s")
        [void]$psi.ArgumentList.Add("/c")
        [void]$psi.ArgumentList.Add($CommandPath)
    }
    else {
        $psi.FileName = $CommandPath
    }
    [void]$psi.ArgumentList.Add("--help")

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch {}
            try { $process.WaitForExit(5000) | Out-Null } catch {}
        }
        $stdoutReady = $false; $stderrReady = $false
        try { $stdoutReady = $stdoutTask.Wait(5000) } catch {}
        try { $stderrReady = $stderrTask.Wait(5000) } catch {}
        if ($timedOut -or -not ($stdoutReady -and $stderrReady)) {
            throw "GNHF help probe timed out or failed to drain output within bounded grace periods."
        }
        $output = (($stdoutTask.GetAwaiter().GetResult(), $stderrTask.GetAwaiter().GetResult()) -join [Environment]::NewLine).Trim()
        if ($process.ExitCode -ne 0) {
            throw "GNHF help probe failed with exit code $($process.ExitCode)."
        }
        return $output
    }
    finally { $process.Dispose() }
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$agentSpec = Resolve-AgentSpec -RequestedAgent $Agent -State $state

if ($PSCmdlet.ParameterSetName -eq "PromptFile") {
    $PromptPath = Resolve-GnhfFleetFile -Path $PromptPath -Description "sprint prompt"
    $objective = Get-Content -LiteralPath $PromptPath -Raw
}
else {
    $objective = $Prompt
}

if ([string]::IsNullOrWhiteSpace($objective)) {
    throw "The sprint prompt is empty."
}
if ($RepairCurrentGnhfBranch -and $PushBranch) {
    throw "-RepairCurrentGnhfBranch cannot be combined with -PushBranch. Repair mode is local-only."
}

$insideOutput = @(Invoke-Git -Arguments @("rev-parse", "--is-inside-work-tree"))
$insideWorkTree = if ($insideOutput.Count -gt 0) { [string]$insideOutput[0] } else { "" }
$insideWorkTree = $insideWorkTree.Trim()
if ($insideWorkTree -ne "true") {
    throw "Target path is not a Git working tree: $RepoPath"
}

$repoRootOutput = @(Invoke-Git -Arguments @("rev-parse", "--show-toplevel"))
$repoRoot = if ($repoRootOutput.Count -gt 0) { [IO.Path]::GetFullPath(([string]$repoRootOutput[0]).Trim()) } else { $RepoPath }

$dirty = @(Invoke-Git -Arguments @("status", "--porcelain=v1"))
$dirty = @($dirty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($dirty.Count -gt 0) {
    throw "GNHF requires a clean target worktree. Existing changes:`n$($dirty -join [Environment]::NewLine)"
}

$branchOutput = @(Invoke-Git -Arguments @("branch", "--show-current"))
$branch = if ($branchOutput.Count -gt 0) { [string]$branchOutput[0] } else { "" }
$branch = $branch.Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Detached HEAD is not allowed for an unattended sprint."
}
if ($RepairCurrentGnhfBranch) {
    if (-not $branch.StartsWith("gnhf/", [StringComparison]::OrdinalIgnoreCase)) {
        throw "-RepairCurrentGnhfBranch may run only inside an existing gnhf/* worktree. Current branch: $branch"
    }

    $gitDirOutput = @(Invoke-Git -Arguments @("rev-parse", "--path-format=absolute", "--git-dir"))
    $commonDirOutput = @(Invoke-Git -Arguments @("rev-parse", "--path-format=absolute", "--git-common-dir"))
    $gitDir = if ($gitDirOutput.Count -gt 0) { [IO.Path]::GetFullPath(([string]$gitDirOutput[0]).Trim()) } else { "" }
    $commonDir = if ($commonDirOutput.Count -gt 0) { [IO.Path]::GetFullPath(([string]$commonDirOutput[0]).Trim()) } else { "" }
    if ([string]::IsNullOrWhiteSpace($gitDir) -or [string]::IsNullOrWhiteSpace($commonDir) -or
        $gitDir.Equals($commonDir, [StringComparison]::OrdinalIgnoreCase)) {
        throw "-RepairCurrentGnhfBranch requires a linked Git worktree; the primary checkout is not an authorized repair target."
    }

    $registered = @(Invoke-Git -Arguments @("worktree", "list", "--porcelain"))
    $registeredPaths = @($registered | Where-Object { ([string]$_).StartsWith("worktree ") } | ForEach-Object {
        [IO.Path]::GetFullPath(([string]$_).Substring(9).Trim())
    })
    if (-not ($registeredPaths | Where-Object { $_.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) })) {
        throw "-RepairCurrentGnhfBranch requires a currently registered linked Git worktree. Target: $repoRoot"
    }
}
elseif ($branch.StartsWith("gnhf/", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Launch worktree mode from a non-GNHF base branch. Current branch: $branch"
}

$recentCommits = Invoke-Git -Arguments @("log", "--oneline", "--decorate", "-5")
$configuredGnhfPath = [string]$state.gnhf.commandPath
$gnhfPath = $null
if ($configuredGnhfPath -and (Test-Path -LiteralPath $configuredGnhfPath -PathType Leaf)) {
    $gnhfPath = (Get-Item -LiteralPath $configuredGnhfPath -Force).FullName
}
else {
    $gnhfCommand = Get-Command gnhf -ErrorAction SilentlyContinue
    if (-not $gnhfCommand) {
        throw "The configured GNHF executable is unavailable: $configuredGnhfPath. Rerun the installer to repair state."
    }
    $gnhfPath = $gnhfCommand.Source
}

if ($RepairCurrentGnhfBranch) {
    $gnhfHelp = Get-BoundedGnhfHelp -CommandPath $gnhfPath -WorkingDirectory $RepoPath
    if ($gnhfHelp -notmatch '(?m)(^|\s)--current-branch([\s,]|$)') {
        throw "Installed GNHF does not advertise --current-branch, so repair mode is unavailable. Upgrade/repair GNHF or rerun the token-saving loop with repair cycles disabled."
    }
}

$logsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs")
$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), [guid]::NewGuid().ToString("N")
$safeName = ($Name -replace "[^A-Za-z0-9._-]", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($safeName)) {
    $safeName = "gnhf-sprint"
}
$runLogDir = Ensure-GnhfFleetDirectory -Path (Join-Path $logsRoot "$runId-$safeName")
$transcriptPath = Join-Path $runLogDir "launcher-transcript.txt"
$summaryPath = Join-Path $runLogDir "launcher-summary.json"

$executionMode = if ($RepairCurrentGnhfBranch) { "current-branch-repair" } else { "isolated-worktree" }
$summary = [ordered]@{
    schemaVersion = 1
    runId = $runId
    name = $Name
    startedAt = (Get-Date).ToString("o")
    repoPath = $RepoPath
    baseBranch = $branch
    executionMode = $executionMode
    agentRequested = $Agent
    agentSpec = $agentSpec
    maxIterations = $MaxIterations
    maxTokens = $MaxTokens
    stopWhen = $StopWhen
    pushBranch = [bool]$PushBranch
    recentCommits = @($recentCommits)
    exitCode = $null
    completedAt = $null
    launcherLog = $transcriptPath
    promptSource = $PSCmdlet.ParameterSetName
    promptUtf8Bytes = [Text.Encoding]::UTF8.GetByteCount($objective)
}

$gnhfArguments = [System.Collections.Generic.List[string]]::new()
[void]$gnhfArguments.Add("--agent")
[void]$gnhfArguments.Add($agentSpec)
if ($RepairCurrentGnhfBranch) {
    [void]$gnhfArguments.Add("--current-branch")
}
else {
    [void]$gnhfArguments.Add("--worktree")
}
[void]$gnhfArguments.Add("--max-iterations")
[void]$gnhfArguments.Add([string]$MaxIterations)
if ($MaxTokens -gt 0) {
    [void]$gnhfArguments.Add("--max-tokens")
    [void]$gnhfArguments.Add([string]$MaxTokens)
}
[void]$gnhfArguments.Add("--stop-when")
[void]$gnhfArguments.Add($StopWhen)
[void]$gnhfArguments.Add("--prevent-sleep")
[void]$gnhfArguments.Add("on")
if ($PushBranch) {
    [void]$gnhfArguments.Add("--push")
}

$env:GNHF_TELEMETRY = "0"
$exitCode = 1
$transcriptStarted = $false
$oldLocation = Get-Location

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host "`n=== GNHF SPRINT ===" -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Base:       $branch"
    Write-Host "Mode:       $executionMode"
    Write-Host "Agent:      $agentSpec"
    Write-Host "Iterations: $MaxIterations"
    Write-Host "Token cap:  $MaxTokens"
    Write-Host "Push:       $([bool]$PushBranch)"
    Write-Host "Stop when:  $StopWhen"
    Write-Host "`nRecent commits:"
    $recentCommits | ForEach-Object { Write-Host "  $_" }

    Set-Location -LiteralPath $RepoPath
    $objective | & $gnhfPath @gnhfArguments
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    $exitCode = 1
}
finally {
    Set-Location -LiteralPath $oldLocation.Path
    $summary.exitCode = $exitCode
    $summary.completedAt = (Get-Date).ToString("o")
    [void](Ensure-GnhfFleetParentDirectory -Path $summaryPath)
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}

Write-Host "`nLauncher summary: $summaryPath" -ForegroundColor Cyan
exit $exitCode
