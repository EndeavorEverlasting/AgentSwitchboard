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
if (-not $RepoRoot) {
    $RepoRoot = (Get-Item $scriptDir).Parent.Parent.Parent.FullName
}

$commonModule = Join-Path $scriptDir 'TechnicianLiveCert.Common.psm1'
Import-Module -LiteralPath $commonModule -Force

$manifest = Get-TechnicianLiveCertManifest -RepoRoot $RepoRoot

if (-not $RunId -and -not $Resume) {
    $runContext = New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot
    $RunId = $runContext.runId
} else {
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
    $RunId = $runContext.runId
}

$runDir = Get-TechnicianLiveCertRunDir -RunId $RunId

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TECHNICIAN CLICKABLE LIVE-CERT FULL RUN" -ForegroundColor Yellow
Write-Host " Run ID: $RunId" -ForegroundColor White
Write-Host " Evidence Path: $runDir" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

$sequence = @($manifest.coreSequence)
if ($IncludeOptional) {
    $sequence += 'P09'
}

$stageDispatcher = Join-Path $scriptDir 'Invoke-TechnicianLiveCertStage.ps1'

$overallFailed = $false
$failedStageId = $null

foreach ($stageId in $sequence) {
    # If resuming, check if stage already passed
    if ($Resume) {
        $stageState = $null
        if ($runContext.stages.PSObject.Properties[$stageId]) {
            $stageState = $runContext.stages.$stageId
        } elseif ($runContext.optionalStages -and $runContext.optionalStages.PSObject.Properties[$stageId]) {
            $stageState = $runContext.optionalStages.$stageId
        }
        if ($stageState -and $stageState.status -eq 'passed') {
            Write-Host "Stage $stageId already passed. Skipping (Resume mode)." -ForegroundColor Gray
            continue
        }
    }

    Write-Host "`n--- Running Stage $stageId ---" -ForegroundColor Yellow
    
    $proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$stageDispatcher`"", "-StageId", "$stageId", "-RunId", "$RunId", "-RepoRoot", "`"$RepoRoot`"", $(if ($NonInteractive) { "-NonInteractive" }) -Wait -NoNewWindow -PassThru

    $stageExit = $proc.ExitCode

    # Reload run context
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId

    if ($stageExit -ne 0) {
        $overallFailed = $true
        $failedStageId = $stageId
        break
    }
}

if ($overallFailed) {
    Write-Host "`n============================================================" -ForegroundColor Red
    Write-Host " LIVE-CERT RUN FAILED AT STAGE $failedStageId" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red

    # Find matching repairs
    $matchingRepairs = @($manifest.repairs | Where-Object { $_.targetsStages -contains $failedStageId })
    if ($matchingRepairs.Count -gt 0) {
        Write-Host "`nRecommended Repair Command(s):" -ForegroundColor Yellow
        foreach ($r in $matchingRepairs) {
            Write-Host "  - $($r.cmd)  (ID: $($r.repairId), Name: $($r.name))" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`nNo specific repair command mapped for stage $failedStageId." -ForegroundColor Gray
    }

    Write-Host "`nTo resume after repair, run:" -ForegroundColor White
    Write-Host "  Run-Technician-LiveCert.cmd -Resume -RunId $RunId" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Red

    $runContext.status = 'failed'
    $runContext.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    Save-TechnicianLiveCertRunContext -RunContext $runContext
    exit 1
} else {
    $runContext.status = 'completed'
    $runContext.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    Save-TechnicianLiveCertRunContext -RunContext $runContext

    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host " LIVE-CERT RUN COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host " Run ID: $RunId" -ForegroundColor White
    Write-Host " Evidence Folder: $runDir" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
    exit 0
}
