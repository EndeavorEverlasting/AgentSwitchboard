[CmdletBinding()]
param(
    [string]$ConfigPath = "$env:LOCALAPPDATA\AgentSwitchboard\Nap\nap-sprint.json",
    [string]$RepoPath,
    [ValidateSet("hermes", "opencode", "goose", "copilot", "agy")]
    [string]$Agent,
    [string]$Prompt,
    [string]$PromptPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required. Run this launcher with pwsh."
}
if ($Prompt -and $PromptPath) {
    throw "Use either -Prompt or -PromptPath, not both."
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Get-AgentSelection {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string[]]$Candidates
    )

    $blocked = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $Candidates) {
        $property = $State.agents.PSObject.Properties[$candidate]
        if (-not $property) {
            [void]$blocked.Add([ordered]@{ agent = $candidate; evidence = "No readiness record exists." })
            continue
        }

        $record = $property.Value
        if ($record.available) {
            return [pscustomobject]@{
                Agent = $candidate
                Record = $record
                Blocked = @($blocked)
            }
        }
        [void]$blocked.Add([ordered]@{ agent = $candidate; evidence = [string]$record.evidence })
    }

    return [pscustomobject]@{
        Agent = $null
        Record = $null
        Blocked = @($blocked)
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$runRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\Nap\runs\$timestamp"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$transcriptPath = Join-Path $runRoot "nap-transcript.txt"
$summaryPath = Join-Path $runRoot "nap-summary.json"
$transcriptStarted = $false
$exitCode = 1
$failure = $null
$innerLogPath = $null
$selectedAgent = $null
$selectedAgentEvidence = $null
$blockedAgents = @()
$repoBranch = $null
$repoHead = $null
$promptSource = $null
$promptHash = $null
$promptUtf8Bytes = 0
$launched = $false
$startedAt = Get-Date

$summary = [ordered]@{
    schemaVersion = 1
    runId = "nap-$timestamp"
    startedAt = $startedAt.ToString("o")
    completedAt = $null
    status = "starting"
    planOnly = [bool]$PlanOnly
    configPath = [IO.Path]::GetFullPath($ConfigPath)
    repoPath = $null
    baseBranch = $null
    baseHead = $null
    preferredAgents = @()
    selectedAgent = $null
    selectedAgentEvidence = $null
    blockedAgents = @()
    promptSource = $null
    promptSha256 = $null
    promptUtf8Bytes = 0
    maxIterations = $null
    maxTokens = $null
    stopWhen = $null
    pushBranch = $false
    bootstrapAttempted = $false
    launched = $false
    preventSleep = $true
    innerLogPath = $null
    transcriptPath = $transcriptPath
    exitCode = $null
    failure = $null
}

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        $configureScript = Join-Path $PSScriptRoot "Configure-NapSprint.ps1"
        throw "Nap configuration not found: $ConfigPath. Run: pwsh -NoLogo -NoProfile -File `"$configureScript`""
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ([int]$config.schemaVersion -ne 1) {
        throw "Unsupported nap configuration schemaVersion '$($config.schemaVersion)'. Expected 1."
    }

    $configuredRepoPath = if ($RepoPath) { $RepoPath } else { [string]$config.repoPath }
    if ([string]::IsNullOrWhiteSpace($configuredRepoPath) -or $configuredRepoPath -eq "__REPO_PATH__") {
        throw "The nap configuration does not contain a real repoPath. Rerun Configure-NapSprint.ps1."
    }
    $RepoPath = (Resolve-Path -LiteralPath $configuredRepoPath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "Target repository path is not a directory: $RepoPath"
    }
    $summary.repoPath = $RepoPath

    $insideWorktree = (Invoke-Git -Repository $RepoPath -Arguments @("rev-parse", "--is-inside-work-tree") | Select-Object -First 1).Trim()
    if ($insideWorktree -ne "true") {
        throw "Target path is not a Git working tree: $RepoPath"
    }

    $dirty = @(Invoke-Git -Repository $RepoPath -Arguments @("status", "--porcelain=v1") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dirty.Count -gt 0) {
        throw "Nap sprint requires a clean target checkout. Preserve or isolate these changes first:`n$($dirty -join [Environment]::NewLine)"
    }

    $repoBranch = (Invoke-Git -Repository $RepoPath -Arguments @("branch", "--show-current") | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($repoBranch)) {
        throw "Detached HEAD is not allowed for an unattended sprint."
    }
    if ($repoBranch.StartsWith("gnhf/")) {
        throw "Launch from a normal base branch, not an existing GNHF worktree branch: $repoBranch"
    }
    $repoHead = (Invoke-Git -Repository $RepoPath -Arguments @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
    $summary.baseBranch = $repoBranch
    $summary.baseHead = $repoHead

    if ($Prompt) {
        $objective = $Prompt
        $promptSource = "parameter"
    }
    elseif ($PromptPath) {
        $resolvedPromptPath = (Resolve-Path -LiteralPath $PromptPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolvedPromptPath -PathType Leaf)) {
            throw "Prompt path is not a file: $resolvedPromptPath"
        }
        $objective = Get-Content -LiteralPath $resolvedPromptPath -Raw
        $promptSource = "parameter-file:$resolvedPromptPath"
    }
    elseif ([string]$config.promptSource -eq "file") {
        $configuredPromptPath = [string]$config.promptPath
        if ([string]::IsNullOrWhiteSpace($configuredPromptPath)) {
            throw "promptSource=file requires promptPath in the nap configuration."
        }
        $configuredPromptPath = (Resolve-Path -LiteralPath $configuredPromptPath -ErrorAction Stop).Path
        $objective = Get-Content -LiteralPath $configuredPromptPath -Raw
        $promptSource = "config-file:$configuredPromptPath"
    }
    else {
        try {
            $objective = Get-Clipboard -Raw
        }
        catch {
            throw "Could not read the Windows clipboard. Supply -Prompt or -PromptPath. $($_.Exception.Message)"
        }
        $promptSource = "clipboard"
    }

    if ([string]::IsNullOrWhiteSpace($objective)) {
        throw "The sprint prompt is empty. Copy a bounded sprint prompt to the clipboard or configure a prompt file."
    }
    $promptHash = Get-TextSha256 -Text $objective
    $promptUtf8Bytes = [Text.Encoding]::UTF8.GetByteCount($objective)
    $summary.promptSource = $promptSource
    $summary.promptSha256 = $promptHash
    $summary.promptUtf8Bytes = $promptUtf8Bytes

    $maxIterations = [int]$config.maxIterations
    $maxTokens = [int]$config.maxTokens
    $stopWhen = [string]$config.stopWhen
    if ($maxIterations -lt 1 -or $maxIterations -gt 100) {
        throw "maxIterations must be between 1 and 100."
    }
    if ($maxTokens -lt 1 -or $maxTokens -gt 1000000000) {
        throw "maxTokens must be between 1 and 1000000000."
    }
    if ([string]::IsNullOrWhiteSpace($stopWhen)) {
        throw "The nap configuration stopWhen value cannot be blank."
    }
    $summary.maxIterations = $maxIterations
    $summary.maxTokens = $maxTokens
    $summary.stopWhen = $stopWhen
    $summary.pushBranch = [bool]$config.pushBranch

    $statePath = Join-Path $InstallRoot "state.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        if ($PlanOnly) {
            throw "Fleet state is missing: $statePath. PlanOnly will not install software. Run Setup-AgentSwitchboard.cmd first."
        }
        if (-not [bool]$config.bootstrapIfMissing) {
            throw "Fleet state is missing and bootstrapIfMissing=false: $statePath"
        }

        $setupScript = Join-Path (Split-Path -Parent $PSScriptRoot) "gnhf\Setup-AgentSwitchboard.ps1"
        if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
            throw "Fleet state is missing and the source setup script is unavailable: $setupScript"
        }

        $summary.bootstrapAttempted = $true
        $setupArguments = [System.Collections.Generic.List[string]]::new()
        foreach ($item in @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setupScript, "-DefaultRepoPath", $RepoPath, "-InstallRoot", $InstallRoot)) {
            [void]$setupArguments.Add($item)
        }
        if ([bool]$config.installOpenCodeAndCopilotDuringBootstrap) {
            [void]$setupArguments.Add("-InstallOpenCodeAndCopilot")
        }

        Write-Host "`nFleet state is missing. Running bounded AgentSwitchboard setup..." -ForegroundColor Yellow
        & pwsh @setupArguments
        if ($LASTEXITCODE -ne 0) {
            throw "AgentSwitchboard setup failed with exit code $LASTEXITCODE. Review setup logs under '$env:LOCALAPPDATA\AgentSwitchboard\setup-logs'."
        }
    }

    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Fleet state remains unavailable after setup: $statePath"
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

    $candidateAgents = if ($Agent) { @($Agent) } else { @($config.preferredAgents | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
    $candidateAgents = @($candidateAgents | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($candidateAgents.Count -eq 0) {
        throw "No preferredAgents are configured."
    }
    $summary.preferredAgents = @($candidateAgents)

    $selection = Get-AgentSelection -State $state -Candidates $candidateAgents
    $blockedAgents = @($selection.Blocked)
    $summary.blockedAgents = @($blockedAgents)
    if (-not $selection.Agent) {
        $evidenceText = @($blockedAgents | ForEach-Object { "$($_.agent): $($_.evidence)" }) -join [Environment]::NewLine
        throw "No configured agent is ready. Run Setup-AgentSwitchboard.cmd, authenticate a provider, and retry. Readiness evidence:`n$evidenceText"
    }

    $selectedAgent = [string]$selection.Agent
    $selectedAgentEvidence = [string]$selection.Record.evidence
    $summary.selectedAgent = $selectedAgent
    $summary.selectedAgentEvidence = $selectedAgentEvidence

    $launcherPath = Join-Path $InstallRoot "Start-AgentSwitchboard.ps1"
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "Installed AgentSwitchboard launcher is missing: $launcherPath. Rerun Setup-AgentSwitchboard.cmd."
    }

    Write-Host "`n=== NAP SPRINT PREFLIGHT ===" -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Base:       $repoBranch @ $repoHead"
    Write-Host "Agent:      $selectedAgent"
    Write-Host "Evidence:   $selectedAgentEvidence"
    Write-Host "Prompt:     $promptSource ($promptUtf8Bytes UTF-8 bytes, SHA-256 $promptHash)"
    Write-Host "Iterations: $maxIterations"
    Write-Host "Token cap:  $maxTokens"
    Write-Host "Push:       $([bool]$config.pushBranch)"
    Write-Host "Prevent sleep: true"

    if ($PlanOnly) {
        $summary.status = "planned"
        $exitCode = 0
        Write-Host "`nPlanOnly completed. No agent or repository mutation was started." -ForegroundColor Green
    }
    else {
        $beforeLogs = @()
        $innerLogsRoot = Join-Path $InstallRoot "logs"
        if (Test-Path -LiteralPath $innerLogsRoot -PathType Container) {
            $beforeLogs = @(Get-ChildItem -LiteralPath $innerLogsRoot -Directory | ForEach-Object { $_.FullName })
        }

        $launcherArguments = [System.Collections.Generic.List[string]]::new()
        foreach ($item in @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $launcherPath,
            "-RepoPath", $RepoPath,
            "-Agent", $selectedAgent,
            "-Prompt", $objective,
            "-Name", [string]$config.name,
            "-MaxIterations", [string]$maxIterations,
            "-MaxTokens", [string]$maxTokens,
            "-StopWhen", $stopWhen,
            "-InstallRoot", $InstallRoot
        )) {
            [void]$launcherArguments.Add($item)
        }
        if ([bool]$config.pushBranch) {
            [void]$launcherArguments.Add("-PushBranch")
        }

        $summary.status = "running"
        $launched = $true
        $summary.launched = $true
        Write-Host "`nStarting bounded GNHF worktree sprint. Automatic failover is disabled after execution begins." -ForegroundColor Cyan
        & pwsh @launcherArguments
        $exitCode = $LASTEXITCODE

        if (Test-Path -LiteralPath $innerLogsRoot -PathType Container) {
            $afterLogs = @(Get-ChildItem -LiteralPath $innerLogsRoot -Directory | Sort-Object LastWriteTime -Descending)
            $newLog = $afterLogs | Where-Object { $beforeLogs -notcontains $_.FullName } | Select-Object -First 1
            if (-not $newLog) {
                $newLog = $afterLogs | Select-Object -First 1
            }
            if ($newLog) {
                $innerLogPath = $newLog.FullName
                $summary.innerLogPath = $innerLogPath
            }
        }

        if ($exitCode -eq 0) {
            $summary.status = "completed"
            Write-Host "`nNap sprint completed. Review the GNHF branch and evidence before merging." -ForegroundColor Green
        }
        else {
            $summary.status = "failed"
            throw "Nap sprint exited with code $exitCode. No second agent was started automatically."
        }
    }
}
catch {
    $failure = $_.Exception.Message
    if ($summary.status -notin @("failed", "planned", "completed")) {
        $summary.status = "blocked"
    }
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    if ($exitCode -eq 0) {
        $exitCode = 1
    }
}
finally {
    $summary.completedAt = (Get-Date).ToString("o")
    $summary.selectedAgent = $selectedAgent
    $summary.selectedAgentEvidence = $selectedAgentEvidence
    $summary.blockedAgents = @($blockedAgents)
    $summary.promptSource = $promptSource
    $summary.promptSha256 = $promptHash
    $summary.promptUtf8Bytes = $promptUtf8Bytes
    $summary.launched = $launched
    $summary.innerLogPath = $innerLogPath
    $summary.exitCode = $exitCode
    $summary.failure = $failure
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}

Write-Host "`nNap summary: $summaryPath" -ForegroundColor Cyan
Write-Host "Nap transcript: $transcriptPath" -ForegroundColor Cyan
exit $exitCode
