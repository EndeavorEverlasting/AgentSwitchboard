[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = 0
function Pass([string]$Name) { $script:passes++; Write-Host "[PASS] $Name" -ForegroundColor Green }
function Fail([string]$Name,[string]$Message) { [void]$script:failures.Add("${Name}: $Message"); Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red }
function Load-Json([string]$Relative) {
    $path = Join-Path $RootPath $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "exists/$Relative" 'missing'; return $null }
    try { $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; Pass "json/$Relative"; return $value }
    catch { Fail "json/$Relative" $_.Exception.Message; return $null }
}
$contractPath = 'tooling/harness/operational/canonical-path.contract.json'
$workflowPath = 'tooling/harness/operational/workflows/canonical-path-proof.workflow.json'
$schemaPath = 'tooling/harness/operational/schemas/canonical-path-proof.schema.json'
$skillPath = '.ai/skills/canonical-path-proof/SKILL.md'
$reportPath = 'docs/harness/canonical-path-current-state.md'
$machineOwner = 'tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json'
foreach ($relative in @($contractPath,$workflowPath,$schemaPath,$skillPath,$reportPath,$machineOwner)) {
    if (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) { Pass "exists/$relative" } else { Fail "exists/$relative" 'required canonical-path surface missing' }
    & git -C $RootPath ls-files --error-unmatch -- $relative *> $null
    if ($LASTEXITCODE -eq 0) { Pass "tracked/$relative" } else { Fail "tracked/$relative" 'required surface is not Git-tracked' }
}
$contract = Load-Json $contractPath
$workflow = Load-Json $workflowPath
$schema = Load-Json $schemaPath
if ($null -ne $contract) {
    if ($contract.contractId -eq 'agentswitchboard.canonical-path-seam.v1') { Pass 'contract/id' } else { Fail 'contract/id' 'unexpected id' }
    if ($contract.defaultPolicy.required -eq $true) { Pass 'contract/default-required' } else { Fail 'contract/default-required' 'local repository actions must default to path proof' }
    if ($contract.authority.machineProfileOwner -eq $machineOwner) { Pass 'contract/reuses-machine-profile-owner' } else { Fail 'contract/reuses-machine-profile-owner' 'must reuse existing owner' }
    $states = @($contract.proofStates | ForEach-Object { [string]$_.id })
    foreach ($id in @('remote-main-contains-sha','canonical-development-checkout-current','production-use-path-current','real-entrypoint-observes-it')) {
        if ($states -contains $id) { Pass "proof-state/$id" } else { Fail "proof-state/$id" 'missing' }
    }
    foreach ($property in @('secondMutableCloneAllowed','destructiveCleanupAllowed','silentStashAllowed','modelChosenDirectoryAllowed')) {
        if ($contract.pathSprawl.$property -eq $false) { Pass "path-sprawl/$property" } else { Fail "path-sprawl/$property" 'must remain false' }
    }
}
if ($null -ne $workflow) {
    $text = Get-Content -LiteralPath (Join-Path $RootPath $workflowPath) -Raw
    foreach ($token in @('git fetch --all --prune --tags','git pull --ff-only','remote-main-contains-sha','canonical-development-checkout-current','production-use-path-current','real-entrypoint-observes-it','approved isolated worktree')) {
        if ($text.Contains($token)) { Pass "workflow/$token" } else { Fail "workflow/$token" 'required path proof behavior missing' }
    }
}
$skill = Get-Content -LiteralPath (Join-Path $RootPath $skillPath) -Raw
foreach ($token in @('id: canonical-path-proof','status: canonical','## Trigger','## Procedure','## Known traps','git pull --ff-only','P92 Canonical Path Prompt')) {
    if ($skill.Contains($token)) { Pass "skill/$token" } else { Fail "skill/$token" 'required skill contract missing' }
}
& python (Join-Path $RootPath 'tests/test_canonical_path_harness.py')
if ($LASTEXITCODE -eq 0) { Pass 'python/canonical-path-contract' } else { Fail 'python/canonical-path-contract' "exit=$LASTEXITCODE" }
Write-Host ''
Write-Host ("CANONICAL PATH HARNESS: {0} passed / {1} failed" -f $passes, $failures.Count) -ForegroundColor Cyan
if ($failures.Count -gt 0) { exit 1 }
exit 0
