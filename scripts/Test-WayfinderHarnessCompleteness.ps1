[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    'tooling/harness/wayfinder/manifest.json',
    'tooling/harness/wayfinder/codebase-map.json',
    'tooling/harness/wayfinder/workflows/runtime-validation.workflow.json',
    'tooling/harness/wayfinder/artifact-registry.json',
    'tooling/harness/wayfinder/validator-registry.json',
    'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1',
    'tooling/harness/wayfinder/hooks/Invoke-WayfinderPreCommit.ps1',
    'tooling/harness/wayfinder/templates/operator-report.template.md',
    'tooling/harness/wayfinder/reports/harness-status.md',
    '.ai/skills/wayfinder/SKILL.md',
    '.ai/skills/wayfinder-runtime-binding/SKILL.md',
    'docs/harness/wayfinder.md',
    'scripts/Test-WayfinderPythonBinding.ps1',
    'scripts/Test-WayfinderHarness.ps1',
    'scripts/Test-WayfinderPublicPlanContribution.ps1',
    'tests/test_wayfinder_runtime_binding_contract.py',
    'tests/test_wayfinder_companion_source_integrity.py',
    'tests/test_wayfinder_harness.py',
    'tests/test_wayfinder_public_plan_contribution.py',
    '.github/workflows/wayfinder-public-plan-contribution.yml'
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RootPath $_) -PathType Leaf) })
if ($missing.Count -gt 0) { throw "Wayfinder harness completeness failure; missing tracked components:`n - $($missing -join "`n - ")" }

foreach ($jsonRelative in @(
    'tooling/harness/wayfinder/manifest.json',
    'tooling/harness/wayfinder/codebase-map.json',
    'tooling/harness/wayfinder/workflows/runtime-validation.workflow.json',
    'tooling/harness/wayfinder/artifact-registry.json',
    'tooling/harness/wayfinder/validator-registry.json'
)) { [void](Get-Content -LiteralPath (Join-Path $RootPath $jsonRelative) -Raw | ConvertFrom-Json) }

$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/wayfinder/manifest.json') -Raw | ConvertFrom-Json
$componentExpectations = @{
    codebaseMap = 'tooling/harness/wayfinder/codebase-map.json'
    workflowSpec = 'tooling/harness/wayfinder/workflows/runtime-validation.workflow.json'
    artifactRegistry = 'tooling/harness/wayfinder/artifact-registry.json'
    validatorRegistry = 'tooling/harness/wayfinder/validator-registry.json'
    optionalPreCommitHook = 'tooling/harness/wayfinder/hooks/Invoke-WayfinderPreCommit.ps1'
    operatorReportTemplate = 'tooling/harness/wayfinder/templates/operator-report.template.md'
    operatorStatusReport = 'tooling/harness/wayfinder/reports/harness-status.md'
}
foreach ($key in $componentExpectations.Keys) {
    if ($manifest.components.$key -ne $componentExpectations[$key]) { throw "Wayfinder manifest component mismatch: $key" }
}
if ($manifest.runtimeBinding.resolver -ne 'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1') { throw 'Wayfinder manifest does not own the runtime resolver.' }
if ($manifest.skills.runtimeBinding -ne '.ai/skills/wayfinder-runtime-binding/SKILL.md') { throw 'Wayfinder manifest does not own the runtime-binding skill.' }

[void][scriptblock]::Create((Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/wayfinder/hooks/Invoke-WayfinderPreCommit.ps1') -Raw))

. (Join-Path $RootPath 'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1')
$binding = Resolve-WayfinderPython -PythonPath $PythonPath -RootPath $RootPath
foreach ($test in @('tests/test_wayfinder_runtime_binding_contract.py', 'tests/test_wayfinder_companion_source_integrity.py')) {
    & $binding.Path (Join-Path $RootPath $test)
    if ($LASTEXITCODE -ne 0) { throw "Wayfinder completeness dependency failed: $test" }
}
& (Join-Path $RootPath 'scripts/Test-WayfinderPythonBinding.ps1') -RootPath $RootPath -PythonPath $binding.Path
if ($LASTEXITCODE -ne 0) { throw 'Wayfinder runtime-binding PowerShell contract failed.' }

Write-Host 'PASS: Wayfinder harness completeness' -ForegroundColor Green
Write-Host "Python: $($binding.Path)"
Write-Host 'Components: codebase map, workflow spec, artifact registry, validator registry, optional hook, scoped skills, operator report template/status report, owning validators, hosted workflow.'
exit 0
