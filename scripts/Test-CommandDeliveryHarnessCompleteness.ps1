[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$GitCommand = if ($env:OS -eq 'Windows_NT') { 'git.exe' } else { 'git' }
$PowerShellHost = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    'pwsh'
}
elseif ($env:OS -eq 'Windows_NT' -and (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
    'powershell.exe'
}
else {
    throw 'Neither PowerShell 7 nor Windows PowerShell was found for child validator execution.'
}
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [string]((& $GitCommand -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1))
}
if ([string]::IsNullOrWhiteSpace($RootPath)) { throw 'Unable to resolve repository root.' }
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
Set-Location -LiteralPath $RootPath

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $OutputRoot = Join-Path $base 'AgentSwitchboard/command-delivery-harness'
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

& python -m unittest tests.test_skill_factoring_contracts tests.test_command_delivery_harness tests.test_native_exitcode_hygiene
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$skillValidator = Join-Path $PSScriptRoot 'Test-SkillFactoringContracts.ps1'
& $PowerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $skillValidator -RootPath $RootPath -OutputRoot (Join-Path $OutputRoot 'skill-factoring')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$statusReporter = Join-Path $RootPath 'tooling/skills/Get-CommandDeliveryHarnessStatus.ps1'
& $PowerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $statusReporter -RootPath $RootPath -OutputDirectory $OutputRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $GitCommand -C $RootPath --no-pager diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Command-delivery harness completeness checks passed.' -ForegroundColor Green
exit 0
