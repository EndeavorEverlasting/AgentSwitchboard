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
    [ValidatePattern('^[^\s/]+/[^\s/]+$')][string]$OpenCodeModel,
    [switch]$RequireOpenCodeModelProbe,
    [ValidateRange(5, 120)][int]$ProbeTimeoutSeconds = 20,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranch
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

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $result = [ordered]@{
        ExitCode = $null
        TimedOut = $false
        Output = ""
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $WorkingDirectory

    if ($FilePath.EndsWith(".cmd", [StringComparison]::OrdinalIgnoreCase) -or
        $FilePath.EndsWith(".bat", [StringComparison]::OrdinalIgnoreCase)) {
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
        [void]$psi.ArgumentList.Add("/d")
        [void]$psi.ArgumentList.Add("/s")
        [void]$psi.ArgumentList.Add("/c")
        [void]$psi.ArgumentList.Add($FilePath)
    }
    else {
        $psi.FileName = $FilePath
    }

    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try {
                $process.Kill($true)
                $process.WaitForExit()
            }
            catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    finally {
        $process.Dispose()
    }

    return [pscustomobject]$result
}

function Get-ProbeExcerpt {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "<no output>"
    }
    $normalized = $Text.Trim()
    if ($normalized.Length -le 1200) {
        return $normalized
    }
    return $normalized.Substring($normalized.Length - 1200)
}

function Assert-OpenCodeModelReady {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $openCodeRecord = $State.agents.PSObject.Properties["opencode"]
    if (-not $openCodeRecord -or -not $openCodeRecord.Value.available) {
        $evidence = if ($openCodeRecord) { [string]$openCodeRecord.Value.evidence } else { "no OpenCode state record" }
        throw "Provider-pinned routing requires the READY OpenCode adapter. Evidence: $evidence"
    }

    $openCodePath = [string]$openCodeRecord.Value.commandPath
    if (-not $openCodePath -or -not (Test-Path -LiteralPath $openCodePath -PathType Leaf)) {
        $openCodeCommand = Get-Command opencode -ErrorAction SilentlyContinue
        if (-not $openCodeCommand) {
            throw "The OpenCode command recorded by AgentSwitchboard is unavailable. Rerun setup before requesting '$Model'."
        }
        $openCodePath = $openCodeCommand.Source
    }

    $versionProbe = Invoke-BoundedProcess -FilePath $openCodePath -ArgumentList @("--version") -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds
    if ($versionProbe.TimedOut -or $versionProbe.ExitCode -ne 0) {
        throw "OpenCode version probe failed. $(Get-ProbeExcerpt -Text $versionProbe.Output)"
    }

    $versionMatch = [regex]::Match($versionProbe.Output, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $versionMatch.Success) {
        throw "OpenCode version output could not be parsed: $(Get-ProbeExcerpt -Text $versionProbe.Output)"
    }
    $openCodeVersion = [version]$versionMatch.Groups[1].Value
    $minimumVersion = [version]"1.14.24"
    if ($openCodeVersion -lt $minimumVersion) {
        throw "Provider-pinned routing requires OpenCode $minimumVersion or newer. Detected $openCodeVersion."
    }

    $provider = $Model.Split("/", 2)[0]
    $modelsProbe = Invoke-BoundedProcess -FilePath $openCodePath -ArgumentList @("models", $provider) -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds
    if ($modelsProbe.TimedOut -or $modelsProbe.ExitCode -ne 0) {
        throw "OpenCode could not enumerate provider '$provider'. Connect it interactively first, then rerun. $(Get-ProbeExcerpt -Text $modelsProbe.Output)"
    }
    $modelPattern = '(?m)^\s*' + [regex]::Escape($Model) + '\s*$'
    if ($modelsProbe.Output -notmatch $modelPattern) {
        throw "Requested OpenCode model '$Model' is not available. Run 'opencode models $provider' and pass an exact provider/model ID."
    }

    $readyMarker = "AGENT_SWITCHBOARD_MODEL_READY"
    $spawnPrompt = "Return exactly $readyMarker. Do not inspect files, call tools, or modify state."
    $spawnProbe = Invoke-BoundedProcess `
        -FilePath $openCodePath `
        -ArgumentList @("run", "--model", $Model, "--format", "json", $spawnPrompt) `
        -WorkingDirectory $WorkingDirectory `
        -TimeoutSeconds $TimeoutSeconds
    if ($spawnProbe.TimedOut) {
        throw "OpenCode model spawnability probe timed out after $TimeoutSeconds seconds. No repository sprint was started."
    }
    if ($spawnProbe.ExitCode -ne 0 -or $spawnProbe.Output -notmatch [regex]::Escape($readyMarker)) {
        throw "OpenCode model spawnability probe did not return the success marker. Authenticate/configure '$provider' interactively, then rerun. $(Get-ProbeExcerpt -Text $spawnProbe.Output)"
    }

    return [pscustomobject]@{
        CommandPath = $openCodePath
        Version = $openCodeVersion.ToString()
        Model = $Model
        Marker = $readyMarker
    }
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$agentSpec = Resolve-AgentSpec -RequestedAgent $Agent -State $state

if ($OpenCodeModel -and $agentSpec -ne "opencode") {
    throw "-OpenCodeModel can only be used with the native opencode GNHF adapter. Resolved adapter: $agentSpec"
}
if ($RequireOpenCodeModelProbe -and -not $OpenCodeModel) {
    throw "-RequireOpenCodeModelProbe requires -OpenCodeModel provider/model."
}

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

$insideWorkTree = (Invoke-Git -Arguments @("rev-parse", "--is-inside-work-tree") | Select-Object -First 1).Trim()
if ($insideWorkTree -ne "true") {
    throw "Target path is not a Git working tree: $RepoPath"
}

$dirty = @(Invoke-Git -Arguments @("status", "--porcelain=v1"))
$dirty = @($dirty | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($dirty.Count -gt 0) {
    throw "GNHF requires a clean target worktree. Existing changes:`n$($dirty -join [Environment]::NewLine)"
}

$branch = (Invoke-Git -Arguments @("branch", "--show-current") | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw "Detached HEAD is not allowed for an unattended sprint."
}
if ($branch.StartsWith("gnhf/")) {
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

$modelProbe = $null
$tempProbeRoot = $null
if ($OpenCodeModel -and $RequireOpenCodeModelProbe) {
    $tempProbeRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-switchboard-model-probe-{0}" -f [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $tempProbeRoot -Force)
    try {
        $modelProbe = Assert-OpenCodeModelReady -State $state -Model $OpenCodeModel -WorkingDirectory $tempProbeRoot -TimeoutSeconds $ProbeTimeoutSeconds
    }
    finally {
        if (Test-Path -LiteralPath $tempProbeRoot) {
            Remove-Item -LiteralPath $tempProbeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$logsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$safeName = ($Name -replace "[^A-Za-z0-9._-]", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($safeName)) {
    $safeName = "gnhf-sprint"
}
$runLogDir = Ensure-GnhfFleetDirectory -Path (Join-Path $logsRoot "$timestamp-$safeName")
$transcriptPath = Join-Path $runLogDir "launcher-transcript.txt"
$summaryPath = Join-Path $runLogDir "launcher-summary.json"

$summary = [ordered]@{
    schemaVersion = 1
    name = $Name
    startedAt = (Get-Date).ToString("o")
    repoPath = $RepoPath
    baseBranch = $branch
    agentRequested = $Agent
    agentSpec = $agentSpec
    providerRoute = if ($OpenCodeModel) { "opencode:$OpenCodeModel" } else { $null }
    providerProbeRequired = [bool]$RequireOpenCodeModelProbe
    providerProbeEvidence = if ($modelProbe) {
        [ordered]@{
            commandPath = $modelProbe.CommandPath
            openCodeVersion = $modelProbe.Version
            model = $modelProbe.Model
            successMarker = $modelProbe.Marker
            timeoutSeconds = $ProbeTimeoutSeconds
        }
    }
    else { $null }
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
[void]$gnhfArguments.Add("--worktree")
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

$originalInlineConfig = [Environment]::GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", "Process")
if ($OpenCodeModel) {
    $inlineConfig = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"
        model = $OpenCodeModel
    }
    if (-not [string]::IsNullOrWhiteSpace($originalInlineConfig)) {
        try {
            $existingConfig = $originalInlineConfig | ConvertFrom-Json -AsHashtable
            if ($null -eq $existingConfig) {
                throw "inline config is empty"
            }
            $existingConfig["model"] = $OpenCodeModel
            if (-not $existingConfig.ContainsKey('$schema')) {
                $existingConfig['$schema'] = "https://opencode.ai/config.json"
            }
            $inlineConfig = $existingConfig
        }
        catch {
            throw "Existing OPENCODE_CONFIG_CONTENT is not valid JSON and cannot be safely merged: $($_.Exception.Message)"
        }
    }
    $env:OPENCODE_CONFIG_CONTENT = $inlineConfig | ConvertTo-Json -Depth 20 -Compress
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
    Write-Host "Agent:      $agentSpec"
    if ($OpenCodeModel) {
        Write-Host "Model:      $OpenCodeModel"
        Write-Host "Probe:      $([bool]$RequireOpenCodeModelProbe)"
    }
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
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", $originalInlineConfig, "Process")
    $summary.exitCode = $exitCode
    $summary.completedAt = (Get-Date).ToString("o")
    [void](Ensure-GnhfFleetParentDirectory -Path $summaryPath)
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}

Write-Host "`nLauncher summary: $summaryPath" -ForegroundColor Cyan
exit $exitCode
