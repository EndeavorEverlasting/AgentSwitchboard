[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepairId,

    [string]$RunId,

    [string]$RepoRoot,

    [string]$OriginSid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonModule = Join-Path $scriptDir 'TechnicianLiveCert.Common.psm1'
Import-Module -Name $commonModule -Force

$RepoRoot = Resolve-TechnicianRepoRoot -RepoRoot $RepoRoot
$currentSid = Get-TechnicianCurrentSid
if (-not [string]::IsNullOrWhiteSpace($OriginSid) -and $OriginSid -ne $currentSid) {
    throw "Same-user elevation failed for repair '$RepairId'. Origin SID '$OriginSid' does not match elevated SID '$currentSid'."
}

$manifest = Get-TechnicianLiveCertManifest -RepoRoot $RepoRoot
$repairDef = @($manifest.repairs | Where-Object repairId -eq $RepairId)[0]
if (-not $repairDef) {
    throw "Repair '$RepairId' is not defined in manifest."
}

if ($repairDef.requiresElevation -and -not (Test-IsElevated)) {
    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-RepairId', $RepairId,
        '-RepoRoot', ('"{0}"' -f $RepoRoot),
        '-OriginSid', $currentSid
    )
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $arguments += @('-RunId', $RunId)
    }

    Write-Host "Repair $RepairId requires administrator rights. Requesting same-user UAC elevation..." -ForegroundColor Yellow
    try {
        $elevated = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    }
    catch {
        throw "Same-user UAC elevation for repair '$RepairId' was cancelled or failed: $($_.Exception.Message)"
    }
    exit $elevated.ExitCode
}

if ($repairDef.requiresElevation -and -not [string]::IsNullOrWhiteSpace($RunId)) {
    $runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
    if ($currentSid -ne [string]$runContext.accountSid) {
        throw "Elevated repair account SID '$currentSid' does not match run owner SID '$($runContext.accountSid)'."
    }
}

$implPath = Join-Path $scriptDir $repairDef.implementation
if (-not (Test-Path -LiteralPath $implPath -PathType Leaf)) {
    throw "Repair implementation script missing: $implPath"
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Executing Repair $RepairId`: $($repairDef.name)" -ForegroundColor Yellow
Write-Host " Implementation: $($repairDef.implementation)" -ForegroundColor Gray
Write-Host " Targets Stages: $($repairDef.targetsStages -join ', ')" -ForegroundColor Gray
Write-Host '============================================================' -ForegroundColor Cyan

$exitCode = 1
try {
    $repairResult = & $implPath -RepairId $RepairId -RunId $RunId -RepoRoot $RepoRoot
    if ($repairResult -is [int]) {
        $exitCode = [int]$repairResult
    } elseif ($null -ne $repairResult -and $repairResult.PSObject.Properties['exitCode']) {
        $exitCode = [int]$repairResult.exitCode
    } else {
        $exitCode = 0
    }
}
catch {
    $exitCode = 1
    Write-Host "Repair $RepairId failed`: $($_.Exception.Message)" -ForegroundColor Red
}

if ($exitCode -eq 0) {
    Write-Host "`nRepair $RepairId completed successfully." -ForegroundColor Green
} elseif ($exitCode -eq 3010) {
    Write-Host "`nRepair $RepairId reached a required Windows reboot boundary." -ForegroundColor Yellow
    Write-Host 'The repair registered a one-time continuation for the same Windows user. Restart Windows; do not rerun the same pre-reboot step manually.' -ForegroundColor Yellow
} else {
    Write-Host "`nRepair $RepairId failed with exit code $exitCode." -ForegroundColor Red
}
exit $exitCode
