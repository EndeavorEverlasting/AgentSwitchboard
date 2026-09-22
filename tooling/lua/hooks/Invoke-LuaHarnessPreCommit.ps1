[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

& pwsh -NoLogo -NoProfile -File (Join-Path $Root 'scripts\Test-LuaHarnessCompleteness.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& git -C $Root diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$forbidden = @(
    'lua-harness-report.md',
    'lua-readiness.json',
    'lua-runtime-handoff.json'
)
$staged = @(git -C $Root diff --cached --name-only)
foreach ($name in $forbidden) {
    if ($staged | Where-Object { [System.IO.Path]::GetFileName($_) -eq $name }) {
        Write-Error "Generated Lua evidence must remain untracked: $name"
        exit 1
    }
}
Write-Host '[PASS] LUA_HARNESS_PRECOMMIT'
