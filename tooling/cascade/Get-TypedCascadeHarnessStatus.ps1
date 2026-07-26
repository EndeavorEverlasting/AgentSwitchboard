[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputDirectory,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    'tooling/cascade/harness/typed-gates/codebase-map.json',
    'tooling/cascade/harness/typed-gates/typed-cascade.registry.json',
    'tooling/cascade/harness/typed-gates/ontology.registry.json',
    'tooling/cascade/harness/typed-gates/artifact-registry.json',
    'tooling/cascade/harness/typed-gates/workflows/task-intake.workflow.json',
    'tooling/cascade/harness/typed-gates/workflows/pre-action-validation.workflow.json',
    'tooling/cascade/harness/typed-gates/workflows/post-action-validation.workflow.json',
    'tooling/cascade/harness/typed-gates/workflows/cascade-emission.workflow.json',
    'tooling/cascade/harness/typed-gates/workflows/failure-handoff.workflow.json',
    'tooling/cascade/harness/typed-gates/schemas/typed-cascade-harness.schema.json',
    'tooling/cascade/harness/typed-gates/fixtures/typed-cascade.cases.json',
    '.ai/skills/typed-cascade-validation/SKILL.md',
    'scripts/Test-TypedCascadeHarness.ps1',
    'tests/test_typed_cascade_harness.py',
    'tooling/cascade/hooks/Invoke-TypedCascadeHarnessPreCommit.ps1',
    'docs/harness/typed-cascade-validation.md',
    '.github/workflows/typed-cascade-harness.yml',
    'Test-TypedCascadeHarness.cmd'
)

$components = foreach ($relativePath in $required) {
    $path = Join-Path $RootPath $relativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $tracked = $false
    if ($exists) {
        $null = & git -C $RootPath ls-files --error-unmatch -- $relativePath 2>$null
        $tracked = $LASTEXITCODE -eq 0
    }
    [ordered]@{ path = $relativePath; exists = $exists; tracked = $tracked }
}

$branch = (& git -C $RootPath branch --show-current 2>$null | Select-Object -First 1)
$head = (& git -C $RootPath rev-parse HEAD 2>$null | Select-Object -First 1)
$dirty = [bool](& git -C $RootPath status --short 2>$null)
$missing = @($components | Where-Object { -not $_.exists -or -not $_.tracked })

$working = @(
    'A pre-action structural gate is defined for required fields, types, ranges, enums, and declared authority prerequisites.',
    'A post-action semantic gate is defined for cardinality, disjointness, enumeration, domain/range, current-run references, and world-state coherence.',
    'Success propagation requires both gates plus one fresh action observation tied to the same run/action/correlation identity.',
    'Synthetic fixtures exercise acceptance and rejection paths without product mutation or provider calls.'
)
$broken = @()
if ($missing.Count -gt 0) { $broken += "$($missing.Count) required tracked component(s) are missing or untracked." }
if ($dirty) { $broken += 'The checkout is dirty; a write lane must preserve or isolate unrelated work.' }
$gaps = @(
    'Product action dispatchers do not yet consume this gate registry automatically.',
    'No Pydantic runtime adapter is proven.',
    'No OWL reasoner or SHACL engine is proven.',
    'No live runtime event cascade or external side effect is proven by this status report.'
)

$status = if ($missing.Count -eq 0) { 'contract-ready' } else { 'incomplete' }
$nextCommand = 'pwsh -NoLogo -NoProfile -File scripts/Test-TypedCascadeHarness.ps1'
$result = [ordered]@{
    schema = 'agentswitchboard.typed-cascade-harness-status.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    branch = [string]$branch
    head = [string]$head
    dirty = $dirty
    components = $components
    working = $working
    broken = $broken
    missing = @($missing | ForEach-Object { $_.path })
    gaps = $gaps
    proofCeiling = 'Read-only repository contract state only; no product dispatch, Pydantic, OWL/SHACL, provider, live event, or target proof.'
    nextCommand = $nextCommand
}

Write-Host 'TYPED CASCADE VALIDATION HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Components: {0}/{1} ready" -f @($components | Where-Object { $_.exists -and $_.tracked }).Count, $components.Count)
Write-Host ''
Write-Host 'Working:'
$working | ForEach-Object { Write-Host "- $_" }
Write-Host 'Broken or blocked:'
if ($broken.Count -eq 0) { Write-Host '- None at repository-contract level.' } else { $broken | ForEach-Object { Write-Host "- $_" } }
Write-Host 'Missing runtime proof:'
$gaps | ForEach-Object { Write-Host "- $_" }
Write-Host "Next: $nextCommand"

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/TypedCascade/status'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'typed-cascade-harness-status.json'
    $mdPath = Join-Path $OutputDirectory 'typed-cascade-harness-status.md'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    @(
        '# Typed Cascade Validation Harness Status',
        '',
        "- Status: $status",
        "- Branch: $($result.branch)",
        "- HEAD: $($result.head)",
        '',
        '## Working',
        ($working | ForEach-Object { "- $_" }),
        '',
        '## Broken or blocked',
        $(if ($broken.Count -eq 0) { '- None at repository-contract level.' } else { $broken | ForEach-Object { "- $_" } }),
        '',
        '## Missing runtime proof',
        ($gaps | ForEach-Object { "- $_" }),
        '',
        '## Proof ceiling',
        $result.proofCeiling,
        '',
        '## Next command',
        '```powershell',
        $nextCommand,
        '```'
    ) | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host "JSON: $jsonPath"
    Write-Host "Report: $mdPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
