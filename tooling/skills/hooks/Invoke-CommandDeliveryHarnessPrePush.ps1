[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$GitCommand = if ($env:OS -eq 'Windows_NT') { 'git.exe' } else { 'git' }
$PowerShellHost = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    'pwsh'
}
elseif ($env:OS -eq 'Windows_NT' -and (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
    'powershell.exe'
}
else {
    throw 'Neither PowerShell 7 nor Windows PowerShell was found for hook validation.'
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [string]((& $GitCommand -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1))
}
if ([string]::IsNullOrWhiteSpace($RootPath)) { throw 'Unable to resolve repository root.' }
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
Set-Location -LiteralPath $RootPath

$completeness = Join-Path $RootPath 'scripts/Test-CommandDeliveryHarnessCompleteness.ps1'
& $PowerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $completeness -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($env:OS -eq 'Windows_NT') {
    $entrypoint = Join-Path $RootPath 'scripts/Test-CommandDeliveryEntrypoint.ps1'
    & $PowerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $entrypoint -RootPath $RootPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
else {
    Write-Host 'SKIP: outer CMD entrypoint proof runs on Windows CI and Windows pre-push.' -ForegroundColor Yellow
}

& $GitCommand --no-pager diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Command-delivery pre-push checks passed.' -ForegroundColor Green
exit 0
