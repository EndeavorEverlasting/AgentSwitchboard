[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [string]((& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1))
}
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    throw 'Unable to resolve the repository root.'
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
Set-Location -LiteralPath $RootPath

& pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& python tests/test_windows_profile_launch_mode_harness.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$generatedPatterns = @(
    'windows-launch-mode-run-context.json',
    'windows-launch-before-snapshot.json',
    'windows-launch-after-snapshot.json',
    'windows-launch-mode-result.json',
    'windows-launch-mode-operator-report.md',
    'windows-launch-mode-final-handoff.json',
    '*.stdout.log',
    '*.stderr.log'
)

$staged = @(& git diff --cached --name-only --diff-filter=ACMR)
foreach ($path in $staged) {
    foreach ($pattern in $generatedPatterns) {
        if ((Split-Path -Leaf $path) -like $pattern) {
            Write-Error "Generated launch-mode evidence must remain untracked: $path"
            exit 41
        }
    }
}

Write-Host 'Windows Profile launch-mode pre-commit checks passed.' -ForegroundColor Green
exit 0
