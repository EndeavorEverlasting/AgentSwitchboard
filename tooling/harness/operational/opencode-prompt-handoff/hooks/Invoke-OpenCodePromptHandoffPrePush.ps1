[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseRef,
    [string]$RootPath = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($BaseRef)) {
    throw '-BaseRef is required so the push range is explicit.'
}

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-OpenCodePromptHandoffHarness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $RootPath rev-parse --verify "$BaseRef^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { throw "BaseRef could not be resolved: $BaseRef" }

& git -C $RootPath diff --check "$BaseRef...HEAD"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '[PASS] opt-in OpenCode prompt-handoff pre-push checks passed'
exit 0
