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
    'tooling/agents/harness/admission/codebase-map.json',
    'tooling/agents/harness/admission/agent-admission.registry.json',
    'tooling/agents/harness/admission/artifact-registry.json',
    'tooling/agents/harness/admission/workflows/task-intake.workflow.json',
    'tooling/agents/harness/admission/workflows/admission-evaluation.workflow.json',
    'tooling/agents/harness/admission/workflows/route-selection.workflow.json',
    'tooling/agents/harness/admission/workflows/failure-handoff.workflow.json',
    'tooling/agents/harness/admission/schemas/agent-admission-harness.schema.json',
    'tooling/agents/harness/admission/fixtures/runtime-proof-discipline.cases.json',
    '.ai/skills/agent-admission-routing/SKILL.md',
    'tooling/agents/Get-AgentAdmissionHarnessStatus.ps1',
    'tooling/agents/hooks/Invoke-AgentAdmissionHarnessPreCommit.ps1',
    'tests/test_agent_admission_harness.py',
    'docs/harness/agent-admission-harness.md',
    '.github/workflows/agent-admission-harness.yml',
    'CODEBASE_MAP.md',
    'SKILLS.md',
    'TRIGGERS.md',
    'CAPABILITIES.md',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json'
)

$textByPath = @{}
foreach ($relativePath in $requiredFiles) {
    $textByPath[$relativePath] = Read-Tracked $relativePath
}

$jsonPaths = @(
    'tooling/agents/harness/admission/codebase-map.json',
    'tooling/agents/harness/admission/agent-admission.registry.json',
    'tooling/agents/harness/admission/artifact-registry.json',
    'tooling/agents/harness/admission/workflows/task-intake.workflow.json',
    'tooling/agents/harness/admission/workflows/admission-evaluation.workflow.json',
    'tooling/agents/harness/admission/workflows/route-selection.workflow.json',
    'tooling/agents/harness/admission/workflows/failure-handoff.workflow.json',
    'tooling/agents/harness/admission/schemas/agent-admission-harness.schema.json',
    'tooling/agents/harness/admission/fixtures/runtime-proof-discipline.cases.json',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json'
)
foreach ($relativePath in $jsonPaths) {
    try {
        $null = $textByPath[$relativePath] | ConvertFrom-Json
        Check $true "json/$relativePath" ''
    }
    catch {
        Check $false "json/$relativePath" $_.Exception.Message
    }
}

try {
    $registry = $textByPath['tooling/agents/harness/admission/agent-admission.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.agent-admission-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.defaultPolicy.unknownAgentEligibility -eq 'static-build-only') 'registry/unknown-static-only' 'unknown agents do not fail closed to static/build'
    Check ($registry.defaultPolicy.liveRuntimeFailClosed -eq $true) 'registry/live-fail-closed' 'live runtime is not fail closed'
    Check ($registry.defaultPolicy.silentProofDowngradeAllowed -eq $false) 'registry/no-silent-downgrade' 'proof downgrade is allowed'
    $laneIds = @($registry.executionLanes | ForEach-Object { [string]$_.laneId })
    foreach ($laneId in @('static-build','repository-runtime','live-runtime','adjudication-readonly')) {
        Check ($laneIds -contains $laneId) "registry/lane/$laneId" 'required execution lane is missing'
    }
    $liveLane = @($registry.executionLanes | Where-Object { $_.laneId -eq 'live-runtime' })[0]
    Check ($liveLane.minimumAdmission -eq 'runtime-proof-discipline-pass') 'registry/live-admission' 'live runtime does not require admission pass'
    Check ($liveLane.requiresFreshExecutionIdentity -eq $true) 'registry/live-identity' 'live runtime does not require fresh execution identity'
    Check ($registry.proofReducer.commandAckIsBehaviorProof -eq $false) 'registry/ack-not-behavior' 'command ACK is incorrectly behavior proof'
    Check ($registry.proofReducer.fixtureIsRuntimeProof -eq $false) 'registry/fixture-not-runtime' 'fixture is incorrectly runtime proof'
    Check ($registry.proofReducer.staleEvidenceMustNotCount -eq $true) 'registry/stale-rejected' 'stale evidence can promote proof'
    foreach ($classification in @('PASS_LIVE_RUNTIME','NOT_ATTEMPTED','LAUNCHER_BLOCKED','ACK_ONLY','STALE_EVIDENCE','BLOCKED_NO_ELIGIBLE_AGENT')) {
        Check (@($registry.proofReducer.terminalClassifications) -contains $classification) "registry/classification/$classification" 'required terminal classification missing'
    }
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $fixture = $textByPath['tooling/agents/harness/admission/fixtures/runtime-proof-discipline.cases.json'] | ConvertFrom-Json
    Check ($fixture.suiteId -eq 'runtime-proof-discipline/v1') 'fixture/suite' 'unexpected admission suite'
    Check (@($fixture.cases).Count -eq 5) 'fixture/case-count' 'runtime proof discipline suite must contain exactly five canonical cases'
    $expected = @{
        'live-runtime-pass' = 'PASS_LIVE_RUNTIME'
        'launch-not-requested' = 'NOT_ATTEMPTED'
        'launcher-hwnd-missing' = 'LAUNCHER_BLOCKED'
        'ack-without-behavior' = 'ACK_ONLY'
        'stale-behavior-evidence' = 'STALE_EVIDENCE'
    }
    foreach ($caseId in $expected.Keys) {
        $case = @($fixture.cases | Where-Object { $_.caseId -eq $caseId })
        Check ($case.Count -eq 1) "fixture/case/$caseId" 'canonical case is missing or duplicated'
        if ($case.Count -eq 1) {
            Check ($case[0].expectedClassification -eq $expected[$caseId]) "fixture/classification/$caseId" 'unexpected canonical classification'
        }
    }
    Check ($fixture.passingRule.maximumMisses -eq 0) 'fixture/zero-misses' 'live-runtime admission permits misses'
    Check ($fixture.passingRule.liveRuntimeEligibleOnPassOnly -eq $true) 'fixture/pass-only' 'live-runtime eligibility is not pass-only'
}
catch { [void]$failures.Add("fixture/semantic: $($_.Exception.Message)") }

$expectedWorkflows = @{
    'tooling/agents/harness/admission/workflows/task-intake.workflow.json' = 'agent-task-intake'
    'tooling/agents/harness/admission/workflows/admission-evaluation.workflow.json' = 'agent-admission-evaluation'
    'tooling/agents/harness/admission/workflows/route-selection.workflow.json' = 'agent-route-selection'
    'tooling/agents/harness/admission/workflows/failure-handoff.workflow.json' = 'agent-failure-handoff'
}
foreach ($path in $expectedWorkflows.Keys) {
    try {
        $workflow = $textByPath[$path] | ConvertFrom-Json
        Check ($workflow.schema -eq 'agentswitchboard.agent-admission-workflow.v1') "workflow/schema/$path" 'unexpected workflow schema'
        Check ($workflow.workflowId -eq $expectedWorkflows[$path]) "workflow/id/$path" 'unexpected workflow ID'
        Check (@($workflow.steps).Count -ge 5) "workflow/steps/$path" 'workflow is not operationally complete'
        Check (-not [string]::IsNullOrWhiteSpace([string]$workflow.proofCeiling)) "workflow/proof/$path" 'proof ceiling is missing'
    }
    catch { [void]$failures.Add("workflow/$path`: $($_.Exception.Message)") }
}

$routeText = $textByPath['tooling/agents/harness/admission/workflows/route-selection.workflow.json']
foreach ($token in @('capability presence alone does not establish admission','BLOCKED_NO_ELIGIBLE_AGENT','Requested routing is not execution proof')) {
    Check ($routeText -match [regex]::Escape($token)) "route/$token" 'route-selection invariant is missing'
}
$failureText = $textByPath['tooling/agents/harness/admission/workflows/failure-handoff.workflow.json']
foreach ($token in @('not-attempted','do not convert not-attempted into environment-blocked','strongest actually observed proof')) {
    Check ($failureText -match [regex]::Escape($token)) "handoff/$token" 'failure-handoff proof discipline is missing'
}

$skillText = $textByPath['.ai/skills/agent-admission-routing/SKILL.md']
foreach ($token in @('id: agent-admission-routing','version: 1.0.0','status: experimental','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate','BLOCKED_NO_ELIGIBLE_AGENT')) {
    Check ($skillText.Contains($token)) "skill/$token" 'skill contract token is missing'
}

foreach ($entry in @(
    @{ Path = 'CODEBASE_MAP.md'; Token = 'Agent admission and proof-discipline harness' },
    @{ Path = 'SKILLS.md'; Token = 'agent-admission-routing' },
    @{ Path = 'TRIGGERS.md'; Token = 'agent.admission-required' },
    @{ Path = 'CAPABILITIES.md'; Token = 'agent.admission.evaluate' }
)) {
    Check ($textByPath[$entry.Path].Contains($entry.Token)) "catalog/$($entry.Path)" "missing registration token $($entry.Token)"
}

try {
    $manifest = $textByPath['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($manifest.entrypoints.agentAdmissionCodebaseMap -eq 'tooling/agents/harness/admission/codebase-map.json') 'central/manifest/map' 'agent admission codebase map is not registered'
    Check ($manifest.entrypoints.agentAdmissionRegistry -eq 'tooling/agents/harness/admission/agent-admission.registry.json') 'central/manifest/registry' 'agent admission registry is not registered'
    Check ($manifest.entrypoints.agentAdmissionValidator -eq 'scripts/Test-AgentAdmissionHarness.ps1') 'central/manifest/validator' 'agent admission validator is not registered'
    Check ($manifest.entrypoints.agentAdmissionSkill -eq '.ai/skills/agent-admission-routing/SKILL.md') 'central/manifest/skill' 'agent admission skill is not registered'
    Check ($manifest.agentAdmissionHarness.status -eq 'contract-only') 'central/manifest/status' 'agent admission harness overclaims runtime enforcement'
    Check ($manifest.agentAdmissionHarness.runtimeEnforcementWired -eq $false) 'central/manifest/runtime-unwired' 'manifest falsely claims product runtime enforcement'
    Check ($manifest.agentAdmissionHarness.unknownAgentEligibility -eq 'static-build-only') 'central/manifest/unknown-policy' 'manifest does not fail unknown agents closed'
}
catch { [void]$failures.Add("central/manifest: $($_.Exception.Message)") }

try {
    $centralArtifacts = $textByPath['.ai/harness/artifact-registry.json'] | ConvertFrom-Json
    $artifactIds = @($centralArtifacts.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($artifactId in @('agent-admission-run-context','agent-admission-eval-result','agent-route-decision','agent-execution-identity','agent-proof-ledger','agent-admission-operator-report','agent-admission-final-handoff')) {
        Check ($artifactIds -contains $artifactId) "central/artifact/$artifactId" 'agent admission artifact is not centrally registered'
    }
    foreach ($artifact in @($centralArtifacts.artifacts | Where-Object { [string]$_.artifactId -like 'agent-*' })) {
        Check ($artifact.tracked -eq $false) "central/artifact-untracked/$($artifact.artifactId)" 'generated agent-admission evidence is tracked'
        Check ($artifact.sensitivity -eq 'local-operational') "central/artifact-sensitivity/$($artifact.artifactId)" 'unexpected sensitivity classification'
    }
}
catch { [void]$failures.Add("central/artifacts: $($_.Exception.Message)") }

$deployableText = @(
    $textByPath['tooling/agents/harness/admission/agent-admission.registry.json'],
    $textByPath['tooling/agents/harness/admission/workflows/admission-evaluation.workflow.json'],
    $textByPath['tooling/agents/harness/admission/workflows/route-selection.workflow.json'],
    $textByPath['.ai/skills/agent-admission-routing/SKILL.md'],
    $textByPath['docs/harness/agent-admission-harness.md']
) -join "`n"
foreach ($forbidden in @('agent brand is sufficient','fixture proves runtime','command presence proves eligibility','silent downgrade allowed')) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'unsafe admission shortcut is embedded in the harness'
}

Write-Host 'AGENT ADMISSION HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
