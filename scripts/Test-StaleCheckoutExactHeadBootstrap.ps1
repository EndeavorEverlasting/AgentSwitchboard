[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$GitCommand = if ($env:OS -eq 'Windows_NT') { 'git.exe' } else { 'git' }

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$manifestPath = Join-Path $RootPath 'tooling\profiles\windows\harness\stale-checkout-exact-head\manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$requiredIds = @(
    'bootstrap-cmd',
    'bootstrap-engine',
    'codebase-map',
    'artifact-registry',
    'workflow',
    'schema',
    'fixture',
    'operator-report-template',
    'status-reporter',
    'validator',
    'python-validator',
    'opt-in-hook',
    'skill',
    'operator-guide',
    'ci-workflow'
)

$ids = @($manifest.components | ForEach-Object { [string]$_.id })
foreach ($id in $requiredIds) {
    if ($id -notin $ids) {
        throw "Manifest is missing required component: $id"
    }
}

foreach ($component in $manifest.components) {
    $componentPath = Join-Path $RootPath ([string]$component.path)
    if (-not (Test-Path -LiteralPath $componentPath -PathType Leaf)) {
        throw "Missing harness component: $($component.path)"
    }
    & $GitCommand -C $RootPath ls-files --error-unmatch -- ([string]$component.path) *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Harness component is not tracked: $($component.path)"
    }
}

$jsonContracts = @(
    'tooling/profiles/windows/harness/stale-checkout-exact-head/manifest.json',
    'tooling/profiles/windows/harness/stale-checkout-exact-head/codebase-map.json',
    'tooling/profiles/windows/harness/stale-checkout-exact-head/artifact-registry.json',
    'tooling/profiles/windows/harness/stale-checkout-exact-head/workflows/bootstrap.workflow.json',
    'tooling/profiles/windows/harness/stale-checkout-exact-head/schemas/bootstrap-result.schema.json',
    'tooling/profiles/windows/harness/stale-checkout-exact-head/fixtures/bootstrap-cases.fixture.json'
)
foreach ($relativePath in $jsonContracts) {
    Get-Content -LiteralPath (Join-Path $RootPath $relativePath) -Raw | ConvertFrom-Json | Out-Null
}

$enginePath = Join-Path $RootPath 'scripts\Invoke-StaleCheckoutExactHeadBootstrap.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($enginePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Bootstrap engine parser errors:`n$($parseErrors.Message -join "`n")"
}

$engine = Get-Content -LiteralPath $enginePath -Raw
$requiredPatterns = @(
    "fetch', '--no-tags', 'origin', `$RemoteRef",
    "rev-parse', 'FETCH_HEAD'",
    "show', `$validatorSpec",
    'Invoke-TechnicianExactHeadValidation.ps1',
    "Where-Object { `$_.LastWriteTimeUtc -ge `$startedUtc }",
    'verifiedHead',
    'AGENT_SWITCHBOARD_NO_PAUSE',
    'Unexpected origin'
)
foreach ($pattern in $requiredPatterns) {
    if ($engine -notlike "*$pattern*") {
        throw "Bootstrap engine is missing required contract text: $pattern"
    }
}

$forbiddenPatterns = @(
    'git reset',
    'git clean',
    'git stash',
    'fetch --force',
    'checkout -f',
    'worktree remove --force'
)
foreach ($pattern in $forbiddenPatterns) {
    if ($engine -like "*$pattern*") {
        throw "Bootstrap engine contains forbidden operation: $pattern"
    }
}
if ($engine.Contains('-Encoding utf8NoBOM')) {
    throw 'Bootstrap engine uses a PowerShell 7-only encoding name.'
}
if (-not $engine.Contains('New-Object Text.UTF8Encoding($false)')) {
    throw 'Bootstrap engine is missing PowerShell 5.1-compatible UTF-8 no-BOM output.'
}

$reporterSource = Get-Content -LiteralPath (Join-Path $RootPath 'tooling\profiles\windows\Get-StaleCheckoutExactHeadHarnessStatus.ps1') -Raw
if ($reporterSource.Contains('-Encoding utf8NoBOM')) {
    throw 'Harness status reporter uses a PowerShell 7-only encoding name.'
}
if (-not $reporterSource.Contains('New-Object Text.UTF8Encoding($false)')) {
    throw 'Harness status reporter is missing PowerShell 5.1-compatible UTF-8 no-BOM output.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard-stale-checkout-harness-status'
}
& (Join-Path $RootPath 'tooling\profiles\windows\Get-StaleCheckoutExactHeadHarnessStatus.ps1') -RootPath $RootPath -OutputRoot $OutputRoot
if ($LASTEXITCODE -ne 0) {
    throw "Harness status reporter failed with exit code $LASTEXITCODE."
}

$statusJson = Join-Path $OutputRoot 'stale-checkout-exact-head-harness-status.json'
$status = Get-Content -LiteralPath $statusJson -Raw | ConvertFrom-Json
if ($status.status -ne 'ready') {
    throw "Harness status is not ready: $statusJson"
}

Write-Host "Stale-checkout exact-head harness validation: PASS ($($manifest.components.Count) components)"
