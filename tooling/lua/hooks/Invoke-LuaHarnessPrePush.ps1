[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaseRef
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

& pwsh -NoLogo -NoProfile -File (Join-Path $Root 'scripts\Test-LuaHarnessCompleteness.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $Root rev-parse --verify $BaseRef *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Unable to resolve BaseRef: $BaseRef"
    exit 2
}

& git -C $Root diff --check "$BaseRef...HEAD"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[PASS] LUA_HARNESS_PREPUSH base=$BaseRef"
