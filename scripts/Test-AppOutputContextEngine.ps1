[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$required = @(
    'Contextualize-AppOutput.cmd',
    'tooling/context/Contextualize-AppOutput.py',
    'tests/test_app_output_context_engine.py',
    '.ai/harness/schemas/app-output-context.schema.json',
    '.ai/harness/workflows/app-output-contextualization.workflow.json',
    '.ai/harness/fixtures/app-output-context/prompt-registry.fixture.json',
    '.ai/harness/fixtures/app-output-context/failing-app.log',
    '.ai/skills/app-output-contextualization/SKILL.md',
    'docs/harness/app-output-context-engine.md',
    '.github/workflows/app-output-context-engine.yml'
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf)) {
        [void]$failures.Add("missing required file: $relativePath")
    }
}

foreach ($relativePath in @(
    '.ai/harness/schemas/app-output-context.schema.json',
    '.ai/harness/workflows/app-output-contextualization.workflow.json',
    '.ai/harness/fixtures/app-output-context/prompt-registry.fixture.json'
)) {
    try {
        Get-Content -LiteralPath (Join-Path $RootPath $relativePath) -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        [void]$failures.Add("invalid JSON: $relativePath :: $($_.Exception.Message)")
    }
}

$registrations = @{
    'SKILLS.md' = 'app-output-contextualization'
    'CAPABILITIES.md' = 'app.output.contextualize'
    'TRIGGERS.md' = 'app.output-context-request'
    'CODEBASE_MAP.md' = 'Contextualize-AppOutput.cmd'
    '.ai/agent-contract.json' = 'appOutputContext'
    '.ai/harness/manifest.json' = 'appOutputContext'
    '.ai/harness/artifact-registry.json' = 'app-output-context-json'
    '.ai/harness/app-composition.graph.json' = 'validator.app-output-context'
}
foreach ($relativePath in $registrations.Keys) {
    $path = Join-Path $RootPath $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("registration file missing: $relativePath")
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw
    if (-not $text.Contains($registrations[$relativePath])) {
        [void]$failures.Add("registration missing: $relativePath -> $($registrations[$relativePath])")
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if ($null -eq $python) {
    [void]$failures.Add('Python 3 command is unavailable')
}
else {
    $output = & $python.Source (Join-Path $RootPath 'tests/test_app_output_context_engine.py') 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        [void]$failures.Add("Python contracts failed with exit $exitCode :: $(($output | ForEach-Object { [string]$_ }) -join ' ')")
    }
}

Write-Host 'APP OUTPUT CONTEXT ENGINE CONTRACT' -ForegroundColor Cyan
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "[FAIL] $failure" -ForegroundColor Red
    }
    exit 1
}

foreach ($relativePath in $required) {
    Write-Host "[PASS] $relativePath" -ForegroundColor Green
}
Write-Host '[PASS] deterministic Python contracts' -ForegroundColor Green
Write-Host 'Proof ceiling: offline parsing, redaction, prompt-kit ranking, and report rendering only.' -ForegroundColor Yellow
exit 0
