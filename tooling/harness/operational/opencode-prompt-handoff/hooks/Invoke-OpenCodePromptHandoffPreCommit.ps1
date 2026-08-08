[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-OpenCodePromptHandoffHarness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $RootPath diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '[PASS] opt-in OpenCode prompt-handoff pre-commit checks passed'
exit 0
