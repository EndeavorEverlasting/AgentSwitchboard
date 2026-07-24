[CmdletBinding()]
param(
    [string]$RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonModule = Join-Path $scriptDir 'TechnicianLiveCert.Common.psm1'
Import-Module -Name $commonModule -Force

$runsDir = Get-TechnicianLiveCertRunsDir

if (-not $RunId) {
    $latestDir = Get-ChildItem -Path $runsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latestDir) {
        Write-Warning "No live cert runs found in: $runsDir"
        exit 1
    }
    $targetPath = $latestDir.FullName
} else {
    $targetPath = Join-Path $runsDir $RunId
    if (-not (Test-Path -LiteralPath $targetPath)) {
        Write-Warning "Specified run directory does not exist: $targetPath"
        exit 1
    }
}

Write-Host "Opening evidence directory: $targetPath" -ForegroundColor Green
Start-Process "explorer.exe" -ArgumentList "`"$targetPath`""
exit 0
