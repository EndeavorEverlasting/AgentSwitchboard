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

& $GitCommand diff --cached --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$generatedNames = @(
    'skill-factoring-report.json',
    'skill-factoring-report.md',
    'command-delivery-harness-status.json',
    'command-delivery-harness-status.md',
    'command-delivery-handoff.json',
    'command-delivery-entrypoint-result.json',
    'command-delivery-entrypoint-result.md'
)
$staged = @(& $GitCommand diff --cached --name-only --diff-filter=ACMR)
foreach ($path in $staged) {
    if ((Split-Path -Leaf $path) -in $generatedNames) {
        Write-Error "Generated command-delivery evidence must remain untracked: $path"
        exit 41
    }
}
Write-Host 'Command-delivery pre-commit checks passed.' -ForegroundColor Green
exit 0
