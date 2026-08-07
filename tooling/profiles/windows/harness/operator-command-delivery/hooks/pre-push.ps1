[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..\..')).Path
$validator = Join-Path $repoRoot 'scripts\Test-OperatorCommandDeliveryHarnessCompleteness.ps1'
$pythonTest = Join-Path $repoRoot 'tests\test_operator_command_delivery_harness.py'

if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Operator command-delivery validator is missing: $validator"
}
if (-not (Test-Path -LiteralPath $pythonTest -PathType Leaf)) {
    throw "Operator command-delivery Python contract is missing: $pythonTest"
}

& pwsh -NoLogo -NoProfile -File $validator
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& python $pythonTest
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host 'PASS: operator command-delivery pre-push checks' -ForegroundColor Green
exit 0
