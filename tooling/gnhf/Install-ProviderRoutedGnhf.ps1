[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$RequiredGnhfVersion = "0.1.42"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required."
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
    throw "AgentSwitchboard repository not found from installer: $RepoRoot"
}

# Directory first: installation and validation begin only after entering AgentSwitchboard.
Set-Location -LiteralPath $RepoRoot

$required = [version]$RequiredGnhfVersion
$gnhfCommand = Get-Command gnhf -ErrorAction SilentlyContinue
$detectedVersion = $null
$hasModelFlag = $false
if ($gnhfCommand) {
    $versionText = (& $gnhfCommand.Source --version 2>&1 | Out-String).Trim()
    $match = [regex]::Match($versionText, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if ($match.Success) {
        $detectedVersion = [version]$match.Groups[1].Value
    }
    $helpText = (& $gnhfCommand.Source --help 2>&1 | Out-String)
    $hasModelFlag = $helpText -match '(?m)^\s*(-m,\s*)?--model\b'
}

$needsRepair = ($null -eq $detectedVersion -or $detectedVersion -lt $required -or -not $hasModelFlag)

Write-Host "`n=== Provider-routed GNHF installation plan ===" -ForegroundColor Cyan
Write-Host "Repository:       $RepoRoot"
Write-Host "Install root:     $InstallRoot"
Write-Host "Required GNHF:    $required"
Write-Host "Detected GNHF:    $(if ($detectedVersion) { $detectedVersion } else { '<unavailable>' })"
Write-Host "--model support:  $hasModelFlag"
Write-Host "GNHF repair:      $needsRepair"
Write-Host "Apply:            $([bool]$Apply)"

if (-not $Apply) {
    Write-Host "`nPlan only. Rerun with -Apply to install the pinned runtime and launchers." -ForegroundColor Yellow
    return
}

if ($needsRepair) {
    $npm = Get-Command npm -ErrorAction Stop
    Write-Host "Installing gnhf@$required..." -ForegroundColor Yellow
    & $npm.Source install --global "gnhf@$required"
    if ($LASTEXITCODE -ne 0) {
        throw "npm failed to install gnhf@$required."
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath;$(Join-Path $env:APPDATA 'npm');$(Join-Path $HOME '.local\bin')"
    $gnhfCommand = Get-Command gnhf -ErrorAction Stop

    $versionText = (& $gnhfCommand.Source --version 2>&1 | Out-String).Trim()
    $match = [regex]::Match($versionText, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success -or [version]$match.Groups[1].Value -lt $required) {
        throw "GNHF repair completed but the required version was not observed. Output: $versionText"
    }
    $helpText = (& $gnhfCommand.Source --help 2>&1 | Out-String)
    if ($helpText -notmatch '(?m)^\s*(-m,\s*)?--model\b') {
        throw "GNHF repair completed but --model is still unavailable."
    }
    $detectedVersion = [version]$match.Groups[1].Value
}

[void](New-Item -ItemType Directory -Path $InstallRoot -Force)
foreach ($file in @("Gnhf.Process.ps1", "Start-ProviderRoutedGnhfSprint.ps1")) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required provider-route file is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $InstallRoot $file) -Force
}

$launcher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ProviderRoutedGnhfSprint.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
Set-Content -LiteralPath (Join-Path $InstallRoot "agent-switchboard-provider.cmd") -Value $launcher -Encoding ascii

$statePath = Join-Path $InstallRoot "state.json"
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state.gnhf.commandPath = $gnhfCommand.Source
    $state.gnhf.versionOutput = $detectedVersion.ToString()
    if (-not $state.gnhf.PSObject.Properties["requiredProviderRouteVersion"]) {
        $state.gnhf | Add-Member -NotePropertyName requiredProviderRouteVersion -NotePropertyValue $required.ToString()
    }
    else {
        $state.gnhf.requiredProviderRouteVersion = $required.ToString()
    }
    if (-not $state.gnhf.PSObject.Properties["modelFlagVerified"]) {
        $state.gnhf | Add-Member -NotePropertyName modelFlagVerified -NotePropertyValue $true
    }
    else {
        $state.gnhf.modelFlagVerified = $true
    }
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
}

Write-Host "`nProvider-routed GNHF installed." -ForegroundColor Green
Write-Host "GNHF:     $detectedVersion"
Write-Host "Launcher: $(Join-Path $InstallRoot 'agent-switchboard-provider.cmd')"
Write-Host "Script:   $(Join-Path $InstallRoot 'Start-ProviderRoutedGnhfSprint.ps1')"
