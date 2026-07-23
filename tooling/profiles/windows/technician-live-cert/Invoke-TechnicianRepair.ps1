[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepairId,

    [string]$RunId,

    [string]$RepoRoot
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

$repairDef = @($manifest.repairs | Where-Object repairId -eq $RepairId)[0]
if (-not $repairDef) {
    throw "Repair '$RepairId' is not defined in manifest."
}

if ($repairDef.requiresElevation) {
    Assert-Elevation -ContextName "Repair $RepairId ($($repairDef.name))"
}

$implPath = Join-Path $scriptDir $repairDef.implementation
if (-not (Test-Path -LiteralPath $implPath)) {
    throw "Repair implementation script missing: $implPath"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Executing Repair $RepairId`: $($repairDef.name)" -ForegroundColor Yellow
Write-Host " Implementation: $($repairDef.implementation)" -ForegroundColor Gray
Write-Host " Targets Stages: $($repairDef.targetsStages -join ', ')" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

$exitCode = 1
try {
    & $implPath -RepairId $RepairId -RunId $RunId -RepoRoot $RepoRoot
    $exitCode = 0
}
catch {
    $exitCode = 1
    Write-Host "Repair $RepairId failed`: $($_.Exception.Message)" -ForegroundColor Red
}

if ($exitCode -eq 0) {
    Write-Host "`nRepair $RepairId completed successfully." -ForegroundColor Green
} else {
    Write-Host "`nRepair $RepairId failed with exit code $exitCode." -ForegroundColor Red
}

exit $exitCode
