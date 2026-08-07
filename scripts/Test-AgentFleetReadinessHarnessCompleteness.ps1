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
    'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/core-autoconfig-defer-hermes.workflow.json',
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
    Add-Check -Condition (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) -Name "required/$relativePath" -FailureMessage 'required harness component is missing'
}

$map = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/codebase-map.json'
$registry = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/artifact-registry.json'
$fixtures = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/fixtures/readiness-state-cases.json'
$bootstrapWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/bootstrap-or-list-readiness.workflow.json'
$coreWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/core-autoconfig-defer-hermes.workflow.json'
$pickupWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/pick-up-agent-task.workflow.json'
$failureWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/handle-readiness-failure.workflow.json'
$handoffWorkflow = Read-Json 'tooling/profiles/windows/harness/agent-fleet-readiness/workflows/handoff-agent-task.workflow.json'

if ($null -ne $map) {
    Add-Check ($map.harnessId -eq 'agentswitchboard.agent-fleet-readiness-harness.v1') 'map/harness-id' 'unexpected harness ID'
    foreach ($property in @('rootSetupLauncher','setupImplementation','rootOperatorLauncher','startupReport','artifactRegistry','pickupWorkflow','readinessWorkflow','coreAutoconfigWorkflow','failureWorkflow','handoffWorkflow','operatorReport','prePushHook','skill','validator','pythonContract','ci','operatorGuide')) {
        Add-Check ($null -ne $map.entrypoints.PSObject.Properties[$property]) "map/entrypoint/$property" 'entrypoint is missing'
    }
    $traps = [string]($map.knownTraps -join "`n")
    foreach ($trap in @('post-setup launcher','tmux/WezTerm/WSL','state.json','stale hard-coded repository paths','irm are not CMD commands','Hermes is optional for core autoconfig','-SkipHermesInstall','Adapter READY','clean-checkout','Push is off by default')) {
        Add-Check ($traps.Contains($trap)) "map/trap/$trap" 'known trap is missing'
    }
}

if ($null -ne $registry) {
    $artifactIds = @($registry.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($id in @('fleet-state','installed-operator-launcher','setup-summary','setup-transcript','startup-readiness-json','startup-readiness-markdown','provider-route-proof')) {
        Add-Check ($artifactIds -contains $id) "registry/artifact/$id" 'artifact registration is missing'
    }
    $states = @($registry.stateGates | ForEach-Object { [string]$_.state })
    foreach ($state in @('not-bootstrapped','partial-or-inconsistent','core-ready-hermes-deferred','installed-unclassified','adapter-ready')) {
        Add-Check ($states -contains $state) "registry/state/$state" 'state gate is missing'
    }
    $hermesOptional = @($registry.optionalDependencies | Where-Object { $_.name -eq 'Hermes' }) | Select-Object -First 1
    Add-Check ($null -ne $hermesOptional) 'registry/hermes-optional' 'Hermes optional dependency contract is missing'
    if ($null -ne $hermesOptional) {
        Add-Check ($hermesOptional.setupFlag -eq '-SkipHermesInstall') 'registry/hermes-skip-flag' 'Hermes deferral must use the existing product flag'
        Add-Check ($hermesOptional.deferredLabel -eq 'TBD') 'registry/hermes-tbd-label' 'Hermes deferred label must be TBD'
    }
}

if ($null -ne $fixtures) {
    $cases = @{}
    foreach ($case in $fixtures.cases) { $cases[[string]$case.name] = $case }
    Add-Check ($cases['not-bootstrapped'].expectedNextAction -eq 'bootstrap-or-repair') 'fixture/not-bootstrapped/action' 'must bootstrap before readiness listing'
    Add-Check ($cases['partial-state-only'].expectedClassification -eq 'partial-or-inconsistent') 'fixture/partial-state-only' 'state-only installation must be inconsistent'
    Add-Check ($cases['installed-unclassified'].expectedNextAction -eq 'list-readiness') 'fixture/installed/action' 'installed state must list readiness before launch'
    Add-Check ($cases['adapter-ready-provider-unproved'].mustNotClaim -eq 'hosted-response-proven') 'fixture/provider-proof-ceiling' 'provider proof ceiling fixture is missing'
    Add-Check ($cases['stale-repository-path'].expectedClassification -eq 'repository-path-invalid') 'fixture/stale-path' 'stale repo path classification is missing'
    Add-Check ($cases['powershell-command-pasted-into-cmd'].expectedClassification -eq 'shell-command-mismatch') 'fixture/shell-mismatch' 'shell mismatch classification is missing'
    Add-Check ($cases['hermes-unavailable-core-autoconfig'].expectedClassification -eq 'core-ready-hermes-deferred') 'fixture/hermes-deferred' 'Hermes deferred core-ready state is missing'
    Add-Check ($cases['hermes-unavailable-core-autoconfig'].hermesLabel -eq 'TBD') 'fixture/hermes-tbd' 'Hermes deferred fixture must label Hermes TBD'
}

foreach ($workflow in @($bootstrapWorkflow,$coreWorkflow,$pickupWorkflow,$failureWorkflow,$handoffWorkflow)) {
    Add-Check ($null -ne $workflow -and -not [string]::IsNullOrWhiteSpace([string]$workflow.workflowId)) 'workflow/id' 'workflow failed to parse or has no ID'
    Add-Check ($null -ne $workflow -and -not [string]::IsNullOrWhiteSpace([string]$workflow.proofCeiling)) 'workflow/proof-ceiling' 'workflow has no proof ceiling'
}

$setupPath = Join-Path $RootPath 'tooling/gnhf/Setup-AgentSwitchboard.ps1'
$setupText = Get-Content -LiteralPath $setupPath -Raw
Add-Check ($setupText.Contains('[switch]$SkipHermesInstall')) 'product-contract/skip-hermes-parameter' 'existing setup no longer exposes SkipHermesInstall'
Add-Check ($setupText.Contains('Core fleet setup will continue and Hermes will be recorded as BLOCKED')) 'product-contract/graceful-hermes-failure' 'existing setup no longer guarantees non-blocking Hermes failure'

foreach ($productPath in @('Setup-AgentSwitchboard.cmd','AgentSwitchboard.cmd','tooling/gnhf/Setup-AgentSwitchboard.ps1','tooling/gnhf/Start-AgentSwitchboard.ps1','tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1','tooling/gnhf/Test-GnhfFleetContracts.ps1','tooling/gnhf/Test-HermesSetupContracts.ps1')) {
    Add-Check (Test-Path -LiteralPath (Join-Path $RootPath $productPath) -PathType Leaf) "product-reference/$productPath" 'referenced existing product surface is missing'
}

$skillText = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/agent-fleet-readiness/SKILL.md') -Raw
foreach ($token in @('id: agent-fleet-readiness','version: 1.1.0','status: experimental','Resolve the repository root before Git or setup','irm is a PowerShell alias, not a CMD command','Prefer non-blocking core autoconfig when Hermes is not the priority','-SkipHermesInstall','TBD/deferred','No manual Hermes installation or repeated Hermes retry')) {
    Add-Check ($skillText.Contains($token)) "skill/$token" 'required readiness rule is missing'
}

$guideText = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/agent-fleet-readiness.md') -Raw
foreach ($token in @('two separate operator floors','stale hard-coded repository path','PowerShell-only `irm ... | iex`','Hermes is also explicitly **optional for core autoconfig**','-SkipHermesInstall','core-ready-hermes-deferred','Do not collapse these into a generic “agent failed.”')) {
    Add-Check ($guideText.Contains($token)) "guide/$token" 'operator guide regression coverage is missing'
}

Write-Host 'AGENT FLEET READINESS HARNESS' -ForegroundColor Cyan
foreach ($pass in $passes) { Write-Host "[PASS] $pass" -ForegroundColor Green }
foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
Write-Host ''
Write-Host ("Components: {0}/{0}" -f $requiredFiles.Count)
Write-Host ("Checks: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
Write-Host ("Agent Fleet Readiness Harness: PASS ({0}/{0} components)" -f $requiredFiles.Count) -ForegroundColor Green
exit 0
