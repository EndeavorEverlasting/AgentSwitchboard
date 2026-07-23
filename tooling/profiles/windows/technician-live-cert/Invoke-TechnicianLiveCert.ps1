[CmdletBinding()]
param(
    [string]$RunId,

    [string]$RepoRoot,

    [switch]$IncludeOptional,

    [switch]$NonInteractive,

    [switch]$Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonModule = Join-Path $scriptDir 'TechnicianLiveCert.Common.psm1'
Import-Module -Name $commonModule -Force
$RepoRoot = Resolve-TechnicianRepoRoot -RepoRoot $RepoRoot

$manifest = Get-TechnicianLiveCertManifest -RepoRoot $RepoRoot

if (-not $RunId -and -not $Resume) {
    $runContext = New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot
    $RunId = $runContext.runId
} else {
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
    $RunId = $runContext.runId
    $null = Assert-TechnicianLiveCertRunIdentity -RunContext $runContext -RepoRoot $RepoRoot
}

$runDir = Get-TechnicianLiveCertRunDir -RunId $RunId

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' TECHNICIAN CLICKABLE LIVE-CERT FULL RUN' -ForegroundColor Yellow
Write-Host " Run ID: $RunId" -ForegroundColor White
Write-Host " Evidence Path: $runDir" -ForegroundColor White
Write-Host '============================================================' -ForegroundColor Cyan

$sequence = @($manifest.coreSequence)
if ($IncludeOptional) {
    $sequence += 'P09'
}

$stageDispatcher = Join-Path $scriptDir 'Invoke-TechnicianLiveCertStage.ps1'
$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
$overallFailed = $false
$failedStageId = $null

foreach ($stageId in $sequence) {
    if ($Resume) {
        $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
        $stageState = $null
        if ($runContext.stages.PSObject.Properties[$stageId]) {
            $stageState = $runContext.stages.$stageId
        } elseif ($runContext.optionalStages -and $runContext.optionalStages.PSObject.Properties[$stageId]) {
            $stageState = $runContext.optionalStages.$stageId
        }
        if ($stageState -and $stageState.status -eq 'passed') {
            Write-Host "Stage $stageId already passed. Skipping in Resume mode." -ForegroundColor Gray
            continue
        }
    }

    Write-Host "`n--- Running Stage $stageId ---" -ForegroundColor Yellow
    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $stageDispatcher),
        '-StageId', $stageId,
        '-RunId', $RunId,
        '-RepoRoot', ('"{0}"' -f $RepoRoot)
    )
    if ($NonInteractive) { $arguments += '-NonInteractive' }

    $proc = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru
    $stageExit = $proc.ExitCode
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId

    if ($stageExit -ne 0) {
        $overallFailed = $true
        $failedStageId = $stageId
        break
    }
}

if ($overallFailed) {
    Write-Host "`n============================================================" -ForegroundColor Red
    Write-Host " LIVE-CERT RUN STOPPED AT STAGE $failedStageId" -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Red

    $matchingRepairs = @($manifest.repairs | Where-Object { $_.targetsStages -contains $failedStageId })
    if ($matchingRepairs.Count -gt 0) {
        Write-Host "`nTracked repair CMD(s):" -ForegroundColor Yellow
        foreach ($repair in $matchingRepairs) {
            Write-Host "  - $($repair.cmd)  [$($repair.name)]" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`nNo stage-specific repair CMD is mapped. Review the stage evidence before changing anything." -ForegroundColor Gray
    }

    Write-Host "`nEvidence:" -ForegroundColor White
    Write-Host "  $runDir" -ForegroundColor Cyan
    Write-Host "`nResume after repair:" -ForegroundColor White
    Write-Host "  Run-Technician-LiveCert.cmd -Resume -RunId $RunId" -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Red

    $runContext.status = 'failed'
    $runContext.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    Save-TechnicianLiveCertRunContext -RunContext $runContext
    exit 1
}

$runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
$runContext.status = 'completed'
if (-not $runContext.completedAt) {
    $runContext.completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
Save-TechnicianLiveCertRunContext -RunContext $runContext

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host ' LIVE-CERT CORE RUN COMPLETED SUCCESSFULLY' -ForegroundColor Green
Write-Host " Run ID: $RunId" -ForegroundColor White
Write-Host " Evidence Folder: $runDir" -ForegroundColor White
Write-Host ' Provider authentication/response remains separate unless explicitly observed.' -ForegroundColor Gray
Write-Host '============================================================' -ForegroundColor Green
exit 0
