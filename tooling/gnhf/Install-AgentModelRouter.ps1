[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$ResetPolicy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required."
}

$InstallRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

$routerSource = Join-Path $PSScriptRoot "Start-AutoRoutedGnhfSprint.ps1"
$policySource = Join-Path $PSScriptRoot "model-route-policy.example.json"
foreach ($required in @($routerSource, $policySource)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required router artifact not found: $required"
    }
}

$routerTarget = Join-Path $InstallRoot "Start-AutoRoutedGnhfSprint.ps1"
$policyExampleTarget = Join-Path $InstallRoot "model-route-policy.example.json"
$policyTarget = Join-Path $InstallRoot "model-route-policy.json"

Copy-Item -LiteralPath $routerSource -Destination $routerTarget -Force
Copy-Item -LiteralPath $policySource -Destination $policyExampleTarget -Force

if ($ResetPolicy -or -not (Test-Path -LiteralPath $policyTarget -PathType Leaf)) {
    if (Test-Path -LiteralPath $policyTarget -PathType Leaf) {
        $backup = "$policyTarget.$(Get-Date -Format 'yyyyMMdd-HHmmss').backup"
        Copy-Item -LiteralPath $policyTarget -Destination $backup
        Write-Host "Policy backup: $backup" -ForegroundColor Yellow
    }
    Copy-Item -LiteralPath $policySource -Destination $policyTarget -Force
    Write-Host "Installed model route policy: $policyTarget" -ForegroundColor Green
}
else {
    Write-Host "Preserved customized model route policy: $policyTarget" -ForegroundColor Green
}

$null = Get-Content -LiteralPath $policyTarget -Raw | ConvertFrom-Json

$launcherPath = Join-Path $InstallRoot "agent-switchboard-auto.cmd"
$launcher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AutoRoutedGnhfSprint.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ascii

Write-Host "`nAgent/model router installed." -ForegroundColor Green
Write-Host "Router:   $routerTarget"
Write-Host "Policy:   $policyTarget"
Write-Host "Launcher: $launcherPath"
Write-Host "`nList routes:"
Write-Host "  & `"$launcherPath`" -ListRoutes" -ForegroundColor Cyan
