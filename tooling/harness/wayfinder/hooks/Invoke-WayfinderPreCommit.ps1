[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))),
    [string]$PythonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

& (Join-Path $RootPath 'scripts/Test-WayfinderPythonBinding.ps1') -RootPath $RootPath -PythonPath $PythonPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

. (Join-Path $RootPath 'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1')
$binding = Resolve-WayfinderPython -PythonPath $PythonPath -RootPath $RootPath
& $binding.Path (Join-Path $RootPath 'tests/test_wayfinder_runtime_binding_contract.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $RootPath 'scripts/Test-WayfinderHarnessCompleteness.ps1') -RootPath $RootPath -PythonPath $binding.Path
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'PASS: optional Wayfinder pre-commit hook' -ForegroundColor Green
Write-Host 'This helper is opt-in and is never installed implicitly.'
exit 0
