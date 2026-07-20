[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

Write-Host 'PI HARNESS PRE-COMMIT (OPT-IN)' -ForegroundColor Cyan
Write-Host 'This script is tracked but is never installed as a Git hook automatically.'

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-PiHarnessCompleteness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& python (Join-Path $RootPath 'tests/test_pi_harness_contracts.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $RootPath diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$staged = @(& git -C $RootPath diff --cached --name-only)
$blockedPatterns = @('pi-run-context.json', 'pi-fusion-result.json', 'pi-validation-ledger.json', 'pi-operator-report.md', 'pi-final-handoff.json')
$blocked = @($staged | Where-Object { $name = $_; $blockedPatterns | Where-Object { $name.EndsWith($_, [StringComparison]::OrdinalIgnoreCase) } })
if ($blocked.Count -gt 0) {
    Write-Error ("Generated Pi runtime evidence must remain untracked: {0}" -f ($blocked -join ', '))
    exit 1
}

Write-Host 'PASS: Pi harness completeness, dependency-free contracts, staged diff hygiene, and generated-evidence exclusion.' -ForegroundColor Green
exit 0
