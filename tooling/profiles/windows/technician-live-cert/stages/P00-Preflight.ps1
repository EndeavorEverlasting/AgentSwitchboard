[CmdletBinding()]
param(
    [string]$StageId = 'P00',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P00-Preflight checks..." -ForegroundColor Yellow

if ($env:OS -ne 'Windows_NT') {
    throw 'P00-Preflight requires Windows_NT.'
}

$pwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwshPath) {
    throw 'pwsh.exe (PowerShell 7) is required on PATH.'
}

$gitPath = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $gitPath) {
    throw 'git.exe is required on PATH.'
}

$curlPath = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curlPath) {
    throw 'curl.exe is required on PATH.'
}

$preflightFile = Join-Path $StageDir 'preflight-summary.json'
$summaryData = [ordered]@{
    os = $env:OS
    psVersion = $PSVersionTable.PSVersion.ToString()
    gitPath = $gitPath.Source
    curlPath = $curlPath.Source
    passed = $true
}

$json = ConvertTo-Json $summaryData -Depth 5
[System.IO.File]::WriteAllText($preflightFile, $json, [System.Text.Encoding]::UTF8)

Write-Host "P00-Preflight passed." -ForegroundColor Green
return 0
