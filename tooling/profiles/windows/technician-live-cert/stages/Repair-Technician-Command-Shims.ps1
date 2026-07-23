[CmdletBinding()]
param(
    [string]$RepairId = 'Command-Shims',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Repairing command shims in %LOCALAPPDATA%\AgentSwitchboard\bin..." -ForegroundColor Yellow
$shimDir = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
if (-not (Test-Path -LiteralPath $shimDir)) {
    $null = New-Item -ItemType Directory -Path $shimDir -Force
}

$commands = @('agy', 'opencode', 'hermes')
foreach ($cmdName in $commands) {
    $cmdPath = Join-Path $shimDir "$cmdName.cmd"
    $cmdContent = @"
@echo off
wsl.exe -d Ubuntu -- bash -lc "$cmdName %*"
"@
    [System.IO.File]::WriteAllText($cmdPath, $cmdContent, [System.Text.Encoding]::ASCII)
    Write-Host "Recreated shim: $cmdPath" -ForegroundColor Gray
}

Write-Host "Command shims repair complete." -ForegroundColor Green
exit 0
