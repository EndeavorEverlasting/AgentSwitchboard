[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

Write-Host 'TYPED CASCADE HARNESS PRE-COMMIT (OPT-IN)' -ForegroundColor Cyan
Write-Host 'This script is tracked but is never installed as a Git hook automatically.'

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-TypedCascadeHarness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& python (Join-Path $RootPath 'tests/test_typed_cascade_harness.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-RuntimeEventContract.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $RootPath diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$staged = @(& git -C $RootPath diff --cached --name-only)
$blockedNames = @(
    'cascade-run-context.json',
    'cascade-pre-gate-result.json',
    'cascade-action-observation.json',
    'cascade-post-gate-result.json',
    'cascade-successor-event.json',
    'cascade-proof-ledger.json',
    'cascade-operator-report.md',
    'cascade-final-handoff.json'
)
$blocked = @($staged | Where-Object {
    $candidate = $_
    @($blockedNames | Where-Object { $candidate.EndsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
})
if ($blocked.Count -gt 0) {
    Write-Error ("Generated typed-cascade evidence must remain untracked: {0}" -f ($blocked -join ', '))
    exit 1
}

Write-Host 'PASS: typed cascade completeness, semantic fixtures, runtime-event compatibility, staged diff hygiene, and generated-evidence exclusion.' -ForegroundColor Green
exit 0
