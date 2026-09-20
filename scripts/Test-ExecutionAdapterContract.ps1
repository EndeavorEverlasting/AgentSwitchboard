#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $root 'tests/test_execution_adapter_contract.py'

if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
    Write-Error "Execution adapter contract test not found: $testPath" -ErrorAction Continue
    exit 2
}

$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Error 'Python 3 is required for execution-adapter contract validation.' -ErrorAction Continue
    exit 2
}

& $python.Source $testPath
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Error "Execution adapter contract validation failed with exit code $code." -ErrorAction Continue
    exit $code
}

Write-Host 'PASS: execution adapter contract v1' -ForegroundColor Green
exit 0
