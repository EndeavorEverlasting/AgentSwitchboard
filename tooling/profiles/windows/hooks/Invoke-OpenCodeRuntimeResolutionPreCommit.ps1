[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts\Test-OpenCodeRuntimeResolutionHarness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $RootPath diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$generatedRoots = @(
    'opencode-runtime-run-context.json',
    'opencode-runtime-resolution-snapshot.json',
    'opencode-runtime-classification.json',
    'opencode-runtime-operator-report.md',
    'opencode-runtime-final-handoff.json'
)
$staged = @(& git -C $RootPath diff --cached --name-only)
foreach ($name in $generatedRoots) {
    if ($staged | Where-Object { [IO.Path]::GetFileName([string]$_) -eq $name }) {
        Write-Error "Generated local-operational evidence must not be committed: $name"
        exit 1
    }
}

Write-Host '[PASS] OpenCode runtime-resolution pre-commit checks passed.' -ForegroundColor Green
exit 0
