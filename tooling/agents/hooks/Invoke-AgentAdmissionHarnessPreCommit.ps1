[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

Write-Host 'AGENT ADMISSION HARNESS PRE-COMMIT (OPT-IN)' -ForegroundColor Cyan
Write-Host 'This script is tracked but is never installed as a Git hook automatically.'

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-AgentAdmissionHarness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& python (Join-Path $RootPath 'tests/test_agent_admission_harness.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $RootPath diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$staged = @(& git -C $RootPath diff --cached --name-only)
$blockedPatterns = @(
    'agent-admission-run-context.json',
    'agent-admission-eval-result.json',
    'agent-route-decision.json',
    'agent-execution-identity.json',
    'agent-proof-ledger.json',
    'agent-admission-operator-report.md',
    'agent-admission-final-handoff.json'
)
$blocked = @($staged | Where-Object {
    $name = $_
    $blockedPatterns | Where-Object { $name.EndsWith($_, [StringComparison]::OrdinalIgnoreCase) }
})
if ($blocked.Count -gt 0) {
    Write-Error ("Generated agent-admission runtime evidence must remain untracked: {0}" -f ($blocked -join ', '))
    exit 1
}

Write-Host 'PASS: admission harness completeness, dependency-free contracts, staged diff hygiene, and generated-evidence exclusion.' -ForegroundColor Green
exit 0
