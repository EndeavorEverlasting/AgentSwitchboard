[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [string]$OutputPath,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequestPath = [IO.Path]::GetFullPath($RequestPath)
if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
    throw "Child operation request file not found: $RequestPath"
}

$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
if ([string]$request.schema -ne 'agentswitchboard.gnhf.child-operation-request.v1') {
    throw "Unsupported child operation request schema: $($request.schema)"
}

$allowedBoundaries = @('repository-intake', 'static-validation', 'child-validator', 'child-build', 'read-only-runtime', 'none')
$boundary = [string]$request.authorityBoundary
if ($allowedBoundaries -notcontains $boundary) {
    throw "Authority boundary '$boundary' is not recognized. Allowed: $($allowedBoundaries -join ', ')"
}

$requiredConsumerIds = @('agent-switchboard', 'sysadminsuite', 'continuum', 'web-excel-repair-triage')
$consumerId = [string]$request.consumerId
if ($requiredConsumerIds -notcontains $consumerId) {
    throw "Consumer '$consumerId' is not in the allowed AgentSwitchboard consumer list."
}

$operationId = [string]$request.operationId
$targetRepository = [string]$request.targetRepository

$registry = [ordered]@{
    'blacksmith-guild' = @{
        'inspect-harness' = 'scripts/tbg/Test-TbgEndToEndHarness.ps1'
        'run-default-static' = 'scripts/tbg/Invoke-TbgEndToEndValidation.ps1 -Profile default-static'
        'refresh-read-only-runtime' = 'scripts/tbg/Invoke-TbgEndToEndValidation.ps1 -Profile read-only-runtime -AllowLiveRuntime'
        'generate-sprint-capsule' = 'scripts/tbg/New-TbgSprintCapsule.ps1'
        'prepare-runtime-plan' = 'scripts/tbg/Invoke-TbgEndToEndValidation.ps1 -Profile default-static'
    }
}

if (-not $registry.Contains($targetRepository)) {
    throw "Target repository '$targetRepository' is not registered for child operations."
}
$repoOps = $registry[$targetRepository]
if (-not $repoOps.Contains($operationId)) {
    throw "Operation '$operationId' is not registered for repository '$targetRepository'."
}

$entrypoint = $repoOps[$operationId]
$script = $entrypoint -replace '\s+.*$', ''

$result = [ordered]@{
    schema = 'agentswitchboard.gnhf.child-operation-result.v1'
    requestId = [string]$request.requestId
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    targetRepository = $targetRepository
    operationId = $operationId
    status = 'blocked'
    proofLevel = 'contract'
    proofCeiling = "This dispatcher only records the contract surface for '$operationId'. No execution claim is made."
    artifacts = @()
    blockers = @("Child operation execution is not authorized on this host. Entrypoint would be: $script")
    risks = @()
    nextCommand = 'Run the registered entrypoint on the target repository after verifying authority boundary and runtime posture.'
    reinspectState = $true
}

if ($ValidateOnly) {
    $result.status = 'completed'
    $result.proofLevel = 'contract'
    $result.proofCeiling = 'Request validation only: schema, authority boundary, consumer, and operation registry all match.'
    $result.blockers = @()
    $result.artifacts += [ordered]@{ type = 'validated-request'; path = $RequestPath }
}

$resultJson = $result | ConvertTo-Json -Depth 10
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $resultJson
}
else {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $resultJson | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    Write-Host "Wrote child operation result to $OutputPath" -ForegroundColor Green
}
