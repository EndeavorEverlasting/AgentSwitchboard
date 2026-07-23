[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^P\d{2}$')]
    [string]$StageId,

    [string]$RunId,

    [string]$RepoRoot,

    [string]$OriginSid,

    [switch]$Force,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonModule = Join-Path $scriptDir 'TechnicianLiveCert.Common.psm1'
Import-Module -Name $commonModule -Force

$RepoRoot = Resolve-TechnicianRepoRoot -RepoRoot $RepoRoot
$manifest = Get-TechnicianLiveCertManifest -RepoRoot $RepoRoot
$stageDef = @($manifest.stages | Where-Object stageId -eq $StageId)[0]
if (-not $stageDef) {
    throw "Stage '$StageId' is not defined in manifest."
}

$currentSid = Get-TechnicianCurrentSid
if (-not [string]::IsNullOrWhiteSpace($OriginSid) -and $OriginSid -ne $currentSid) {
    throw "Same-user elevation failed. Origin SID '$OriginSid' does not match elevated SID '$currentSid'. Sign in with an account that can elevate itself and rerun the stage."
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    if ($StageId -eq 'P00') {
        $runContext = New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot
    } else {
        $activeRunId = Get-TechnicianLiveCertActiveRunId
        if ([string]::IsNullOrWhiteSpace($activeRunId)) {
            throw "No active live-cert run exists for stage '$StageId'. Start with Technician-LiveCert-P00-Preflight.cmd."
        }
        $runContext = Get-TechnicianLiveCertRunContext -RunId $activeRunId
    }
    $RunId = $runContext.runId
} else {
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
}

if ($StageId -ne 'P00') {
    $null = Assert-TechnicianLiveCertRunIdentity -RunContext $runContext -RepoRoot $RepoRoot
}

# Dependency gate occurs before UAC so we do not elevate a stage that cannot run.
if (-not $Force -and $stageDef.dependencies -and $stageDef.dependencies.Count -gt 0) {
    foreach ($depId in $stageDef.dependencies) {
        $depState = $null
        if ($runContext.stages.PSObject.Properties[$depId]) {
            $depState = $runContext.stages.$depId
        }
        if (-not $depState -or $depState.status -ne 'passed') {
            Write-Warning "Dependency stage '$depId' for '$StageId' has not passed. Status: $(if ($depState) { $depState.status } else { 'missing' })."
            exit 2
        }
    }
}

# Mutating administrative stages elevate themselves and prove that UAC kept the
# same Windows identity. Alternate-admin credentials are rejected by OriginSid.
if ($stageDef.requiresElevation -and -not (Test-IsElevated)) {
    $runContext.elevationState = 'requested'
    Save-TechnicianLiveCertRunContext -RunContext $runContext

    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-StageId', $StageId,
        '-RunId', $RunId,
        '-RepoRoot', ('"{0}"' -f $RepoRoot),
        '-OriginSid', $currentSid
    )
    if ($Force) { $arguments += '-Force' }
    if ($NonInteractive) { $arguments += '-NonInteractive' }

    Write-Host "Stage $StageId requires administrator rights. Requesting same-user UAC elevation..." -ForegroundColor Yellow
    try {
        $elevated = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    }
    catch {
        throw "Same-user UAC elevation for stage '$StageId' was cancelled or failed: $($_.Exception.Message)"
    }
    exit $elevated.ExitCode
}

if ($stageDef.requiresElevation) {
    if ($currentSid -ne [string]$runContext.accountSid) {
        throw "Elevated account SID '$currentSid' does not match run owner SID '$($runContext.accountSid)'."
    }
    $runContext.elevationState = 'elevated'
    Save-TechnicianLiveCertRunContext -RunContext $runContext
}

$runDir = Get-TechnicianLiveCertRunDir -RunId $runContext.runId
$stageStartedAt = (Get-Date).ToUniversalTime().ToString('o')
$stageDir = Join-Path $runDir $StageId
if (-not (Test-Path -LiteralPath $stageDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $stageDir -Force
}

$implPath = Join-Path $scriptDir $stageDef.implementation
if (-not (Test-Path -LiteralPath $implPath -PathType Leaf)) {
    throw "Stage implementation script missing: $implPath"
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Executing Stage $StageId`: $($stageDef.name)" -ForegroundColor Green
Write-Host " Implementation: $($stageDef.implementation)" -ForegroundColor Gray
Write-Host " Evidence Folder: $stageDir" -ForegroundColor Gray
Write-Host '============================================================' -ForegroundColor Cyan

$stageStatus = 'running'
$exitCode = 1
$errorMsg = $null
$manualObs = $null

try {
    $stageResult = & $implPath -StageId $StageId -RunId $runContext.runId -RepoRoot $RepoRoot -StageDir $stageDir -NonInteractive:$NonInteractive
    if ($stageResult -is [int]) {
        $exitCode = $stageResult
    } elseif ($null -ne $stageResult -and $stageResult.PSObject.Properties['exitCode']) {
        $exitCode = [int]$stageResult.exitCode
        if ($stageResult.PSObject.Properties['manualObservation'] -and $stageResult.manualObservation) {
            $manualObs = $stageResult.manualObservation
        }
    } else {
        $exitCode = 0
    }

    $stageStatus = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
}
catch {
    $exitCode = 1
    $stageStatus = 'failed'
    $errorMsg = $_.Exception.Message
    Write-Host "Stage $StageId failed with exception`: $errorMsg" -ForegroundColor Red
}

if ($stageDef.manualObservationRequired -and -not $manualObs) {
    $promptText = if ($stageDef.PSObject.Properties['manualObservationPrompt'] -and $stageDef.manualObservationPrompt) {
        [string]$stageDef.manualObservationPrompt
    } else {
        "Stage $StageId ($($stageDef.name)): confirm the expected workstation behavior was visibly observed."
    }
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
$classification = $stageStatus

$stageResultObj = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-stage.v1'
    stageId = $StageId
    name = $stageDef.name
    status = $stageStatus
    startedAt = $stageStartedAt
    completedAt = $stageCompletedAt
    exitCode = $exitCode
    evidencePath = $stageDir
    classification = $classification
    proofLevel = 'technician-stage-validation'
    evidenceArtifacts = @($stageDef.evidenceArtifacts)
    manualObservation = $manualObs
    error = $errorMsg
}

$stageResultFile = Join-Path $runDir "stage-${StageId}.json"
Write-TechnicianLiveCertJson -Object $stageResultObj -Path $stageResultFile

$stageStateObj = [ordered]@{
    stageId = $StageId
    name = $stageDef.name
    status = $stageStatus
    startedAt = $stageStartedAt
    completedAt = $stageCompletedAt
    exitCode = $exitCode
    evidencePath = $stageDir
    classification = $classification
    manualObservation = $manualObs
    error = $errorMsg
}

if ($stageDef.optional) {
    $runContext.optionalStages.$StageId = $stageStateObj
} else {
    $runContext.stages.$StageId = $stageStateObj
}

if ($StageId -eq 'P02' -and $stageStatus -eq 'passed') {
    $postSetupGit = Get-TechnicianRepoGitState -RepoRoot $RepoRoot
    $runContext.repositoryRoot = $postSetupGit.Root
    $runContext.branch = $postSetupGit.Branch
    $runContext.head = $postSetupGit.Head
    Set-TechnicianLiveCertActiveRun -RunContext $runContext
}

if ($StageId -eq 'P08' -and $stageStatus -eq 'passed') {
    $runContext.status = 'completed'
    $runContext.completedAt = $stageCompletedAt
}

Save-TechnicianLiveCertRunContext -RunContext $runContext

if ($StageId -eq 'P08' -and $stageStatus -eq 'passed') {
    # Refresh the final JSON after P08 itself has been recorded as passed.
    Write-TechnicianLiveCertJson -Object $runContext -Path (Join-Path $runDir 'technician-live-cert-summary.json')
    Clear-TechnicianLiveCertActiveRun -RunId $runContext.runId
}

$statusColor = if ($stageStatus -eq 'passed') { 'Green' } else { 'Red' }
Write-Host "Stage $StageId finished with status '$stageStatus' (exit code: $exitCode)." -ForegroundColor $statusColor
exit $exitCode
