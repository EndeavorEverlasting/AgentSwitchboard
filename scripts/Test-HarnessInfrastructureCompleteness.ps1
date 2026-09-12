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
foreach ($property in @('governanceMutationOwned','productMutationOwned','destructiveGitAllowed','implicitHookInstallationAllowed','remoteMergeImpliesLocalAvailability')) {
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
foreach ($jsonRelative in @('tooling/harness/operational/harness-components.registry.json','tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json','tooling/harness/operational/manifest.json','tooling/harness/operational/codebase-map.json','tooling/harness/operational/workflow-registry.json','tooling/harness/operational/artifact-registry.json','tooling/harness/operational/validator-registry.json')) {
    try { $null = Get-Content -LiteralPath (Join-Path $RootPath $jsonRelative) -Raw | ConvertFrom-Json; Pass "json/$jsonRelative" } catch { Fail "json/$jsonRelative" $_.Exception.Message }
}
$adoption = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json') -Raw
foreach ($token in @('git fetch --all --prune --tags','refs/remotes/origin/HEAD','git merge-base --is-ancestor','git pull --ff-only','isolated worktree','git ls-files --error-unmatch','remote merge')) { if ($adoption.Contains($token)) { Pass "local-adoption/$token" } else { Fail "local-adoption/$token" 'required safe-adoption contract missing' } }
foreach ($forbidden in @('reset --hard','git clean')) { if ($adoption.Contains($forbidden)) { Pass "local-adoption/forbidden-$forbidden" } else { Fail "local-adoption/forbidden-$forbidden" 'workflow must explicitly forbid destructive cleanup' } }
$skillText = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/post-integration-local-adoption/SKILL.md') -Raw
foreach ($token in @('id: post-integration-local-adoption','## Trigger','## Procedure','## Known trap','git pull --ff-only')) { if ($skillText.Contains($token)) { Pass "skill/$token" } else { Fail "skill/$token" 'required scoped skill contract missing' } }
$harnessText = Get-Content -LiteralPath (Join-Path $RootPath 'HARNESS.md') -Raw
foreach ($token in @('harness-components.registry.json','Test-HarnessInfrastructureCompleteness.ps1','operational-harness-routing/SKILL.md','post-integration-local-adoption.workflow.json','post-integration-local-adoption/SKILL.md')) { if ($harnessText.Contains($token)) { Pass "harness-discovery/$token" } else { Fail "harness-discovery/$token" '50k entry does not expose harness infrastructure route' } }
$reportText = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/operational-harness-current-state.md') -Raw
foreach ($heading in @('## Working','## Broken / blocked','## Missing / unproven','## Operator path','## Proof ceiling')) { if ($reportText.Contains($heading)) { Pass "operator-report/$heading" } else { Fail "operator-report/$heading" 'required human state section missing' } }
Write-Host ''
Write-Host ("HARNESS INFRASTRUCTURE COMPLETENESS: {0} passed / {1} failed" -f $passes, $failures.Count) -ForegroundColor Cyan
if ($failures.Count -gt 0) { exit 1 }
exit 0
