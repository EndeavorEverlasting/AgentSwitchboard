#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Installs local git hooks for artifact hygiene.
.DESCRIPTION
    Configures the local repository to use the .githooks directory for git hooks.
    This is a local opt-in installer - it does not affect other clones of the repo.
.EXAMPLE
    pwsh -File scripts/Install-Hooks.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$hooksDir = Join-Path $repoRoot ".githooks"

# Check if hooks directory exists
if (-not (Test-Path $hooksDir)) {
    Write-Error "Hooks directory not found: $hooksDir"
    exit 1
}

# Configure git to use local hooks directory
Write-Host "Configuring git to use local hooks directory..." -ForegroundColor Cyan

& git config core.hooksPath .githooks

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure git hooks path"
    exit 1
}

# Verify configuration
$hooksPath = & git config core.hooksPath
Write-Host "Git hooks path set to: $hooksPath" -ForegroundColor Green

# List installed hooks
$hooks = Get-ChildItem -Path $hooksDir -File | Where-Object { $_.Name -notmatch '\.sample$' -and $_.Name -match '\.ps1$' }
if ($hooks) {
    Write-Host ""
    Write-Host "Installed hooks:" -ForegroundColor Cyan
    foreach ($hook in $hooks) {
        Write-Host "  - $($hook.Name)" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "No hooks found in $hooksDir" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Hook installation complete!" -ForegroundColor Green
Write-Host "Hooks will now run automatically on git commit." -ForegroundColor Gray
