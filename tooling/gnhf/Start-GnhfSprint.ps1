[CmdletBinding(DefaultParameterSetName = "PromptFile")]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$Agent,
    [string]$AgentSpecOverride,
    [Parameter(Mandatory, ParameterSetName = "PromptFile")][string]$PromptPath,
    [Parameter(Mandatory, ParameterSetName = "PromptText")][string]$Prompt,
    [string]$Name = "gnhf-sprint",
    [ValidateRange(1, 100)][int]$MaxIterations = 6,
    [ValidateRange(0, 1000000000)][int]$MaxTokens = 500000,
    [Parameter(Mandatory)][string]$StopWhen,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranch,
    [switch]$CurrentBranch,
    [string]$ModelProfileId,
    [string]$ModelId,
    [string]$RoutingDecisionPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

$modelActivationPath = Join-Path $PSScriptRoot "GnhfModelActivation.ps1"
if (Test-Path -LiteralPath $modelActivationPath -PathType Leaf) {
    . $modelActivationPath
}
else {
    function Get-GnhfModelActivationResult {
        param(
            [string]$AcknowledgementPath,
            [string]$ExpectedProfileId,
            [string]$ExpectedAgent,
            [string]$ExpectedModel,
            [string]$ExpectedRoutingDecisionHash
        )
        [pscustomobject][ordered]@{
            state = if ([string]::IsNullOrWhiteSpace($ExpectedModel)) { "not-requested" } else { "requested-only" }
            requestedModel = if ([string]::IsNullOrWhiteSpace($ExpectedModel)) { $null } else { $ExpectedModel }
            acknowledgedModel = $null
            acknowledgementPath = if ([string]::IsNullOrWhiteSpace($AcknowledgementPath)) { $null } else { $AcknowledgementPath }
            evidenceKind = $null
            evidence = $null
            recordedAt = $null
            validationError = "model activation helper unavailable"
        }
    }
}

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

function Get-SafeAgentSpecLabel {
    param([Parameter(Mandatory)][string]$AgentSpec)

    if ($AgentSpec.StartsWith("acp:") -and $AgentSpec.Substring(4).Contains(" ")) {
        return "acp:custom"
    }
    return $AgentSpec
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$resolvedStateAgentSpec = Resolve-AgentSpec -RequestedAgent $Agent -State $state
$agentSpec = if ([string]::IsNullOrWhiteSpace($AgentSpecOverride)) { $resolvedStateAgentSpec } else { $AgentSpecOverride.Trim() }
if ([string]::IsNullOrWhiteSpace($agentSpec)) { throw "Resolved GNHF agent specification is empty." }
$safeAgentSpec = Get-SafeAgentSpecLabel -AgentSpec $agentSpec

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

$routingDecisionHash = $null
if ($RoutingDecisionPath) {
    $RoutingDecisionPath = Resolve-GnhfFleetFile -Path $RoutingDecisionPath -Description "routing decision"
    $routingDecisionHash = (Get-FileHash -LiteralPath $RoutingDecisionPath -Algorithm SHA256).Hash
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
if ($CurrentBranch) {
    if ($branch -in @("main", "master", "trunk")) {
        throw "Scheduler current-branch mode refuses a protected default branch: $branch"
    }
    if (-not $branch.StartsWith("switchboard/gnhf-")) {
        throw "Scheduler current-branch mode requires a scheduler-owned 'switchboard/gnhf-*' branch. Current branch: $branch"
    }
}
elseif ($branch.StartsWith("gnhf/")) {
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

$logsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$safeName = ($Name -replace "[^A-Za-z0-9._-]", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($safeName)) {
    $safeName = "gnhf-sprint"
}
$runLogDir = Ensure-GnhfFleetDirectory -Path (Join-Path $logsRoot "$timestamp-$safeName")
$transcriptPath = Join-Path $runLogDir "launcher-transcript.txt"
$summaryPath = Join-Path $runLogDir "launcher-summary.json"
$modelAcknowledgementPath = Join-Path $runLogDir "model-activation.json"

$summary = [ordered]@{
    schemaVersion = 2
    name = $Name
    startedAt = (Get-Date).ToString("o")
    repoPath = $RepoPath
    baseBranch = $branch
    executionMode = if ($CurrentBranch) { "scheduler-current-branch" } else { "gnhf-worktree" }
    agentRequested = $Agent
    agentSpec = $safeAgentSpec
    modelProfileId = if ($ModelProfileId) { $ModelProfileId } else { $null }
    modelId = if ($ModelId) { $ModelId } else { $null }
    modelActivation = Get-GnhfModelActivationResult `
        -AcknowledgementPath $modelAcknowledgementPath `
        -ExpectedProfileId $ModelProfileId `
        -ExpectedAgent $Agent `
        -ExpectedModel $ModelId `
        -ExpectedRoutingDecisionHash $routingDecisionHash
    routingDecisionPath = if ($RoutingDecisionPath) { $RoutingDecisionPath } else { $null }
    routingDecisionHash = $routingDecisionHash
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
if ($CurrentBranch) {
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

$oldEnvironment = @{
    GNHF_TELEMETRY = $env:GNHF_TELEMETRY
    AGENTSWITCHBOARD_MODEL_PROFILE = $env:AGENTSWITCHBOARD_MODEL_PROFILE
    AGENTSWITCHBOARD_MODEL = $env:AGENTSWITCHBOARD_MODEL
    AGENTSWITCHBOARD_ROUTING_DECISION = $env:AGENTSWITCHBOARD_ROUTING_DECISION
    AGENTSWITCHBOARD_ROUTING_DECISION_HASH = $env:AGENTSWITCHBOARD_ROUTING_DECISION_HASH
    AGENTSWITCHBOARD_MODEL_ACK_PATH = $env:AGENTSWITCHBOARD_MODEL_ACK_PATH
}
$env:GNHF_TELEMETRY = "0"
if ($ModelProfileId) { $env:AGENTSWITCHBOARD_MODEL_PROFILE = $ModelProfileId }
if ($ModelId) { $env:AGENTSWITCHBOARD_MODEL = $ModelId }
if ($RoutingDecisionPath) { $env:AGENTSWITCHBOARD_ROUTING_DECISION = $RoutingDecisionPath }
if ($routingDecisionHash) { $env:AGENTSWITCHBOARD_ROUTING_DECISION_HASH = $routingDecisionHash }
if ($ModelId) { $env:AGENTSWITCHBOARD_MODEL_ACK_PATH = $modelAcknowledgementPath }

$exitCode = 1
$transcriptStarted = $false
$oldLocation = Get-Location

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host "`n=== GNHF SPRINT ===" -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Base:       $branch"
    Write-Host "Mode:       $($summary.executionMode)"
    Write-Host "Agent:      $safeAgentSpec"
    if ($ModelProfileId) { Write-Host "Profile:    $ModelProfileId" }
    if ($ModelId) {
        Write-Host "Model:      $ModelId"
        Write-Host "Model ACK:  $modelAcknowledgementPath"
    }
    Write-Host "Iterations: $MaxIterations"
    Write-Host "Budget:     $MaxTokens"
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
    $summary.modelActivation = Get-GnhfModelActivationResult `
        -AcknowledgementPath $modelAcknowledgementPath `
        -ExpectedProfileId $ModelProfileId `
        -ExpectedAgent $Agent `
        -ExpectedModel $ModelId `
        -ExpectedRoutingDecisionHash $routingDecisionHash
    [void](Ensure-GnhfFleetParentDirectory -Path $summaryPath)
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
    $env:GNHF_TELEMETRY = $oldEnvironment.GNHF_TELEMETRY
    $env:AGENTSWITCHBOARD_MODEL_PROFILE = $oldEnvironment.AGENTSWITCHBOARD_MODEL_PROFILE
    $env:AGENTSWITCHBOARD_MODEL = $oldEnvironment.AGENTSWITCHBOARD_MODEL
    $env:AGENTSWITCHBOARD_ROUTING_DECISION = $oldEnvironment.AGENTSWITCHBOARD_ROUTING_DECISION
    $env:AGENTSWITCHBOARD_ROUTING_DECISION_HASH = $oldEnvironment.AGENTSWITCHBOARD_ROUTING_DECISION_HASH
    $env:AGENTSWITCHBOARD_MODEL_ACK_PATH = $oldEnvironment.AGENTSWITCHBOARD_MODEL_ACK_PATH
}

Write-Host "`nLauncher summary: $summaryPath" -ForegroundColor Cyan
exit $exitCode
