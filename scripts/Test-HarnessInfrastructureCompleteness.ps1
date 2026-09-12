[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$registryPath = Join-Path $RootPath 'tooling/harness/operational/harness-components.registry.json'
$failures = [System.Collections.Generic.List[string]]::new()
$passes = 0
function Pass([string]$Name) { $script:passes++; Write-Host "[PASS] $Name" -ForegroundColor Green }
function Fail([string]$Name,[string]$Message) { [void]$script:failures.Add("${Name}: $Message"); Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red }
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { Write-Error 'Harness component registry is missing.'; exit 1 }
try { $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json } catch { Write-Error "Harness component registry JSON is invalid: $($_.Exception.Message)"; exit 1 }
if ($registry.schemaVersion -eq 1) { Pass 'registry/schema-version' } else { Fail 'registry/schema-version' 'expected schemaVersion 1' }
if ($registry.registryId -eq 'agentswitchboard.harness-components.v1') { Pass 'registry/id' } else { Fail 'registry/id' 'unexpected registry id' }
foreach ($property in @('governanceMutationOwned','productMutationOwned','destructiveGitAllowed','implicitHookInstallationAllowed','remoteMergeImpliesLocalAvailability','modelChosenCanonicalPathAllowed','secondMutableCloneAllowed')) {
    if ($registry.safety.$property -eq $false) { Pass "safety/$property" } else { Fail "safety/$property" 'must remain false' }
}
$allPaths = [System.Collections.Generic.List[string]]::new()
foreach ($group in $registry.components.PSObject.Properties) { foreach ($relative in @($group.Value)) { if (-not $allPaths.Contains([string]$relative)) { [void]$allPaths.Add([string]$relative) } } }
foreach ($relative in $allPaths) {
    $full = Join-Path $RootPath $relative
    if (Test-Path -LiteralPath $full -PathType Leaf) { Pass "exists/$relative" } else { Fail "exists/$relative" 'required component file is missing'; continue }
    & git -C $RootPath ls-files --error-unmatch -- $relative *> $null
    if ($LASTEXITCODE -eq 0) { Pass "tracked/$relative" } else { Fail "tracked/$relative" 'required component is not tracked by Git' }
}
foreach ($jsonRelative in @(
    'tooling/harness/operational/harness-components.registry.json',
    'tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json',
    'tooling/harness/operational/workflows/canonical-path-proof.workflow.json',
    'tooling/harness/operational/schemas/canonical-path-proof.schema.json',
    'tooling/harness/operational/canonical-path.contract.json',
    'tooling/harness/operational/manifest.json',
    'tooling/harness/operational/codebase-map.json',
    'tooling/harness/operational/workflow-registry.json',
    'tooling/harness/operational/artifact-registry.json',
    'tooling/harness/operational/validator-registry.json',
    'tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json'
)) {
    try { $null = Get-Content -LiteralPath (Join-Path $RootPath $jsonRelative) -Raw | ConvertFrom-Json; Pass "json/$jsonRelative" } catch { Fail "json/$jsonRelative" $_.Exception.Message }
}
$adoption = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json') -Raw
foreach ($token in @('canonical-path.contract.json','git fetch --all --prune --tags','refs/remotes/origin/HEAD','git merge-base --is-ancestor','git pull --ff-only','approved isolated worktree','remote-main-contains-sha','canonical-development-checkout-current','production-use-path-current','real-entrypoint-observes-it')) { if ($adoption.Contains($token)) { Pass "local-adoption/$token" } else { Fail "local-adoption/$token" 'required safe-adoption contract missing' } }
foreach ($forbidden in @('reset --hard','git clean')) { if ($adoption.Contains($forbidden)) { Pass "local-adoption/forbidden-$forbidden" } else { Fail "local-adoption/forbidden-$forbidden" 'workflow must explicitly forbid destructive cleanup' } }
$skillText = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/post-integration-local-adoption/SKILL.md') -Raw
foreach ($token in @('id: post-integration-local-adoption','## Trigger','## Procedure','## Known trap','canonical-path.contract.json','git pull --ff-only','approved isolated worktree')) { if ($skillText.Contains($token)) { Pass "skill/$token" } else { Fail "skill/$token" 'required scoped skill contract missing' } }
$contract = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/canonical-path.contract.json') -Raw | ConvertFrom-Json
if ($contract.defaultPolicy.required -eq $true) { Pass 'canonical-path/default-required' } else { Fail 'canonical-path/default-required' 'must default required for local repository-backed actions' }
if ($contract.authority.machineProfileOwner -eq 'tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json') { Pass 'canonical-path/reuses-profile-owner' } else { Fail 'canonical-path/reuses-profile-owner' 'must reuse existing machine-profile registry' }
if ($contract.authority.deepRepairOwner -eq 'P92 Canonical Path Prompt') { Pass 'canonical-path/p92-seam' } else { Fail 'canonical-path/p92-seam' 'deep repair owner missing' }
$states = @($contract.proofStates | ForEach-Object { [string]$_.id })
foreach ($state in @('remote-main-contains-sha','canonical-development-checkout-current','production-use-path-current','real-entrypoint-observes-it')) { if ($states -contains $state) { Pass "canonical-path/state/$state" } else { Fail "canonical-path/state/$state" 'proof state missing' } }
$registryWorkflow = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/workflow-registry.json') -Raw | ConvertFrom-Json
$canonicalPrecondition = @($registryWorkflow.actionPreconditions | Where-Object { $_.preconditionId -eq 'canonical-path-proof' })
if ($canonicalPrecondition.Count -eq 1 -and $canonicalPrecondition[0].defaultRequired -eq $true) { Pass 'canonical-path/workflow-precondition' } else { Fail 'canonical-path/workflow-precondition' 'default action precondition missing' }
$taskIntake = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/workflows/task-intake.workflow.json') -Raw
foreach ($token in @('canonical-path-proof','provider-only remote read','development checkout','production/use path','temporary worktree root','real operator entrypoint')) { if ($taskIntake.Contains($token)) { Pass "canonical-path/task-intake/$token" } else { Fail "canonical-path/task-intake/$token" 'task intake path seam missing' } }
$harnessText = Get-Content -LiteralPath (Join-Path $RootPath 'HARNESS.md') -Raw
foreach ($token in @('harness-components.registry.json','Test-HarnessInfrastructureCompleteness.ps1','operational-harness-routing/SKILL.md','post-integration-local-adoption.workflow.json','post-integration-local-adoption/SKILL.md','workflow-registry.json')) { if ($harnessText.Contains($token)) { Pass "harness-discovery/$token" } else { Fail "harness-discovery/$token" '50k entry does not expose harness infrastructure route' } }
$reportText = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/operational-harness-current-state.md') -Raw
foreach ($heading in @('## Working','## Broken / blocked','## Missing / unproven','## Operator path','## Proof ceiling')) { if ($reportText.Contains($heading)) { Pass "operator-report/$heading" } else { Fail "operator-report/$heading" 'required human state section missing' } }
$canonicalReport = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/canonical-path-current-state.md') -Raw
foreach ($heading in @('## Working','## Broken / blocked','## Missing / unproven','## Operator path','## Proof ceiling')) { if ($canonicalReport.Contains($heading)) { Pass "canonical-report/$heading" } else { Fail "canonical-report/$heading" 'required canonical path human state section missing' } }
& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-CanonicalPathHarness.ps1') -RootPath $RootPath
if ($LASTEXITCODE -eq 0) { Pass 'canonical-path/owning-validator' } else { Fail 'canonical-path/owning-validator' "exit=$LASTEXITCODE" }
Write-Host ''
Write-Host ("HARNESS INFRASTRUCTURE COMPLETENESS: {0} passed / {1} failed" -f $passes, $failures.Count) -ForegroundColor Cyan
if ($failures.Count -gt 0) { exit 1 }
exit 0
