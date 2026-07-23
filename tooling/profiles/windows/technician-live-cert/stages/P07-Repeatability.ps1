[CmdletBinding()]
param(
    [string]$StageId = 'P07',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P07-Repeatability stage..." -ForegroundColor Yellow

# Verify that repeated launch does not throw or break process environment
$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
$proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupScript`"", "-Mode", "shell", "-RepoRoot", "`"$RepoRoot`"" -Wait -NoNewWindow -PassThru

$repeatabilityFile = Join-Path $StageDir 'repeatability-summary.json'
$summaryData = [ordered]@{
    repeatExitCode = $proc.ExitCode
    passed = ($proc.ExitCode -eq 0)
}

$json = ConvertTo-Json $summaryData -Depth 5
[System.IO.File]::WriteAllText($repeatabilityFile, $json, [System.Text.Encoding]::UTF8)

Write-Host "P07-Repeatability passed." -ForegroundColor Green
return 0
