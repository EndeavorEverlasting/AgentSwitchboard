[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$GitCommand = if ($env:OS -eq 'Windows_NT') { 'git.exe' } else { 'git' }

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$staged = @(& $GitCommand -C $RootPath diff --cached --name-only --diff-filter=ACMR)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not inspect the staged file list.'
}

$ownedPrefixes = @(
    'Bootstrap-Technician-ExactHead.cmd',
    'scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1',
    'scripts/Test-StaleCheckoutExactHeadBootstrap.ps1',
    'tests/test_stale_checkout_exact_head_bootstrap.py',
    'tooling/profiles/windows/harness/stale-checkout-exact-head/',
    'tooling/profiles/windows/Get-StaleCheckoutExactHeadHarnessStatus.ps1',
    'tooling/profiles/windows/hooks/Invoke-StaleCheckoutExactHeadPreCommit.ps1',
    '.ai/skills/stale-checkout-exact-head-bootstrap/',
    'docs/harness/stale-checkout-exact-head-bootstrap.md',
    '.github/workflows/stale-checkout-exact-head-bootstrap.yml'
)

$relevant = @($staged | Where-Object {
    $candidate = [string]$_
    @($ownedPrefixes | Where-Object { $candidate.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
})
if ($relevant.Count -eq 0) {
    Write-Host 'Stale-checkout exact-head pre-commit: no owned staged paths.'
    return
}

& (Join-Path $RootPath 'scripts\Test-StaleCheckoutExactHeadBootstrap.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) {
    throw "Stale-checkout exact-head validation failed with exit code $LASTEXITCODE."
}

& $GitCommand -C $RootPath --no-pager diff --cached --check
if ($LASTEXITCODE -ne 0) {
    throw 'Staged diff hygiene failed.'
}

Write-Host 'Stale-checkout exact-head pre-commit: PASS'
