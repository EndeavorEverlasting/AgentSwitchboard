[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'tooling/profiles/windows/harness/operator-command-delivery/codebase-map.json',
    'tooling/profiles/windows/harness/operator-command-delivery/artifact-registry.json',
    'tooling/profiles/windows/harness/operator-command-delivery/workflows/verify-command-delivery.workflow.json',
    'tooling/profiles/windows/harness/operator-command-delivery/workflows/handle-command-delivery-failure.workflow.json',
    'tooling/profiles/windows/harness/operator-command-delivery/fixtures/valid-powershell-command.fixture.ps1',
    'tooling/profiles/windows/harness/operator-command-delivery/fixtures/invalid-corrupted-command.fixture.txt',
    'tooling/profiles/windows/harness/operator-command-delivery/operator-report.template.md',
    'tooling/profiles/windows/harness/operator-command-delivery/hooks/pre-push.ps1',
    '.ai/skills/operator-command-delivery/SKILL.md',
    'docs/harness/operator-command-delivery.md',
    'tests/test_operator_command_delivery_harness.py',
    '.github/workflows/operator-command-delivery-harness.yml'
)

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) {
    [void]$failures.Add($Message)
}

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "missing tracked harness component: $relative"
    }
}

foreach ($relative in @(
    'tooling/profiles/windows/harness/operator-command-delivery/codebase-map.json',
    'tooling/profiles/windows/harness/operator-command-delivery/artifact-registry.json',
    'tooling/profiles/windows/harness/operator-command-delivery/workflows/verify-command-delivery.workflow.json',
    'tooling/profiles/windows/harness/operator-command-delivery/workflows/handle-command-delivery-failure.workflow.json'
)) {
    $path = Join-Path $repoRoot $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
        catch { Add-Failure "invalid JSON: $relative :: $($_.Exception.Message)" }
    }
}

$validPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/fixtures/valid-powershell-command.fixture.ps1'
$invalidPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/fixtures/invalid-corrupted-command.fixture.txt'
if (Test-Path -LiteralPath $validPath -PathType Leaf) {
    $valid = Get-Content -LiteralPath $validPath -Raw
    foreach ($token in @('$env:TEMP', '$env:LOCALAPPDATA', 'gh api --method GET', 'CHILD_EXIT_CODE=', 'ARTIFACT=')) {
        if (-not $valid.Contains($token)) { Add-Failure "valid fixture missing token: $token" }
    }
    if ($valid -match '\$env\\:') { Add-Failure 'valid fixture contains escaped PowerShell environment-variable colon' }
    if ($valid -match '(?m)^\s*PS\s+[A-Za-z]:\\') { Add-Failure 'valid fixture contains a PowerShell prompt marker' }
    if ($valid -match '(?m)^\s*exit\s+') { Add-Failure 'valid fixture contains top-level exit' }
    if ($valid -match 'contents/[^\s"'']+\?ref=') { Add-Failure 'valid fixture uses interpolated content query-string retrieval' }
}
if (Test-Path -LiteralPath $invalidPath -PathType Leaf) {
    $invalid = Get-Content -LiteralPath $invalidPath -Raw
    if ($invalid -notmatch '\$env\\:TEMP') { Add-Failure 'negative fixture no longer contains escaped TEMP regression' }
    if ($invalid -notmatch '\$env\\:LOCALAPPDATA') { Add-Failure 'negative fixture no longer contains escaped LOCALAPPDATA regression' }
    if ($invalid -notmatch '(?m)^PS\s+[A-Za-z]:\\') { Add-Failure 'negative fixture no longer contains prompt contamination regression' }
    if ($invalid -notmatch 'contents/[^\s"'']+\?ref=') { Add-Failure 'negative fixture no longer contains query-string retrieval regression' }
    if ($invalid -notmatch '(?m);\s*exit\s+\$LASTEXITCODE') { Add-Failure 'negative fixture no longer contains top-level exit regression' }
}

$skillPath = Join-Path $repoRoot '.ai/skills/operator-command-delivery/SKILL.md'
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($heading in @('## Trigger','## Required inputs','## Procedure','## Expected outputs','## Deterministic validation','## Proof promotion','## Forbidden scope','## Stop and escalate')) {
        if (-not $skill.Contains($heading)) { Add-Failure "skill missing heading: $heading" }
    }
}

$reportPath = Join-Path $repoRoot 'tooling/profiles/windows/harness/operator-command-delivery/operator-report.template.md'
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    $report = Get-Content -LiteralPath $reportPath -Raw
    foreach ($token in @('{{STATUS}}','{{RESOLVED_COMMIT}}','{{CHILD_EXIT_CODE}}','{{DOWNSTREAM_ARTIFACT}}','{{PROOF_CEILING}}','{{NEXT_COMMAND}}')) {
        if (-not $report.Contains($token)) { Add-Failure "operator report missing placeholder: $token" }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Operator Command Delivery Harness: FAIL' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "- $failure" -ForegroundColor Red }
    exit 1
}

Write-Host "Operator Command Delivery Harness: PASS ($($required.Count)/$($required.Count) components)" -ForegroundColor Green
Write-Host 'Guarded regressions: escaped env-var colon, prompt contamination, query-string content retrieval, top-level interactive exit.'
exit 0
