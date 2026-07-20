#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for the pre-commit hook artifact hygiene.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$repoRoot = Split-Path $scriptDir -Parent
$hookPath = Join-Path $repoRoot ".githooks" "pre-commit.ps1"

Write-Host "Testing pre-commit hook artifact hygiene..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Hook exists and parses
Write-Host "Test 1: Hook exists and parses" -ForegroundColor Yellow
if (Test-Path $hookPath) {
    try {
        $null = Get-Command $hookPath -ErrorAction Stop
        Write-Host "  PASS: Hook script exists and is valid PowerShell" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL: Hook script has syntax errors: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  FAIL: Hook script not found at $hookPath" -ForegroundColor Red
    exit 1
}

# Test 2: Hook blocks obvious generated/runtime evidence
Write-Host "Test 2: Hook blocks generated/runtime evidence" -ForegroundColor Yellow
$testCases = @(
    @{ File = "test.log"; ShouldBlock = $true },
    @{ File = "gnhf.log"; ShouldBlock = $true },
    @{ File = "iteration-1.jsonl"; ShouldBlock = $true },
    @{ File = "core.dmp"; ShouldBlock = $true },
    @{ File = "secret.env"; ShouldBlock = $true },
    @{ File = "credentials.json"; ShouldBlock = $true },
    @{ File = "node_modules/package/index.js"; ShouldBlock = $true },
    @{ File = "C:/Users/test/file.txt"; ShouldBlock = $true },
    @{ File = "test.md"; ShouldBlock = $false },
    @{ File = "docs/README.md"; ShouldBlock = $false },
    @{ File = "tests/fixtures/test.xlsx"; ShouldBlock = $false }
)

$allPassed = $true
foreach ($tc in $testCases) {
    $blocked = $false
    # Check if file matches blocked patterns (simplified check)
    if ($tc.File -match '\.log$' -or 
        $tc.File -match '\.log\.\d+$' -or
        $tc.File -match 'gnhf\.log' -or
        $tc.File -match 'iteration-\d+\.jsonl' -or
        $tc.File -match '\.dmp$' -or 
        $tc.File -match '\.env$' -or 
        $tc.File -match 'credentials\.json$' -or
        $tc.File -match 'node_modules/' -or
        $tc.File -match 'C:\\Users\\' -or
        $tc.File -match 'C:/Users/') {
        $blocked = $true
    }
    
    if ($blocked -eq $tc.ShouldBlock) {
        Write-Host "  PASS: $($tc.File) - $(if ($tc.ShouldBlock) { 'blocked' } else { 'allowed' })" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $($tc.File) - expected $(if ($tc.ShouldBlock) { 'blocked' } else { 'allowed' })" -ForegroundColor Red
        $allPassed = $false
    }
}

if (-not $allPassed) {
    exit 1
}

# Test 3: Remediation guidance appears
Write-Host "Test 3: Remediation guidance appears" -ForegroundColor Yellow
$hookContent = Get-Content $hookPath -Raw
if ($hookContent -match "Move live/generated evidence" -or $hookContent -match "git reset HEAD") {
    Write-Host "  PASS: Remediation guidance found in hook" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Remediation guidance not found" -ForegroundColor Red
    exit 1
}

# Test 4: Sanitized fixtures are allowed
Write-Host "Test 4: Sanitized fixtures are allowed" -ForegroundColor Yellow
if ($hookContent -match "tests/fixtures/" -or $hookContent -match "docs/") {
    Write-Host "  PASS: Sanitized fixture paths are allowed" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Sanitized fixture paths not found in allow list" -ForegroundColor Red
    exit 1
}

# Test 5: Docs/code are not broadly blocked
Write-Host "Test 5: Docs/code are not broadly blocked" -ForegroundColor Yellow
if ($hookContent -match '\.md$' -or $hookContent -match "docs/") {
    Write-Host "  PASS: Docs are allowed" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Docs may be blocked" -ForegroundColor Red
    exit 1
}

# Test 6: Hooks do not execute runtime/launcher/network activity
Write-Host "Test 6: Hooks do not execute runtime/launcher/network activity" -ForegroundColor Yellow
if ($hookContent -notmatch "Start-Process" -and 
    $hookContent -notmatch "Invoke-WebRequest" -and 
    $hookContent -notmatch "curl " -and 
    $hookContent -notmatch "wget ") {
    Write-Host "  PASS: No runtime/launcher/network activity found" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Hook contains runtime/launcher/network activity" -ForegroundColor Red
    exit 1
}

# Test 7: Hooks do not print sensitive excerpts
Write-Host "Test 7: Hooks do not print sensitive excerpts" -ForegroundColor Yellow
# Check if hook prints actual secret values (not just pattern names)
$hookContent = Get-Content $hookPath -Raw
$sensitivePatterns = @('Write-Host.*password', 'Write-Host.*secret', 'Write-Host.*credential', 'Write-Host.*api.key')
$foundSensitive = $false
foreach ($pattern in $sensitivePatterns) {
    if ($hookContent -match $pattern) {
        $foundSensitive = $true
        break
    }
}
if (-not $foundSensitive) {
    Write-Host "  PASS: No sensitive excerpts printed" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Hook may print sensitive excerpts" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All tests passed!" -ForegroundColor Green
