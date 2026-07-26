[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("${Name}: $Message") }
}

function Read-Tracked([string]$RelativePath) {
    $path = Join-Path $RootPath $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Check $exists "file/$RelativePath" 'required file is missing'
    if (-not $exists) { return $null }
    $null = & git -C $RootPath ls-files --error-unmatch -- $RelativePath 2>$null
    Check ($LASTEXITCODE -eq 0) "tracked/$RelativePath" 'required file is not tracked'
    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
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
    'tooling/cascade/Get-TypedCascadeHarnessStatus.ps1',
    'tooling/cascade/hooks/Invoke-TypedCascadeHarnessPreCommit.ps1',
    'tests/test_typed_cascade_harness.py',
    'docs/harness/typed-cascade-validation.md',
    '.github/workflows/typed-cascade-harness.yml',
    'Test-TypedCascadeHarness.cmd',
    'CODEBASE_MAP.md',
    'SKILLS.md',
    'TRIGGERS.md',
    'CAPABILITIES.md',
    '.ai/harness/runtime-event-contract.policy.json',
    '.ai/harness/runtime-event-topology.json'
)

$textByPath = @{}
foreach ($relativePath in $requiredFiles) {
    $textByPath[$relativePath] = Read-Tracked $relativePath
}

$jsonPaths = @($requiredFiles | Where-Object { $_.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase) })
foreach ($relativePath in $jsonPaths) {
    if ($null -eq $textByPath[$relativePath]) { continue }
    try {
        $null = $textByPath[$relativePath] | ConvertFrom-Json
        Check $true "json/$relativePath" ''
    }
    catch { Check $false "json/$relativePath" $_.Exception.Message }
}

try {
    $registry = $textByPath['tooling/cascade/harness/typed-gates/typed-cascade.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.typed-cascade-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.executionDiscipline.agentMayMutateExternalState -eq $false) 'registry/pure-agent' 'agent is allowed to mutate external state'
    Check ($registry.executionDiscipline.deterministicBoundaryOwnsMutation -eq $true) 'registry/deterministic-boundary' 'mutation owner is not deterministic boundary'
    Check ($registry.executionDiscipline.preGateRequiredBeforeExecution -eq $true) 'registry/pre-required' 'pre gate is not mandatory'
    Check ($registry.executionDiscipline.postGateRequiredBeforeSuccessorEmission -eq $true) 'registry/post-required' 'post gate is not mandatory'
    Check ($registry.executionDiscipline.silentGateBypassAllowed -eq $false) 'registry/no-bypass' 'silent gate bypass is allowed'
    $gateIds = @($registry.gates | ForEach-Object { [string]$_.gateId })
    foreach ($gateId in @('pre-action', 'post-action')) { Check ($gateIds -contains $gateId) "registry/gate/$gateId" 'required gate missing' }
    foreach ($classification in @('PASS_SYNTHETIC_CASCADE','REJECT_INPUT_SCHEMA','REJECT_RESULT_CARDINALITY','REJECT_RESULT_DISJOINTNESS','REJECT_RESULT_ENUMERATION','REJECT_RESULT_DOMAIN_RANGE','REJECT_RESULT_REFERENCE','REJECT_STALE_RESULT','REJECT_CAUSALITY','BLOCKED_ACTION_NOT_OBSERVED')) {
        Check (@($registry.cascade.terminalClassifications) -contains $classification) "registry/classification/$classification" 'required terminal classification missing'
    }
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $ontology = $textByPath['tooling/cascade/harness/typed-gates/ontology.registry.json'] | ConvertFrom-Json
    $types = @($ontology.ruleTypes | ForEach-Object { [string]$_.type })
    foreach ($ruleType in @('functional-property','disjoint-classes','one-of','domain-range','required-reference')) {
        Check ($types -contains $ruleType) "ontology/type/$ruleType" 'required ontology rule type missing'
    }
    $ruleIds = @($ontology.cascadeRules | ForEach-Object { [string]$_.ruleId })
    foreach ($ruleId in @('one-terminal-classification-per-action','success-and-rejection-are-disjoint','proof-level-is-closed','successor-caused-by-runtime-event','result-action-reference-must-exist','causation-reference-must-exist')) {
        Check ($ruleIds -contains $ruleId) "ontology/rule/$ruleId" 'required cascade ontology rule missing'
    }
}
catch { [void]$failures.Add("ontology/semantic: $($_.Exception.Message)") }

$expectedWorkflows = @{
    'tooling/cascade/harness/typed-gates/workflows/task-intake.workflow.json' = 'typed-cascade-task-intake'
    'tooling/cascade/harness/typed-gates/workflows/pre-action-validation.workflow.json' = 'typed-cascade-pre-action-validation'
    'tooling/cascade/harness/typed-gates/workflows/post-action-validation.workflow.json' = 'typed-cascade-post-action-validation'
    'tooling/cascade/harness/typed-gates/workflows/cascade-emission.workflow.json' = 'typed-cascade-emission'
    'tooling/cascade/harness/typed-gates/workflows/failure-handoff.workflow.json' = 'typed-cascade-failure-handoff'
}
foreach ($path in $expectedWorkflows.Keys) {
    try {
        $workflow = $textByPath[$path] | ConvertFrom-Json
        Check ($workflow.schema -eq 'agentswitchboard.typed-cascade-workflow.v1') "workflow/schema/$path" 'unexpected workflow schema'
        Check ($workflow.workflowId -eq $expectedWorkflows[$path]) "workflow/id/$path" 'unexpected workflow ID'
        Check (@($workflow.steps).Count -ge 5) "workflow/steps/$path" 'workflow is not operationally complete'
        Check (-not [string]::IsNullOrWhiteSpace([string]$workflow.proofCeiling)) "workflow/proof/$path" 'proof ceiling is missing'
    }
    catch { [void]$failures.Add("workflow/$path`: $($_.Exception.Message)") }
}

try {
    $fixtures = $textByPath['tooling/cascade/harness/typed-gates/fixtures/typed-cascade.cases.json'] | ConvertFrom-Json
    Check ($fixtures.suiteId -eq 'typed-cascade-gates/v1') 'fixture/suite' 'unexpected fixture suite'
    Check (@($fixtures.cases).Count -ge 10) 'fixture/count' 'fixture suite is too small to exercise both gates and ontology rules'
    $expectedCases = @{
        'valid-complete-cascade' = 'PASS_SYNTHETIC_CASCADE'
        'input-wrong-type' = 'REJECT_INPUT_SCHEMA'
        'input-authority-missing' = 'REJECT_INPUT_AUTHORITY'
        'action-not-observed' = 'BLOCKED_ACTION_NOT_OBSERVED'
        'stale-result' = 'REJECT_STALE_RESULT'
        'duplicate-terminal-classification' = 'REJECT_RESULT_CARDINALITY'
        'disjoint-success-and-rejection' = 'REJECT_RESULT_DISJOINTNESS'
        'made-up-proof-level' = 'REJECT_RESULT_ENUMERATION'
        'wrong-causation-domain-range' = 'REJECT_RESULT_DOMAIN_RANGE'
        'missing-action-reference' = 'REJECT_RESULT_REFERENCE'
        'broken-successor-causality' = 'REJECT_CAUSALITY'
    }
    foreach ($caseId in $expectedCases.Keys) {
        $case = @($fixtures.cases | Where-Object { $_.caseId -eq $caseId })
        Check ($case.Count -eq 1) "fixture/case/$caseId" 'canonical case missing or duplicated'
        if ($case.Count -eq 1) { Check ($case[0].expectedClassification -eq $expectedCases[$caseId]) "fixture/classification/$caseId" 'unexpected expected classification' }
    }
}
catch { [void]$failures.Add("fixture/semantic: $($_.Exception.Message)") }

$skillText = $textByPath['.ai/skills/typed-cascade-validation/SKILL.md']
foreach ($token in @('id: typed-cascade-validation','version: 1.0.0','status: experimental','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) {
    Check ($skillText.Contains($token)) "skill/$token" 'skill contract token missing'
}

foreach ($entry in @(
    @{ Path = 'CODEBASE_MAP.md'; Token = 'Typed cascade validation harness' },
    @{ Path = 'SKILLS.md'; Token = 'typed-cascade-validation' },
    @{ Path = 'TRIGGERS.md'; Token = 'cascade.typed-validation-request' },
    @{ Path = 'CAPABILITIES.md'; Token = 'cascade.pre-validate' }
)) {
    Check ($textByPath[$entry.Path].Contains($entry.Token)) "catalog/$($entry.Path)" "missing registration token $($entry.Token)"
}

try {
    $runtimePolicy = $textByPath['.ai/harness/runtime-event-contract.policy.json'] | ConvertFrom-Json
    Check ($runtimePolicy.envelope.immutableAfterEmission -eq $true) 'runtime/immutable' 'runtime event policy does not require immutable envelopes'
    Check ($runtimePolicy.causality.successorCorrelationInherited -eq $true) 'runtime/correlation' 'runtime event policy does not require inherited correlation'
    Check ($runtimePolicy.causality.successorCausationEqualsParentEventId -eq $true) 'runtime/causation' 'runtime event policy does not require immediate-parent causation'
}
catch { [void]$failures.Add("runtime-policy/semantic: $($_.Exception.Message)") }

$deployableText = @(
    $textByPath['tooling/cascade/harness/typed-gates/typed-cascade.registry.json'],
    $textByPath['tooling/cascade/harness/typed-gates/ontology.registry.json'],
    $textByPath['.ai/skills/typed-cascade-validation/SKILL.md'],
    $textByPath['docs/harness/typed-cascade-validation.md']
) -join "`n"
foreach ($forbidden in @('agent may bypass gate','schema pass proves runtime','ontology file proves OWL runtime','stale result may promote','success successor after rejection')) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'unsafe shortcut embedded in deployable harness contract'
}

Write-Host 'TYPED CASCADE HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
