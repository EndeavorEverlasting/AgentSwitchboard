[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^P\d{2}$')]
    [string]$StageId,

    [string]$RunId,

    [string]$RepoRoot,

    [switch]$Force,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) {
    $RepoRoot = (Get-Item $scriptDir).Parent.Parent.Parent.FullName
}

$commonModule = Join-Path $scriptDir 'TechnicianLiveCert.Common.psm1'
Import-Module -Name $commonModule -Force

$manifest = Get-TechnicianLiveCertManifest -RepoRoot $RepoRoot

$stageDef = @($manifest.stages | Where-Object stageId -eq $StageId)[0]
if (-not $stageDef) {
    throw "Stage '$StageId' is not defined in manifest."
}

# A directly clicked stage must be able to start its own run when no run ID
# exists yet. Full-run and resume callers continue to pass an explicit RunId.
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $runContext = New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot
    $RunId = $runContext.runId
} else {
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
}
$runDir = Get-TechnicianLiveCertRunDir -RunId $runContext.runId

# Check dependencies
if (-not $Force -and $stageDef.dependencies -and $stageDef.dependencies.Count -gt 0) {
    foreach ($depId in $stageDef.dependencies) {
        $depState = $null
        if ($runContext.stages.PSObject.Properties[$depId]) {
            $depState = $runContext.stages.$depId
        }
        if (-not $depState -or $depState.status -ne 'passed') {
            Write-Warning "Dependency stage '$depId' for '$StageId' has not passed. Status: $(if ($depState) { $depState.status } else { 'missing' }). Use -Force to override."
            exit 2
        }
    }
}

# Elevation check
if ($stageDef.requiresElevation) {
    Assert-Elevation -ContextName "Stage $StageId ($($stageDef.name))"
}

$stageStartedAt = (Get-Date).ToUniversalTime().ToString('o')
$stageDir = Join-Path $runDir $StageId
if (-not (Test-Path -LiteralPath $stageDir)) {
    $null = New-Item -ItemType Directory -Path $stageDir -Force
}

$implPath = Join-Path $scriptDir $stageDef.implementation
if (-not (Test-Path -LiteralPath $implPath)) {
    throw "Stage implementation script missing: $implPath"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Executing Stage $StageId`: $($stageDef.name)" -ForegroundColor Green
Write-Host " Implementation: $($stageDef.implementation)" -ForegroundColor Gray
Write-Host " Evidence Folder: $stageDir" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

$stageStatus = 'running'
$exitCode = 1
$errorMsg = $null
$manualObs = $null

try {
    # Run the stage script
    $stageResult = & $implPath -StageId $StageId -RunId $runContext.runId -RepoRoot $RepoRoot -StageDir $stageDir -NonInteractive:$NonInteractive
    if ($stageResult -is [int]) {
        $exitCode = $stageResult
    } elseif ($stageResult.exitCode -ne $null) {
        $exitCode = [int]$stageResult.exitCode
        if ($stageResult.manualObservation) {
            $manualObs = $stageResult.manualObservation
        }
    } else {
        $exitCode = 0
    }

    if ($exitCode -eq 0) {
        $stageStatus = 'passed'
    } else {
        $stageStatus = 'failed'
    }
}
catch {
    $exitCode = 1
    $stageStatus = 'failed'
    $errorMsg = $_.Exception.Message
    Write-Host "Stage $StageId failed with exception`: $errorMsg" -ForegroundColor Red
}

# Check manual observation if required and not already prompted by stage implementation
if ($stageDef.manualObservationRequired -and -not $manualObs) {
    $promptText = "Stage $StageId ($($stageDef.name)): Please confirm visual observation of expected workstation behavior."
    $manualObs = Invoke-ManualObservationPrompt -StageId $StageId -PromptText $promptText -NonInteractive:$NonInteractive
    if ($manualObs.response -eq '2') {
        $stageStatus = 'failed'
        if ($exitCode -eq 0) { $exitCode = 3 }
    } elseif ($manualObs.response -eq '3') {
        $stageStatus = 'blocked'
        if ($exitCode -eq 0) { $exitCode = 4 }
    }
}

$stageCompletedAt = (Get-Date).ToUniversalTime().ToString('o')

$stageResultObj = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-stage.v1'
    stageId = $StageId
    name = $stageDef.name
    status = $stageStatus
    startedAt = $stageStartedAt
    completedAt = $stageCompletedAt
    exitCode = $exitCode
    evidencePath = $stageDir
    classification = if ($stageStatus -eq 'passed') { 'passed' } else { 'failed' }
    proofLevel = 'technician-stage-validation'
    evidenceArtifacts = @($stageDef.evidenceArtifacts)
    manualObservation = $manualObs
    error = $errorMsg
}

$stageResultFile = Join-Path $runDir "stage-${StageId}.json"
Write-TechnicianLiveCertJson -Object $stageResultObj -Path $stageResultFile

# Update run context
$stageStateObj = [ordered]@{
    stageId = $StageId
    name = $stageDef.name
    status = $stageStatus
    startedAt = $stageStartedAt
    completedAt = $stageCompletedAt
    exitCode = $exitCode
    evidencePath = $stageDir
    classification = if ($stageStatus -eq 'passed') { 'passed' } else { 'failed' }
    manualObservation = $manualObs
    error = $errorMsg
}

if ($stageDef.optional) {
    $runContext.optionalStages.$StageId = $stageStateObj
} else {
    $runContext.stages.$StageId = $stageStateObj
}

Save-TechnicianLiveCertRunContext -RunContext $runContext

$statusColor = if ($stageStatus -eq 'passed') { 'Green' } else { 'Red' }
Write-Host "Stage $StageId finished with status '$stageStatus' (exit code: $exitCode)." -ForegroundColor $statusColor

exit $exitCode
