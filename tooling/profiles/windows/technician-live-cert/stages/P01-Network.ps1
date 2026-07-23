[CmdletBinding()]
param(
    [string]$StageId = 'P01',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P01-Network reachability checks..." -ForegroundColor Yellow

$endpoints = @(
    'https://github.com',
    'https://raw.githubusercontent.com'
)

$results = [System.Collections.Generic.List[object]]::new()
$allPassed = $true

foreach ($url in $endpoints) {
    try {
        $res = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 10 -ErrorAction Stop
        [void]$results.Add([pscustomobject]@{
            url = $url
            status = $res.StatusCode
            reachable = $true
        })
        Write-Host "Reachable: $url ($($res.StatusCode))" -ForegroundColor Gray
    }
    catch {
        $allPassed = $false
        [void]$results.Add([pscustomobject]@{
            url = $url
            status = 0
            error = $_.Exception.Message
            reachable = $false
        })
        Write-Host "Unreachable: $url ($($_.Exception.Message))" -ForegroundColor Red
    }
}

$networkFile = Join-Path $StageDir 'network-summary.json'
$json = ConvertTo-Json $results -Depth 5
[System.IO.File]::WriteAllText($networkFile, $json, [System.Text.Encoding]::UTF8)

if (-not $allPassed) {
    throw "One or more network endpoints were unreachable."
}

Write-Host "P01-Network reachability passed." -ForegroundColor Green
return 0
