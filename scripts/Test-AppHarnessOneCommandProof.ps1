[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot,
    [ValidateRange(5, 120)]
    [int]$ValidatorTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Invoke-TrackedPowerShell {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $hostPath = (Get-Process -Id $PID).Path
    $global:LASTEXITCODE = 0
    & $hostPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    $exitCode = [int]$global:LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Required offline validator failed with exit code ${exitCode}: $ScriptPath"
    }
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $candidateRoot = Split-Path -Parent $PSScriptRoot
    $global:LASTEXITCODE = 0
    $RootPath = [string]((& git -C $candidateRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1))
    $gitExit = [int]$global:LASTEXITCODE
    if ($gitExit -ne 0 -or [string]::IsNullOrWhiteSpace($RootPath)) {
        throw "Unable to detect repository root from $candidateRoot."
    }
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $nonce = ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard/app-harness-proof/${stamp}-${nonce}"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$parseTargets = @(
    'scripts/Test-AppHarness.ps1',
    'scripts/Test-AppHarnessOneCommandProof.ps1',
    'scripts/Test-CommandDeliveryHarnessCompleteness.ps1',
    'scripts/Test-CommandDeliveryEntrypoint.ps1'
)
foreach ($relative in $parseTargets) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $RootPath $relative),
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed for $relative`: $($errors -join [Environment]::NewLine)"
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python 3 was not found on PATH.' }
$staticContract = Join-Path $RootPath 'tests/test_app_harness_validator.py'
if (-not (Test-Path -LiteralPath $staticContract -PathType Leaf)) {
    throw "App harness static contract is missing: $staticContract"
}
$global:LASTEXITCODE = 0
& $python.Source $staticContract
$staticExit = [int]$global:LASTEXITCODE
if ($staticExit -ne 0) {
    throw "App harness static contract failed with exit code ${staticExit}: $staticContract"
}

$completeness = Join-Path $RootPath 'scripts/Test-CommandDeliveryHarnessCompleteness.ps1'
$appHarness = Join-Path $RootPath 'scripts/Test-AppHarness.ps1'
foreach ($required in @($completeness, $appHarness)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required offline validator is missing: $required"
    }
}

Invoke-TrackedPowerShell -ScriptPath $completeness -Arguments @(
    '-RootPath', $RootPath,
    '-OutputRoot', (Join-Path $OutputRoot 'command-delivery')
)
Invoke-TrackedPowerShell -ScriptPath $appHarness -Arguments @(
    '-RootPath', $RootPath,
    '-OutputRoot', $OutputRoot,
    '-ValidatorTimeoutSeconds', [string]$ValidatorTimeoutSeconds
)

$jsonPath = Join-Path $OutputRoot 'app-harness-validation.json'
$reportPath = Join-Path $OutputRoot 'app-harness-validation.md'
if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
    throw "App harness JSON result is missing: $jsonPath"
}
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "App harness English matrix is missing: $reportPath"
}

$result = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
if ([string]$result.schema -ne 'agentswitchboard.app-harness-validation.v1') {
    throw "Unexpected app harness result schema: $($result.schema)"
}
if ([string]$result.proofLevel -ne 'offline-synthetic-harness') {
    throw "App harness proof level was inflated: $($result.proofLevel)"
}
if ([int]$result.summary.failed -ne 0) {
    throw "App harness matrix contains $($result.summary.failed) failed checks: $jsonPath"
}
if ([bool]$result.runContext.networkAllowed -or [bool]$result.runContext.runtimeAllowed -or [bool]$result.runContext.mutationAllowed) {
    throw "App harness run context allowed a forbidden execution surface: $jsonPath"
}

$requiredChecks = @('required-files', 'run-context', 'artifact-registry', 'report-renderer', 'hook-hygiene', 'offline-validators')
$checkIds = @($result.checks | ForEach-Object { [string]$_.id })
$missingChecks = @($requiredChecks | Where-Object { $checkIds -notcontains $_ })
if ($missingChecks.Count -gt 0) {
    throw "App harness matrix omitted required checks: $($missingChecks -join ', ')"
}
$optional = @($result.checks | Where-Object { [string]$_.id -eq 'optional-mcp-symbol-smoke' } | Select-Object -First 1)
if ($optional.Count -ne 1) {
    throw 'App harness matrix omitted optional MCP/LSP readiness.'
}
if ([string]$optional[0].status -eq 'SKIP' -and [string]$optional[0].reason -notin @('lsp_project_not_loaded', 'offline_symbol_index_missing')) {
    throw "Optional MCP/LSP skip used an unknown reason: $($optional[0].reason)"
}

$report = Get-Content -LiteralPath $reportPath -Raw
foreach ($token in @('# APP HARNESS VALIDATION', '[PASS] required files', 'Result:', 'no runtime')) {
    if (-not $report.Contains($token)) {
        throw "App harness English matrix is missing token: $token"
    }
}

Write-Host 'ONE-COMMAND HARNESS PROOF: PASS' -ForegroundColor Green
Write-Host "JSON:   $jsonPath" -ForegroundColor Cyan
Write-Host "Report: $reportPath" -ForegroundColor Cyan
Write-Host 'Proof ceiling: offline synthetic harness only; no launcher, app, provider, network, account, save, target, or runtime execution.' -ForegroundColor Yellow
exit 0
