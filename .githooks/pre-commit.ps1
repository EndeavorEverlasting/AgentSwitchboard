#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pre-commit hook for artifact hygiene.
.DESCRIPTION
    Prevents generated evidence, logs, saves, local tool installs, crash dumps,
    secrets, and machine-local junk from leaking into commits.
.NOTES
    This is a local opt-in hook. Install with: pwsh -File scripts/Install-Hooks.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Patterns that indicate generated/runtime/sensitive artifacts
$blockedPatterns = @(
    # Runtime logs and evidence
    '\.log$',
    '\.log\.\d+$',
    'gnhf\.log',
    'iteration-\d+\.jsonl',
    
    # Crash dumps and core files
    'core\.dmp$',
    'core\.\d+$',
    '\.dmp$',
    'memory\.dump$',
    
    # Local tool installs and caches
    'node_modules/',
    '\.npm/',
    '\.cache/',
    '__pycache__/',
    '\.pytest_cache/',
    '\.mypy_cache/',
    
    # Secrets and credentials
    '\.env$',
    '\.env\.',
    'credentials\.json$',
    'secrets\.json$',
    '\.pem$',
    '\.key$',
    'id_rsa',
    'id_ed25519',
    
    # Machine-local paths
    'C:\\Users\\',
    'C:\\dev\\',
    '/home/',
    '/Users/',
    
    # Large binary artifacts
    '\.zip$',
    '\.tar\.gz$',
    '\.7z$',
    '\.rar$',
    
    # Database files
    '\.sqlite$',
    '\.sqlite3$',
    '\.db$',
    
    # OS noise
    '\.DS_Store$',
    'Thumbs\.db$',
    'desktop\.ini$',
    
    # Editor artifacts
    '\.swp$',
    '\.swo$',
    '\.vscode/settings\.json$',
    
    # Runtime output directories
    '^runs/',
    '^workstation-runtime/',
    '^billing_runs/',
    '^billing_runs_tmp/',
    '^Outputs/',
    '^Repaired/',
    '^Candidate/',
    '^ArtifactIntake/',
    '^artifacts/',
    '^outputs/',
    
    # Sensitive workbook artifacts
    'CANDIDATE_.*\.xlsx$',
    'web_repaired_.*\.xlsx$',
    'README_CANDIDATE_.*\.xlsx$',
    
    # Local env overrides
    '\.local\.ps1$',
    '\.local$'
)

# Patterns that are allowed (sanitized fixtures, docs)
$allowedPatterns = @(
    'tests/fixtures/',
    'docs/',
    '\.md$',
    '\.gitkeep$',
    '\.gitignore$',
    'AGENTS\.md$',
    'CODEBASE_MAP\.md$',
    'WORKFLOW\.md$',
    'ARTIFACT_REGISTRY\.md$',
    'SKILLS\.md$',
    'README\.md$'
)

# Get staged files
$stagedFiles = & git diff --cached --name-only --diff-filter=ACM

if (-not $stagedFiles) {
    Write-Host "[harness] No staged files to check." -ForegroundColor Green
    exit 0
}

$violations = @()

foreach ($file in $stagedFiles) {
    # Check if file is in allowed list
    $allowed = $false
    foreach ($pattern in $allowedPatterns) {
        if ($file -match $pattern) {
            $allowed = $true
            break
        }
    }
    
    if ($allowed) {
        continue
    }
    
    # Check if file matches blocked patterns
    foreach ($pattern in $blockedPatterns) {
        if ($file -match $pattern) {
            $violations += $file
            break
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host ""
    Write-Host "[harness] refusing staged generated/runtime artifact:" -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host "  - $v" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Move live/generated evidence back to ignored local output," -ForegroundColor Cyan
    Write-Host "or commit a sanitized fixture under an approved fixture/docs path." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To unstage a file: git reset HEAD <file>" -ForegroundColor Gray
    Write-Host "To force commit (not recommended): git commit --no-verify" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Write-Host "[harness] Artifact hygiene check passed." -ForegroundColor Green
exit 0
