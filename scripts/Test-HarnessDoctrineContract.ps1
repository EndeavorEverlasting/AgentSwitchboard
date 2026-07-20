[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $RootPath $RelativePath
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$RelativePath" "file missing"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $path -Raw
}

function Test-ActionPrompt([string]$Text) {
    $claims = $Text -match '(?i)\b(install|set\s*up|build|execute|repair|configure|upgrade|deploy|merge|release)\b'
    if (-not $claims) { return $true }
    $mutation = $Text -match '(?i)\b(modify|create|write|update|commit|push|open a pull request|mutate)\b'
    $proof = $Text -match '(?i)\b(validate|validation|test|commit sha|pull request|\bPR\b)\b'
    $substitute = $Text -match '(?i)\b(acknowledgment only|summary only|plan only|advice only|handoff only)\b'
    return ($mutation -and $proof -and -not $substitute)
}

function Test-DeepSeekGate([string]$RateClass, [double]$Multiplier, [bool]$Verified) {
    return ($Verified -and $RateClass -in @('standard', 'discounted') -and $Multiplier -le 1.0)
}

function Test-DeviceProfileClaim([string]$ProfileName, [bool]$ClaimsDelivered) {
    if ($ProfileName -notin @('Windows Profile', 'Linux Profile', 'Android Profile')) { return $false }
    if ($ClaimsDelivered -and $ProfileName -in @('Linux Profile', 'Android Profile')) { return $false }
    return $true
}

function Check-DeviceProfilePolicy($ProfilePolicy, [string]$Prefix) {
    Check ($ProfilePolicy.namingConvention -eq '<Platform> Profile') "$Prefix/naming" "expected <Platform> Profile naming"
    Check ($ProfilePolicy.sharedLayer -eq 'platform-neutral') "$Prefix/shared-layer" "shared layer must remain platform-neutral"
    Check ([bool]$ProfilePolicy.platformSpecificWorkMustDeclareProfile) "$Prefix/declaration" "device-specific work need not declare a profile"
    Check ([bool]$ProfilePolicy.profileNameDoesNotProveImplementation) "$Prefix/proof-ceiling" "profile name is allowed to imply implementation"
    Check ([bool]$ProfilePolicy.reservedProfilesMayNotClaimDelivery) "$Prefix/reserved-proof" "reserved profiles may claim delivery"

    $profiles = @($ProfilePolicy.profiles)
    $windows = @($profiles | Where-Object { $_.id -eq 'windows' })
    $linux = @($profiles | Where-Object { $_.id -eq 'linux' })
    $android = @($profiles | Where-Object { $_.id -eq 'android' })
    Check ($windows.Count -eq 1 -and $windows[0].displayName -eq 'Windows Profile' -and $windows[0].status -eq 'current') "$Prefix/windows" "Windows Profile must be the current profile"
    Check ($linux.Count -eq 1 -and $linux[0].displayName -eq 'Linux Profile' -and $linux[0].status -eq 'reserved') "$Prefix/linux" "Linux Profile must remain reserved"
    Check ($android.Count -eq 1 -and $android[0].displayName -eq 'Android Profile' -and $android[0].status -eq 'reserved') "$Prefix/android" "Android Profile must remain reserved"
}

$policyText = Read-Required ".ai/harness/harness-doctrine.policy.json"
$templatePolicyText = Read-Required "templates/repository-agent-contract/.ai/harness/harness-doctrine.policy.json"
$doctrineText = Read-Required "docs/governance/harness-doctrine.md"
$templateDoctrineText = Read-Required "templates/repository-agent-contract/docs/governance/harness-doctrine.md"
$agentsText = Read-Required "AGENTS.md"
$templateAgentsText = Read-Required "templates/repository-agent-contract/AGENTS.md"
$skillText = Read-Required ".ai/skills/gnhf-prompt-compilation/SKILL.md"
$capabilitiesText = Read-Required "CAPABILITIES.md"
$triggersText = Read-Required "TRIGGERS.md"

try {
    $policy = $policyText | ConvertFrom-Json
    Check ($policy.schemaVersion -eq 1) "policy/schema" "expected schemaVersion 1"
    Check ($policy.policyId -eq 'agentswitchboard.harness-doctrine.v1') "policy/id" "unexpected ID"
    foreach ($field in @('repository','branchOrWorktree','prOrSprint','lane','ownedScope','forbiddenScope','expectedArtifacts','validationOrder')) {
        Check (@($policy.requiredSprintFields) -contains $field) "policy/field/$field" "missing sprint field"
    }
    Check ((@($policy.executableLoop) -join '|') -eq 'request|evidence-review|bounded-decision|repository-or-git-or-github-mutation|artifacts|validation|report|next-decision') "policy/loop" "execution loop changed"
    Check ([bool]$policy.actionCommitment.requiresTrackedMutation) "policy/action-mutation" "mutation not required"
    Check ([bool]$policy.actionCommitment.requiresValidationEvidence) "policy/action-validation" "validation not required"
    Check ([bool]$policy.actionCommitment.requiresCommitOrGitHubEvidence) "policy/action-proof" "commit or GitHub proof not required"
    Check-DeviceProfilePolicy $policy.deviceProfileTaxonomy "policy/device-profile"
    Check ($policy.gnhfTestOnly.maxWallClockSeconds -eq 30) "policy/test-wall" "wall clock must be 30"
    Check ($policy.gnhfTestOnly.maxIterationSeconds -eq 30) "policy/test-iteration" "iteration must be 30"
    Check ($policy.gnhfTestOnly.defaultMaxIterations -eq 1) "policy/test-count" "default test iterations must be 1"
    Check ([bool]$policy.gnhfTestOnly.requireProcessTreeTermination) "policy/test-kill-tree" "process-tree termination not required"
    Check ([bool]$policy.gnhfTestOnly.requireExplicitTimeoutEvidence) "policy/test-timeout-evidence" "timeout evidence not required"
    Check (@($policy.deepseekUsageGate.allowedRateClasses) -contains 'standard') "policy/deepseek-standard" "standard missing"
    Check (@($policy.deepseekUsageGate.allowedRateClasses) -contains 'discounted') "policy/deepseek-discounted" "discounted missing"
    Check (@($policy.deepseekUsageGate.blockedRateClasses) -contains 'double-usage') "policy/deepseek-double" "double-usage not blocked"
    Check (@($policy.deepseekUsageGate.blockedRateClasses) -contains 'unknown') "policy/deepseek-unknown" "unknown not blocked"
    Check ([double]$policy.deepseekUsageGate.maximumAllowedMultiplier -eq 1.0) "policy/deepseek-multiplier" "maximum multiplier must be 1.0"
    Check ($policy.deepseekUsageGate.defaultAction -eq 'deny') "policy/deepseek-deny" "gate is not fail-closed"
    Check (-not [bool]$policy.deepseekUsageGate.officialPricingReference.activeTimeOfDayWindowPublished) "policy/current-window" "active official window claimed"
    Check (-not [bool]$policy.deepseekUsageGate.officialPricingReference.historicalOffPeakWindowUtc.active) "policy/historical-window" "historical window active"
}
catch { [void]$failures.Add("policy/json`: $($_.Exception.Message)") }

try {
    $templatePolicy = $templatePolicyText | ConvertFrom-Json
    Check ($templatePolicy.policyId -eq 'agentswitchboard.harness-doctrine.v1') "template/id" "canonical policy not inherited"
    Check ($templatePolicy.localRulesMayWeaken -eq $false) "template/no-weakening" "template may weaken doctrine"
    Check ([bool]$templatePolicy.actionCommitment.requiresTrackedMutation) "template/action-mutation" "template weakens action commitment"
    Check ($templatePolicy.gnhfTestOnly.maxWallClockSeconds -eq 30) "template/test-wall" "template cap not 30"
    Check ([bool]$templatePolicy.gnhfTestOnly.requireExplicitTimeoutEvidence) "template/test-timeout-evidence" "template omits timeout evidence"
    Check ($templatePolicy.deepseekUsageGate.defaultAction -eq 'deny') "template/deepseek-deny" "template gate is not fail-closed"
    Check-DeviceProfilePolicy $templatePolicy.deviceProfileTaxonomy "template/device-profile"
}
catch { [void]$failures.Add("template/json`: $($_.Exception.Message)") }

foreach ($doc in @($doctrineText, $templateDoctrineText)) {
    foreach ($token in @(
        'request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision',
        'Action-commitment',
        'Device-profile taxonomy',
        'Windows Profile',
        'Linux Profile',
        'Android Profile',
        'platform-neutral',
        '30 seconds',
        'double-usage',
        'standard',
        'discounted'
    )) {
        Check ($doc.Contains($token)) "doctrine/$token" "doctrine token missing"
    }
}
foreach ($doc in @($agentsText, $templateAgentsText)) {
    foreach ($token in @('docs/governance/harness-doctrine.md','.ai/harness/harness-doctrine.policy.json','PR or sprint','validation order')) {
        Check ($doc.Contains($token)) "entrypoint/$token" "doctrine reference missing"
    }
}
foreach ($token in @('Test-only timing contract','30 seconds wall clock','30 seconds per iteration','DeepSeek rate-window contract','double-usage','standard','discounted','unknown or stale schedule state blocks DeepSeek')) {
    Check ($skillText.Contains($token)) "skill/$token" "GNHF doctrine token missing"
}
foreach ($token in @('harness.doctrine.validate','gnhf.test-timeout.enforce','deepseek.usage-window.evaluate','action.commitment.validate')) {
    Check ($capabilitiesText.Contains($token)) "capability/$token" "capability missing"
}
foreach ($token in @('action.claimed','gnhf.test-only','provider.deepseek-request')) {
    Check ($triggersText.Contains($token)) "trigger/$token" "trigger missing"
}

Check (-not (Test-ActionPrompt 'Install the harness. Return an acknowledgment only.')) "fixture/reject-ack" "acknowledgment-only action accepted"
Check (Test-ActionPrompt 'Install by modifying tracked files, validating tests, committing, pushing, and opening a pull request with the commit SHA.') "fixture/accept-action" "commit-required action rejected"
Check (Test-DeviceProfileClaim 'Windows Profile' $true) "fixture/windows-profile" "current Windows Profile claim rejected"
Check (Test-DeviceProfileClaim 'Linux Profile' $false) "fixture/linux-reserved" "reserved Linux Profile architecture rejected"
Check (-not (Test-DeviceProfileClaim 'Linux Profile' $true)) "fixture/linux-delivery-blocked" "reserved Linux Profile delivery claim accepted"
Check (-not (Test-DeviceProfileClaim 'Workstation Profile' $false)) "fixture/generic-profile-blocked" "generic profile alias accepted"
Check (Test-DeepSeekGate 'standard' 1.0 $true) "fixture/standard" "standard rejected"
Check (Test-DeepSeekGate 'discounted' 0.5 $true) "fixture/discounted" "discounted rejected"
Check (-not (Test-DeepSeekGate 'double-usage' 2.0 $true)) "fixture/double-blocked" "double usage accepted"
Check (-not (Test-DeepSeekGate 'standard' 1.0 $false)) "fixture/unknown-blocked" "unverified schedule accepted"

Write-Host 'HARNESS DOCTRINE CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
