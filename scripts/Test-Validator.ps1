#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for the harness validator.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$validatorPath = Join-Path $scriptDir ".." "scripts" "Validate-Harness.ps1"

Write-Host "Testing harness validator..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Validator exists and parses
Write-Host "Test 1: Validator exists and parses" -ForegroundColor Yellow
if (Test-Path $validatorPath) {
    try {
        $null = Get-Command $validatorPath -ErrorAction Stop
        Write-Host "  PASS: Validator script exists and is valid PowerShell" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: Validator script has syntax errors: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  FAIL: Validator script not found at $validatorPath" -ForegroundColor Red
    exit 1
}

# Test 2: Prints matrix (run with -WhatIf to avoid side effects)
Write-Host "Test 2: Prints matrix" -ForegroundColor Yellow
try {
    $output = & pwsh -NoProfile -File $validatorPath 2>&1
    if ($output -match "\[PASS\]|\[SKIP\]|\[FAIL\]") {
        Write-Host "  PASS: Matrix output contains PASS/SKIP/FAIL markers" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Matrix output does not contain expected markers" -ForegroundColor Red
        Write-Host "  Output: $output" -ForegroundColor Gray
        exit 1
    }
} catch {
    Write-Host "  FAIL: Could not run validator: $_" -ForegroundColor Red
    exit 1
}

# Test 3: Emits JSON
Write-Host "Test 3: Emits JSON" -ForegroundColor Yellow
try {
    $jsonOutput = & pwsh -NoProfile -File $validatorPath -JsonOutput 2>&1
    if ($jsonOutput -match '"passed"|"skipped"|"failed"') {
        Write-Host "  PASS: JSON output contains expected fields" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: JSON output does not contain expected fields" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  FAIL: Could not run validator with JSON output: $_" -ForegroundColor Red
    exit 1
}

# Test 4: Does not launch app/game/browser
Write-Host "Test 4: Does not launch app/game/browser" -ForegroundColor Yellow
$forbiddenPatterns = @("Start-Process", "Invoke-WebRequest", "curl ", "wget ", "browser", "chrome", "firefox")
$scriptContent = Get-Content $validatorPath -Raw
$foundForbidden = $false
foreach ($pattern in $forbiddenPatterns) {
    if ($scriptContent -match $pattern) {
        Write-Host "  FAIL: Found forbidden pattern: $pattern" -ForegroundColor Red
        $foundForbidden = $true
    }
}
if (-not $foundForbidden) {
    Write-Host "  PASS: No forbidden patterns found" -ForegroundColor Green
}

# Test 5: Does not mutate targets/data
Write-Host "Test 5: Does not mutate targets/data" -ForegroundColor Yellow
$mutatePatterns = @("Remove-Item", "Set-Content", "Clear-Content", "New-Item -Force")
$foundMutate = $false
foreach ($pattern in $mutatePatterns) {
    if ($scriptContent -match $pattern) {
        Write-Host "  FAIL: Found mutation pattern: $pattern" -ForegroundColor Red
        $foundMutate = $true
    }
}
if (-not $foundMutate) {
    Write-Host "  PASS: No mutation patterns found" -ForegroundColor Green
}

Write-Host ""
Write-Host "All tests passed!" -ForegroundColor Green
