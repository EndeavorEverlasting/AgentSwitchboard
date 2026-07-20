[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$CompiledPromptPath,
    [Parameter(Mandatory)][string]$TargetRepo,
    [switch]$Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $Run) { throw "The queue fixture runtime requires -Run." }
foreach ($required in @($RequestPath, $CompiledPromptPath, $TargetRepo)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Fixture runtime input missing: $required" }
}
foreach ($requiredEnvironment in @(
    "AGENTSWITCHBOARD_APPLICATION_ID",
    "AGENTSWITCHBOARD_TRIGGER_FLAGS",
    "AGENTSWITCHBOARD_TRIGGER_FLAGS_SHA256",
    "AGENTSWITCHBOARD_AWARENESS_GATE"
)) {
    $value = [Environment]::GetEnvironmentVariable($requiredEnvironment)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Fixture runtime environment is missing $requiredEnvironment." }
}
if ($env:AGENTSWITCHBOARD_AWARENESS_GATE -cne "satisfied") {
    throw "Fixture runtime did not receive a satisfied pre-awareness gate."
}
$triggerPath = [IO.Path]::GetFullPath($env:AGENTSWITCHBOARD_TRIGGER_FLAGS)
if (-not (Test-Path -LiteralPath $triggerPath -PathType Leaf)) {
    throw "Fixture runtime trigger snapshot is missing: $triggerPath"
}
$triggerHash = (Get-FileHash -LiteralPath $triggerPath -Algorithm SHA256).Hash
if ($triggerHash -cne $env:AGENTSWITCHBOARD_TRIGGER_FLAGS_SHA256) {
    throw "Fixture runtime trigger snapshot hash mismatch."
}
$triggerSnapshot = Get-Content -LiteralPath $triggerPath -Raw | ConvertFrom-Json -Depth 40
if ([string]$triggerSnapshot.application.id -cne $env:AGENTSWITCHBOARD_APPLICATION_ID -or
    $triggerSnapshot.awarenessGate.satisfied -ne $true -or
    [string]$triggerSnapshot.flaggingPhase -cne "pre-agent-launch") {
    throw "Fixture runtime trigger snapshot does not satisfy the application awareness contract."
}
$compiled = Get-Content -LiteralPath $CompiledPromptPath -Raw | ConvertFrom-Json -Depth 50
if (-not ([string]$compiled.prompt).Contains($triggerPath) -or
    -not ([string]$compiled.prompt).Contains($triggerHash) -or
    -not ([string]$compiled.prompt).Contains("Before completing repository analysis or producing any awareness assessment") -or
    -not (@($compiled.readFirst) -contains $triggerPath)) {
    throw "Fixture runtime compiled prompt lacks the pre-awareness trigger instruction."
}

$laneRoot = Split-Path -Parent $RequestPath
$laneId = Split-Path -Leaf $laneRoot
$evidenceRoot = Join-Path $laneRoot "fake-runtime-evidence"
if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $evidenceRoot -Force)
}

$failLane = [string]$env:AGENTSWITCHBOARD_QUEUE_FIXTURE_FAIL_LANE
$shouldFail = -not [string]::IsNullOrWhiteSpace($failLane) -and $laneId -ceq $failLane
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json -Depth 30
$artifactPath = [string]($request.expectedArtifacts[0] -replace '^Committed\s+', '' -replace '\s+with validation and HEAD proof$', '')
$success = -not $shouldFail
$result = [pscustomobject][ordered]@{
    kind = "desktop-gnhf-runtime-result"
    schemaVersion = 1
    status = if ($success) { "succeeded" } else { "failed" }
    targetState = [pscustomobject][ordered]@{
        clean = $true
        detached = $false
        branch = "main"
        baseCommit = "1111111111111111111111111111111111111111"
    }
    spawn = [pscustomobject][ordered]@{
        acknowledged = $true
        processId = $PID
    }
    process = [pscustomobject][ordered]@{
        exitCode = if ($success) { 0 } else { 1 }
    }
    commitProof = [pscustomobject][ordered]@{
        required = $true
        observed = $success
        branch = if ($success) { "gnhf/fixture-$laneId" } else { $null }
        headCommit = if ($success) { "2222222222222222222222222222222222222222" } else { $null }
        commitsAhead = if ($success) { 1 } else { 0 }
    }
    artifacts = @(
        [pscustomobject][ordered]@{
            path = $artifactPath
            observed = $success
        }
    )
    validation = @(
        [pscustomobject][ordered]@{
            command = "fixture queue runtime"
            result = if ($success) { "passed" } else { "failed" }
        }
    )
    proofLevel = if ($success) { "committed-repository-work" } else { "process-observed" }
    proofCeiling = "Deterministic queue scheduler fixture only; no hosted provider or repository mutation."
    exactNextCommand = "git status --short"
}
$resultPath = Join-Path $evidenceRoot "launch-result.json"
$result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM
Write-Host "AGENTSWITCHBOARD_QUEUE_FIXTURE_LANE:$laneId"
Write-Host "AGENTSWITCHBOARD_QUEUE_FIXTURE_APPLICATION:$($env:AGENTSWITCHBOARD_APPLICATION_ID)"
Write-Host "AGENTSWITCHBOARD_QUEUE_FIXTURE_ACTIVE_TRIGGERS:$($triggerSnapshot.activeTriggerCount)"
Write-Host "Local evidence: $evidenceRoot"
if ($success) { exit 0 }
exit 1
