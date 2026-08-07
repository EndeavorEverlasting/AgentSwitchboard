[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $FailureMessage") }
}

function Read-Json {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch {
        [void]$failures.Add("json/$RelativePath`: $($_.Exception.Message)")
        return $null
    }
}

$requiredFiles = @(
    'tooling/profiles/windows/harness/agent-fleet-readiness/codebase-map.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/artifact-registry.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/pick-up-agent-task.workflow.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/bootstrap-or-list-readiness.workflow.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/handle-readiness-failure.workflow.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/handoff-agent-task.workflow.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/fixtures/readiness-state-cases.json',
    'tooling/profiles/windows/harness/agent-fleet-readiness/operator-report.template.md',
    'tooling/profiles/windows/harness/agent-fleet-readiness/hooks/pre-push.ps1',
    '.ai/skills/agent-fleet-readiness/SKILL.md',
    'docs/harness/agent-fleet-readiness.md',
    'scripts/Test-AgentFleetReadinessHarnessCompleteness.ps1',
    'tests/test_agent_fleet_readiness_harness.py',
    '.github/workflows/agent-fleet-readiness-harness.yml'
)

foreach ($relativePath in $requiredFiles) {
    Add-Check `
        -Condition (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) `
        -Name "required/$relativePath" `
        -FailureMessage 'required harness component is missing'
}

$map = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/codebase-map.json'
$registry = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/artifact-registry.json'
$fixtures = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/fixtures/readiness-state-cases.json'
$bootstrapWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/bootstrap-or-list-readiness.workflow.json'
$pickupWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/pick-up-agent-task.workflow.json'
$failureWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/handle-readiness-failure.workflow.json'
$handoffWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/handoff-agent-task.workflow.json'

if ($null -ne $map) {
    Add-Check ($map.harnessId -eq 'agentswitchboard.agent-fleet-readiness-harness.v1') 'map/harness-id' 'unexpected harness ID'
    foreach ($property in @('rootSetupLauncher','setupImplementation','rootOperatorLauncher','startupReport','artifactRegistry','pickupWorkflow','readinessWorkflow','failureWorkflow','handoffWorkflow','operatorReport','prePushHook','skill','validator','pythonContract','ci','operatorGuide')) {
        Add-Check ($null -ne $map.entrypoints.PSObject.Properties[$property]) "map/entrypoint/$property" 'entrypoint is missing'
    }
    foreach ($trap in @('post-setup launcher','tmux/WezTerm/WSL','state.json','Adapter READY','non-AgentSwitchboard','clean-checkout','Push is off by default')) {
        Add-Check (([string]($map.knownTraps -join "`n")).Contains($trap)) "map/trap/$trap" 'known trap is missing'
    }
}

if ($null -ne $registry) {
    $artifactIds = @($registry.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($id in @('fleet-state','installed-operator-launcher','setup-summary','setup-transcript','startup-readiness-json','startup-readiness-markdown','provider-route-proof')) {
        Add-Check ($artifactIds -contains $id) "registry/artifact/$id" 'artifact registration is missing'
    }
    $states = @($registry.stateGates | ForEach-Object { [string]$_.state })
    foreach ($state in @('not-bootstrapped','partial-or-inconsistent','installed-unclassified','adapter-ready')) {
        Add-Check ($states -contains $state) "registry/state/$state" 'state gate is missing'
    }
}

if ($null -ne $fixtures) {
    $cases = @{}
    foreach ($case in $fixtures.cases) { $cases[[string]$case.name] = $case }
    Add-Check ($cases.ContainsKey('not-bootstrapped')) 'fixture/not-bootstrapped' 'missing case'
    Add-Check ($cases['not-bootstrapped'].expectedNextAction -eq 'bootstrap-or-repair') 'fixture/not-bootstrapped/action' 'must bootstrap before readiness listing'
    Add-Check ($cases['partial-state-only'].expectedClassification -eq 'partial-or-inconsistent') 'fixture/partial-state-only' 'state-only installation must be inconsistent'
    Add-Check ($cases['partial-launcher-only'].expectedClassification -eq 'partial-or-inconsistent') 'fixture/partial-launcher-only' 'launcher-only installation must be inconsistent'
    Add-Check ($cases['installed-unclassified'].expectedNextAction -eq 'list-readiness') 'fixture/installed/action' 'installed state must list readiness before launch'
    Add-Check ($cases['adapter-ready-provider-unproved'].mustNotClaim -eq 'hosted-response-proven') 'fixture/provider-proof-ceiling' 'provider proof ceiling fixture is missing'
}

foreach ($workflow in @($bootstrapWorkflow,$pickupWorkflow,$failureWorkflow,$handoffWorkflow)) {
    Add-Check ($null -ne $workflow -and -not [string]::IsNullOrWhiteSpace([string]$workflow.workflowId)) 'workflow/id' 'workflow failed to parse or has no ID'
    Add-Check ($null -ne $workflow -and -not [string]::IsNullOrWhiteSpace([string]$workflow.proofCeiling)) 'workflow/proof-ceiling' 'workflow has no proof ceiling'
}

foreach ($productPath in @(
    'Setup-AgentSwitchboard.cmd',
    'AgentSwitchboard.cmd',
    'tooling/gnhf/Setup-AgentSwitchboard.ps1',
    'tooling/gnhf/Start-AgentSwitchboard.ps1',
    'tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1',
    'tooling/gnhf/Test-GnhfFleetContracts.ps1'
)) {
    Add-Check (Test-Path -LiteralPath (Join-Path $RootPath $productPath) -PathType Leaf) "product-reference/$productPath" 'referenced existing product surface is missing'
}

$skillText = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/agent-fleet-readiness/SKILL.md') -Raw
foreach ($token in @(
    'id: agent-fleet-readiness',
    'version: 1.0.0',
    'status: experimental',
    'Separate terminal readiness from fleet readiness',
    'Inspect both installed-state surfaces before post-setup commands',
    'not-bootstrapped',
    'partial-or-inconsistent',
    'List readiness before selecting an agent',
    'Keep provider proof separate',
    'Require an explicit task prompt outside AgentSwitchboard',
    'No post-setup launcher command before installed-state classification'
)) {
    Add-Check ($skillText.Contains($token)) "skill/$token" 'required readiness rule is missing'
}

$rootMapText = Get-Content -LiteralPath (Join-Path $RootPath 'CODEBASE_MAP.md') -Raw
foreach ($token in @(
    '## Agent fleet readiness harness',
    'tooling/profiles/windows/harness/agent-fleet-readiness/codebase-map.json',
    '.ai/skills/agent-fleet-readiness/SKILL.md',
    'not-bootstrapped',
    'partial-or-inconsistent',
    'Canonical `SKILLS.md`/`TRIGGERS.md` routing remains unchanged'
)) {
    Add-Check ($rootMapText.Contains($token)) "root-map/$token" 'root codebase map does not expose the scoped harness or P00 boundary'
}

$guideText = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/agent-fleet-readiness.md') -Raw
foreach ($token in @('two separate operator floors','Canonical state gate','not-bootstrapped','partial-or-inconsistent','Do not collapse these into a generic “agent failed.”')) {
    Add-Check ($guideText.Contains($token)) "guide/$token" 'operator guide regression coverage is missing'
}

Write-Host 'AGENT FLEET READINESS HARNESS' -ForegroundColor Cyan
foreach ($pass in $passes) { Write-Host "[PASS] $pass" -ForegroundColor Green }
foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
Write-Host ''
Write-Host ("Components: {0}/{0}" -f $requiredFiles.Count)
Write-Host ("Checks: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
Write-Host 'Agent Fleet Readiness Harness: PASS (14/14 components)' -ForegroundColor Green
exit 0
