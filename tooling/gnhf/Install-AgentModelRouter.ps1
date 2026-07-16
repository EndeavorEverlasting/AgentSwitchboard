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
$agyBridgeSource = Join-Path $PSScriptRoot "Invoke-AgyPiBridge.ps1"
foreach ($required in @($routerSource, $policySource, $agyBridgeSource)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required router artifact not found: $required"
    }
}

$routerTarget = Join-Path $InstallRoot "Start-AutoRoutedGnhfSprint.ps1"
$policyExampleTarget = Join-Path $InstallRoot "model-route-policy.example.json"
$policyTarget = Join-Path $InstallRoot "model-route-policy.json"
$bridgeRoot = Join-Path $InstallRoot "agy-pi-bridge"
$agyBridgeTarget = Join-Path $bridgeRoot "Invoke-AgyPiBridge.ps1"
$piShimTarget = Join-Path $bridgeRoot "pi.cmd"

New-Item -ItemType Directory -Path $bridgeRoot -Force | Out-Null
Copy-Item -LiteralPath $routerSource -Destination $routerTarget -Force
Copy-Item -LiteralPath $policySource -Destination $policyExampleTarget -Force
Copy-Item -LiteralPath $agyBridgeSource -Destination $agyBridgeTarget -Force

$piShim = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-AgyPiBridge.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
Set-Content -LiteralPath $piShimTarget -Value $piShim -Encoding ascii

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

$policy = Get-Content -LiteralPath $policyTarget -Raw | ConvertFrom-Json
if ($policy.schemaVersion -ne 2) {
    Write-Warning "The preserved local model route policy uses schemaVersion $($policy.schemaVersion). Run with -ResetPolicy after reviewing the backup when you are ready to adopt quota-preserving routing."
}

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
Write-Host "Router:     $routerTarget"
Write-Host "Policy:     $policyTarget"
Write-Host "AGY bridge: $agyBridgeTarget"
Write-Host "Pi shim:    $piShimTarget"
Write-Host "Launcher:   $launcherPath"
Write-Host "`nList routes:"
Write-Host "  & `"$launcherPath`" -ListRoutes" -ForegroundColor Cyan
