[CmdletBinding()]
param(
    [string]$RepoPath = (Get-Location).Path,
    [ValidateSet("opencode", "deepseek", "goose", "agy", "copilot", "hermes")]
    [string]$Agent = "opencode",
    [string]$PromptPath,
    [string]$Prompt,
    [string]$Name,
    [ValidateRange(1, 100)]
    [int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)]
    [int]$MaxTokens = 250000,
    [string]$StopWhen = "The bounded sprint is committed in the isolated worktree, targeted validation passes, and no unrelated files changed.",
    [ValidatePattern('^deepseek/[^\s/]+$')]
    [string]$DeepSeekModel = "deepseek/deepseek-v4-pro",
    [ValidateRange(5, 120)]
    [int]$ProbeTimeoutSeconds = 20,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$Bootstrap,
    [switch]$InstallOpenCodeAndCopilot,
    [switch]$SkipHermesInstall,
    [switch]$PushBranch,
    [switch]$ListAgents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Show-AgentReadiness {
    param([Parameter(Mandatory)]$State)

    Write-Host "Agent readiness:" -ForegroundColor Cyan
    foreach ($agentName in @("opencode", "deepseek", "goose", "agy", "copilot", "hermes")) {
        $stateName = if ($agentName -eq "deepseek") { "opencode" } else { $agentName }
        $property = $State.agents.PSObject.Properties[$stateName]
        if (-not $property) {
            Write-Host ("  {0,-9} UNKNOWN  no state record" -f $agentName) -ForegroundColor Yellow
            continue
        }

        $record = $property.Value
        $status = if ($record.available) { "READY" } else { "BLOCKED" }
        $color = if ($record.available) { "Green" } else { "Yellow" }
        $evidence = if ($agentName -eq "deepseek" -and $record.available) {
            "OpenCode adapter is ready; exact DeepSeek provider/model authentication is probed at launch."
        }
        elseif ($agentName -eq "deepseek") {
            "DeepSeek route is blocked because OpenCode is not ready. $($record.evidence)"
        }
        else {
            [string]$record.evidence
        }
        Write-Host ("  {0,-9} {1,-7} {2}" -f $agentName, $status, $evidence) -ForegroundColor $color
    }
}

function Install-OperatorLauncher {
    param([Parameter(Mandatory)][string]$DestinationRoot)

    $DestinationRoot = Ensure-GnhfFleetDirectory -Path $DestinationRoot
    $destinationScript = Join-Path $DestinationRoot "Start-AgentSwitchboard.ps1"
    $sourceScript = [IO.Path]::GetFullPath($PSCommandPath)
    $destinationFullPath = [IO.Path]::GetFullPath($destinationScript)
    if (-not $sourceScript.Equals($destinationFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $sourceScript -Destination $destinationScript -Force
    }

    $cmdLauncher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AgentSwitchboard.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
    Set-Content -LiteralPath (Join-Path $DestinationRoot "agent-switchboard.cmd") -Value $cmdLauncher -Encoding ascii
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

function Assert-DeepSeekRouteReady {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $openCodeProperty = $State.agents.PSObject.Properties["opencode"]
    if (-not $openCodeProperty -or -not $openCodeProperty.Value.available) {
        $evidence = if ($openCodeProperty) { [string]$openCodeProperty.Value.evidence } else { "no OpenCode state record" }
        throw "DeepSeek routing requires the READY OpenCode adapter. Evidence: $evidence"
    }

    $openCodePath = [string]$openCodeProperty.Value.commandPath
    if (-not $openCodePath -or -not (Test-Path -LiteralPath $openCodePath -PathType Leaf)) {
        $openCodeCommand = Get-Command opencode -ErrorAction SilentlyContinue
        if (-not $openCodeCommand) {
            throw "The OpenCode command recorded by AgentSwitchboard is unavailable. Rerun setup before requesting DeepSeek."
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
        throw "DeepSeek routing requires OpenCode $minimumVersion or newer. Detected $openCodeVersion."
    }

    $modelsProbe = Invoke-BoundedProcess -FilePath $openCodePath -ArgumentList @("models", "deepseek") -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds
    if ($modelsProbe.TimedOut -or $modelsProbe.ExitCode -ne 0) {
        throw "OpenCode could not enumerate the DeepSeek provider. Connect it interactively first, then rerun. $(Get-ProbeExcerpt -Text $modelsProbe.Output)"
    }
    $modelPattern = '(?m)^\s*' + [regex]::Escape($Model) + '\s*$'
    if ($modelsProbe.Output -notmatch $modelPattern) {
        throw "Requested DeepSeek model '$Model' is not available. Run 'opencode models deepseek' and pass an exact provider/model ID."
    }

    $readyMarker = "AGENT_SWITCHBOARD_MODEL_READY"
    $spawnPrompt = "Return exactly $readyMarker. Do not inspect files, call tools, or modify state."
    $spawnProbe = Invoke-BoundedProcess `
        -FilePath $openCodePath `
        -ArgumentList @("run", "--model", $Model, "--format", "json", $spawnPrompt) `
        -WorkingDirectory $WorkingDirectory `
        -TimeoutSeconds $TimeoutSeconds
    if ($spawnProbe.TimedOut) {
        throw "DeepSeek spawnability probe timed out after $TimeoutSeconds seconds. No repository sprint was started."
    }
    if ($spawnProbe.ExitCode -ne 0 -or $spawnProbe.Output -notmatch [regex]::Escape($readyMarker)) {
        throw "DeepSeek spawnability probe did not return the success marker. Authenticate/configure DeepSeek in OpenCode interactively, then rerun. $(Get-ProbeExcerpt -Text $spawnProbe.Output)"
    }

    return [pscustomobject]@{
        commandPath = $openCodePath
        openCodeVersion = $openCodeVersion.ToString()
        model = $Model
        successMarker = $readyMarker
        timeoutSeconds = $TimeoutSeconds
    }
}

function Set-OpenCodeModelOverride {
    param(
        [Parameter(Mandatory)][string]$Model,
        [AllowEmptyString()][string]$ExistingInlineConfig
    )

    $inlineConfig = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"
        model = $Model
    }
    if (-not [string]::IsNullOrWhiteSpace($ExistingInlineConfig)) {
        try {
            $existingConfig = $ExistingInlineConfig | ConvertFrom-Json -AsHashtable
            if ($null -eq $existingConfig) {
                throw "inline config is empty"
            }
            $existingConfig["model"] = $Model
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

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "AgentSwitchboard requires PowerShell 7. Open pwsh and rerun this command."
}
if ($Prompt -and $PromptPath) {
    throw "Use either -Prompt or -PromptPath, not both."
}
if ([string]::IsNullOrWhiteSpace($StopWhen)) {
    throw "-StopWhen must describe an observable completion condition."
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$repoName = Split-Path -Leaf $RepoPath
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Join-Path $InstallRoot "state.json"

if ($Bootstrap) {
    Write-Section "Bootstrap or repair AgentSwitchboard"
    $setupPath = Resolve-GnhfFleetFile -Path (Join-Path $PSScriptRoot "Setup-AgentSwitchboard.ps1") -Description "robust setup orchestrator"

    $setupParameters = @{
        DefaultRepoPath = $RepoPath
        InstallRoot = $InstallRoot
    }
    if ($InstallOpenCodeAndCopilot) {
        $setupParameters["InstallOpenCodeAndCopilot"] = $true
    }
    if ($SkipHermesInstall) {
        $setupParameters["SkipHermesInstall"] = $true
    }

    & $setupPath @setupParameters
}

if (-not (Test-Path -LiteralPath $statePath)) {
    $bootstrapCommand = "pwsh -File `"$PSCommandPath`" -RepoPath `"$RepoPath`" -Bootstrap -ListAgents"
    throw "Fleet state not found: $statePath. Run the bootstrap/readiness probe:`n$bootstrapCommand"
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Expected fleet state to be a file, but found a directory: $statePath"
}

$InstallRoot = Ensure-GnhfFleetDirectory -Path $InstallRoot
Install-OperatorLauncher -DestinationRoot $InstallRoot
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

if ($ListAgents) {
    Show-AgentReadiness -State $state
    Write-Host "`nLauncher: $(Join-Path $InstallRoot 'agent-switchboard.cmd')" -ForegroundColor Cyan
    Write-Host "Setup logs: $(Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\setup-logs')" -ForegroundColor Cyan
    return
}

$stateAgentName = if ($Agent -eq "deepseek") { "opencode" } else { $Agent }
$agentProperty = $state.agents.PSObject.Properties[$stateAgentName]
if (-not $agentProperty) {
    throw "Agent '$Agent' has no adapter record in $statePath. Rerun with -Bootstrap -ListAgents to refresh detection."
}

$agentRecord = $agentProperty.Value
if (-not $agentRecord.available) {
    throw "Agent '$Agent' is blocked. Evidence: $($agentRecord.evidence)"
}

$defaultPromptByAgent = @{
    opencode = "opencode-implementation.md"
    deepseek = "opencode-implementation.md"
    goose = "goose-validation.md"
    agy = "agy-architecture.md"
    copilot = "copilot-tests.md"
    hermes = "hermes-implementation.md"
}

$runtimePromptPath = $null
if ($Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw "-Prompt cannot be blank."
    }

    $runtimePromptRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "runtime-prompts")
    $runtimePromptPath = Join-Path $runtimePromptRoot ("operator-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    Set-Content -LiteralPath $runtimePromptPath -Value $Prompt -Encoding utf8NoBOM
    $PromptPath = $runtimePromptPath
}
elseif ($PromptPath) {
    $PromptPath = Resolve-GnhfFleetFile -Path $PromptPath -Description "sprint prompt"
}
else {
    if (-not $repoName.Equals("AgentSwitchboard", [StringComparison]::OrdinalIgnoreCase)) {
        throw "No sprint prompt was supplied for '$repoName'. Copy a bounded sprint prompt and pass -Prompt (Get-Clipboard -Raw), or pass -PromptPath. Bundled default prompts are scoped specifically to AgentSwitchboard."
    }

    $sourcePromptPath = Join-Path $PSScriptRoot (Join-Path "prompts" $defaultPromptByAgent[$Agent])
    $installedPromptPath = Join-Path $InstallRoot (Join-Path "prompts" $defaultPromptByAgent[$Agent])
    if (Test-Path -LiteralPath $sourcePromptPath -PathType Leaf) {
        $PromptPath = (Get-Item -LiteralPath $sourcePromptPath -Force).FullName
    }
    elseif (Test-Path -LiteralPath $installedPromptPath -PathType Leaf) {
        $PromptPath = (Get-Item -LiteralPath $installedPromptPath -Force).FullName
    }
    else {
        throw "Default prompt not found for '$Agent'. Supply -PromptPath explicitly or rerun -Bootstrap to repair installed prompts."
    }
}

if (-not $Name) {
    $Name = "$repoName-$Agent"
}

$sprintLauncher = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "Start-GnhfSprint.ps1") -Description "bounded sprint launcher"
$arguments = [System.Collections.Generic.List[string]]::new()
foreach ($argument in @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $sprintLauncher,
    "-RepoPath", $RepoPath,
    "-Agent", $(if ($Agent -eq "deepseek") { "opencode" } else { $Agent }),
    "-PromptPath", $PromptPath,
    "-Name", $Name,
    "-MaxIterations", [string]$MaxIterations,
    "-MaxTokens", [string]$MaxTokens,
    "-StopWhen", $StopWhen
)) {
    [void]$arguments.Add($argument)
}
if ($PushBranch) {
    [void]$arguments.Add("-PushBranch")
}

Write-Section "Launch coding sprint"
Write-Host "Repo:       $RepoPath"
Write-Host "Agent:      $Agent"
if ($Agent -eq "deepseek") {
    Write-Host "Provider:   DeepSeek through OpenCode"
    Write-Host "Model:      $DeepSeekModel"
}
Write-Host "Prompt:     $PromptPath"
Write-Host "Iterations: $MaxIterations"
Write-Host "Token cap:  $MaxTokens"
Write-Host "Push:       $([bool]$PushBranch)"
Write-Host "Launcher:   $sprintLauncher"

$originalInlineConfig = [Environment]::GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", "Process")
$routeEvidence = $null
$routeEvidencePath = $null
$exitCode = 1
try {
    if ($Agent -eq "deepseek") {
        $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-switchboard-deepseek-probe-{0}" -f [guid]::NewGuid().ToString("N"))
        [void](New-Item -ItemType Directory -Path $probeRoot -Force)
        try {
            $probe = Assert-DeepSeekRouteReady -State $state -Model $DeepSeekModel -WorkingDirectory $probeRoot -TimeoutSeconds $ProbeTimeoutSeconds
        }
        finally {
            if (Test-Path -LiteralPath $probeRoot) {
                Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Set-OpenCodeModelOverride -Model $DeepSeekModel -ExistingInlineConfig $originalInlineConfig
        $routeEvidenceRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs\provider-routes")
        $routeEvidencePath = Join-Path $routeEvidenceRoot ("{0}-{1}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"), (($Name -replace '[^A-Za-z0-9._-]', '-').Trim('-')))
        $routeEvidence = [ordered]@{
            schemaVersion = 1
            route = "deepseek-through-opencode"
            operatorAgent = "deepseek"
            gnhfAgent = "opencode"
            model = $DeepSeekModel
            commandPath = $probe.commandPath
            openCodeVersion = $probe.openCodeVersion
            successMarker = $probe.successMarker
            timeoutSeconds = $probe.timeoutSeconds
            repoPath = $RepoPath
            promptPath = $PromptPath
            startedAt = (Get-Date).ToString("o")
            sprintExitCode = $null
            completedAt = $null
        }
        $routeEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $routeEvidencePath -Encoding utf8NoBOM

        Write-Host "Route proof: $routeEvidencePath" -ForegroundColor Cyan
    }

    & pwsh @arguments
    $exitCode = $LASTEXITCODE
}
finally {
    [Environment]::SetEnvironmentVariable("OPENCODE_CONFIG_CONTENT", $originalInlineConfig, "Process")
    if ($null -ne $routeEvidence -and $routeEvidencePath) {
        $routeEvidence.sprintExitCode = $exitCode
        $routeEvidence.completedAt = (Get-Date).ToString("o")
        $routeEvidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $routeEvidencePath -Encoding utf8NoBOM
    }
    if ($runtimePromptPath -and (Test-Path -LiteralPath $runtimePromptPath -PathType Leaf)) {
        Remove-Item -LiteralPath $runtimePromptPath -Force
    }
}

if ($exitCode -ne 0) {
    throw "AgentSwitchboard sprint failed with exit code $exitCode. Review the launcher summary under '$InstallRoot\logs'."
}

Write-Host "`nSprint completed successfully. Review the generated GNHF worktree and launcher summary before merging." -ForegroundColor Green
