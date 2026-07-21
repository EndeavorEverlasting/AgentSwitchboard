[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [string](& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
}
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    throw 'Unable to resolve the repository root.'
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
Set-Location -LiteralPath $RootPath

& pwsh -NoLogo -NoProfile -File scripts/Test-TmuxNewInstanceShortcutHarness.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& python tests/test_tmux_new_instance_shortcut_harness.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$generatedNames = @(
    'tmux-new-instance-shortcut-install-plan.json',
    'tmux-new-instance-shortcut-install-receipt.json',
    'tmux-new-instance-shortcut-operator-report.md',
    'tmux-new-instance-launch-plan.json',
    'tmux-new-instance-launch-result.json',
    'tmux-new-instance-final-handoff.json',
    'tmux-new-instance-shortcut-status.json',
    'tmux-new-instance-shortcut-status.md'
)

$staged = @(& git diff --cached --name-only --diff-filter=ACMR)
foreach ($path in $staged) {
    if ($generatedNames -contains (Split-Path -Leaf $path)) {
        Write-Error "Generated tmux shortcut evidence must remain untracked: $path"
        exit 41
    }
}

Write-Host 'tmux new-instance shortcut pre-commit checks passed.' -ForegroundColor Green
exit 0
