[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $RootPath $RelativePath
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$RelativePath" 'file missing'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $path -Raw
}

function Test-ActionPrompt([string]$Text) {
    $claims = $Text -match '(?i)\b(install|set\s*up|build|execute|repair|configure|upgrade|deploy|merge|release|certify)\b'
    if (-not $claims) { return $true }
    $mutation = $Text -match '(?i)\b(modify|create|write|update|commit|push|open a pull request|mutate)\b'
    $proof = $Text -match '(?i)\b(validate|validation|test|commit sha|pull request|\bPR\b)\b'
    $substitute = $Text -match '(?i)\b(acknowledgment only|summary only|plan only|advice only|handoff only|architecture only)\b'
    return ($mutation -and $proof -and -not $substitute)
}

function Test-EventActionPrompt([string]$Text) {
    $claims = $Text -match '(?i)\b(event listener|event observer|trigger cascade|event cascade|runtime event path)\b'
    if (-not $claims) { return $true }
    foreach ($token in @('source','observer','handler','successor','sink','correlation','causation')) {
        if ($Text -notmatch "(?i)\b$token\b") { return $false }
    }
    return (Test-ActionPrompt $Text)
}

function Test-ProfileActionPrompt([string]$Text) {
    $claims = $Text -match '(?i)\b(profile|launcher|wezterm|open-or-activate|consumer certification)\b'
    if (-not $claims) { return $true }
    foreach ($token in @('AgentSwitchboard','Windows Profile','open-or-activate','SysAdminSuite','tracked','validate','commit','proof ceiling')) {
        if (-not $Text.Contains($token, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($Text -match '(?i)\b(raw fallback|independent launch|architecture only|plan only|summary only)\b') { return $false }
    return (Test-ActionPrompt $Text)
}

function Test-DeepSeekGate([string]$RateClass, [double]$Multiplier, [bool]$Verified) {
    return ($Verified -and $RateClass -in @('standard', 'discounted') -and $Multiplier -le 1.0)
}

$policyText = Read-Required '.ai/harness/harness-doctrine.policy.json'
$templatePolicyText = Read-Required 'templates/repository-agent-contract/.ai/harness/harness-doctrine.policy.json'
$runtimePolicyText = Read-Required '.ai/harness/runtime-event-contract.policy.json'
$templateRuntimePolicyText = Read-Required 'templates/repository-agent-contract/.ai/harness/runtime-event-contract.policy.json'
$profilePolicyText = Read-Required '.ai/harness/device-profile-launcher.policy.json'
$templateProfilePolicyText = Read-Required 'templates/repository-agent-contract/.ai/harness/device-profile-launcher.policy.json'
$doctrineText = Read-Required 'docs/governance/harness-doctrine.md'
$templateDoctrineText = Read-Required 'templates/repository-agent-contract/docs/governance/harness-doctrine.md'
$runtimeDoctrineText = Read-Required 'docs/governance/runtime-event-contract.md'
$templateRuntimeDoctrineText = Read-Required 'templates/repository-agent-contract/docs/governance/runtime-event-contract.md'
$profileDoctrineText = Read-Required 'docs/governance/device-profile-launcher-contract.md'
$templateProfileDoctrineText = Read-Required 'templates/repository-agent-contract/docs/governance/device-profile-launcher-contract.md'
$agentsText = Read-Required 'AGENTS.md'
$templateAgentsText = Read-Required 'templates/repository-agent-contract/AGENTS.md'
$skillText = Read-Required '.ai/skills/gnhf-prompt-compilation/SKILL.md'
$capabilitiesText = Read-Required 'CAPABILITIES.md'
$triggersText = Read-Required 'TRIGGERS.md'
$runtimeValidatorText = Read-Required 'scripts/Test-RuntimeEventContract.ps1'
$profileValidatorText = Read-Required 'scripts/Test-DeviceProfileLauncherContract.ps1'

try {
    $policy = $policyText | ConvertFrom-Json
    Check ($policy.schemaVersion -eq 1) 'policy/schema' 'expected schemaVersion 1'
    Check ($policy.policyId -eq 'agentswitchboard.harness-doctrine.v1') 'policy/id' 'unexpected ID'
    foreach ($field in @('repository','branchOrWorktree','prOrSprint','lane','ownedScope','forbiddenScope','expectedArtifacts','validationOrder')) {
        Check (@($policy.requiredSprintFields) -contains $field) "policy/field/$field" 'missing sprint field'
    }
    Check ((@($policy.executableLoop) -join '|') -eq 'request|evidence-review|bounded-decision|repository-or-git-or-github-mutation|artifacts|validation|report|next-decision') 'policy/loop' 'execution loop changed'
    Check ([bool]$policy.actionCommitment.requiresTrackedMutation) 'policy/action-mutation' 'mutation not required'
    Check ([bool]$policy.actionCommitment.requiresValidationEvidence) 'policy/action-validation' 'validation not required'
    Check ([bool]$policy.actionCommitment.requiresCommitOrGitHubEvidence) 'policy/action-proof' 'commit or GitHub proof not required'
    Check ($policy.gnhfTestOnly.maxWallClockSeconds -eq 30) 'policy/test-wall' 'wall clock must be 30'
    Check ($policy.gnhfTestOnly.maxIterationSeconds -eq 30) 'policy/test-iteration' 'iteration must be 30'
    Check ($policy.gnhfTestOnly.defaultMaxIterations -eq 1) 'policy/test-count' 'default test iterations must be 1'
    Check ([bool]$policy.gnhfTestOnly.requireProcessTreeTermination) 'policy/test-kill-tree' 'process-tree termination not required'
    Check (@($policy.deepseekUsageGate.allowedRateClasses) -contains 'standard') 'policy/deepseek-standard' 'standard missing'
    Check (@($policy.deepseekUsageGate.allowedRateClasses) -contains 'discounted') 'policy/deepseek-discounted' 'discounted missing'
    Check (@($policy.deepseekUsageGate.blockedRateClasses) -contains 'double-usage') 'policy/deepseek-double' 'double-usage not blocked'
    Check (@($policy.deepseekUsageGate.blockedRateClasses) -contains 'unknown') 'policy/deepseek-unknown' 'unknown not blocked'
    Check ($policy.deepseekUsageGate.defaultAction -eq 'deny') 'policy/deepseek-deny' 'gate is not fail-closed'
    Check ($policy.runtimeEventContract.validator -eq 'scripts/Test-RuntimeEventContract.ps1') 'policy/runtime-validator' 'runtime validator missing'
    Check ([bool]$policy.runtimeEventContract.correlationAndCausationRequired) 'policy/runtime-causality' 'causality not required'
    Check ($policy.deviceProfileLauncherContract.validator -eq 'scripts/Test-DeviceProfileLauncherContract.ps1') 'policy/profile-validator' 'profile validator missing'
    Check ($policy.deviceProfileLauncherContract.canonicalOwnerRepository -eq 'EndeavorEverlasting/AgentSwitchboard') 'policy/profile-owner' 'profile owner differs'
    Check ([bool]$policy.deviceProfileLauncherContract.oneCanonicalLauncherPerProfile) 'policy/profile-single-owner' 'single owner is not required'
    Check ([bool]$policy.deviceProfileLauncherContract.rawFrontendFallbackForbidden) 'policy/profile-no-fallback' 'raw fallback is permitted'
}
catch { [void]$failures.Add("policy/json`: $($_.Exception.Message)") }

try {
    $templatePolicy = $templatePolicyText | ConvertFrom-Json
    Check ($templatePolicy.policyId -eq 'agentswitchboard.harness-doctrine.v1') 'template/id' 'canonical policy not inherited'
    Check ($templatePolicy.localRulesMayWeaken -eq $false) 'template/no-weakening' 'template may weaken doctrine'
    Check ($templatePolicy.runtimeEventContract.validator -eq 'scripts/Test-RuntimeEventContract.ps1') 'template/runtime-validator' 'runtime validator not inherited'
    Check ($templatePolicy.deviceProfileLauncherContract.validator -eq 'scripts/Test-DeviceProfileLauncherContract.ps1') 'template/profile-validator' 'profile validator not inherited'
    Check ([bool]$templatePolicy.deviceProfileLauncherContract.consumerDelegateOnly) 'template/profile-delegate' 'consumer delegation not inherited'
}
catch { [void]$failures.Add("template/json`: $($_.Exception.Message)") }

try {
    $runtimePolicy = $runtimePolicyText | ConvertFrom-Json
    $templateRuntimePolicy = $templateRuntimePolicyText | ConvertFrom-Json
    Check ($runtimePolicy.policyId -eq 'agentswitchboard.runtime-event-contract.v1') 'runtime-policy/id' 'unexpected ID'
    Check ([bool]$runtimePolicy.envelope.immutableAfterEmission) 'runtime-policy/immutable' 'envelope may mutate'
    Check ([bool]$runtimePolicy.causality.successorCorrelationInherited) 'runtime-policy/correlation' 'successor correlation not inherited'
    Check ([bool]$runtimePolicy.composition.allRuntimeNodesMustBeRegistered) 'runtime-policy/nodes' 'nodes need not be registered'
    Check ($templateRuntimePolicy.policyId -eq $runtimePolicy.policyId) 'runtime-template/id' 'runtime policy not inherited'
    Check ($templateRuntimePolicy.localRulesMayWeaken -eq $false) 'runtime-template/no-weakening' 'runtime rules may be weakened'
}
catch { [void]$failures.Add("runtime-policy/json`: $($_.Exception.Message)") }

try {
    $profilePolicy = $profilePolicyText | ConvertFrom-Json
    $templateProfilePolicy = $templateProfilePolicyText | ConvertFrom-Json
    Check ($profilePolicy.policyId -eq 'agentswitchboard.device-profile-launcher.v1') 'profile-policy/id' 'unexpected ID'
    Check ($profilePolicy.windowsProfile.displayName -eq 'Windows Profile') 'profile-policy/windows-name' 'Windows Profile missing'
    Check ($profilePolicy.windowsProfile.canonicalOperation -eq 'open-or-activate') 'profile-policy/operation' 'operation differs'
    Check ($profilePolicy.windowsProfile.consumerCertifier -eq 'EndeavorEverlasting/SysAdminSuite') 'profile-policy/consumer' 'consumer-certifier differs'
    Check ([bool]$profilePolicy.ownership.oneCanonicalLauncherPerProfile) 'profile-policy/single-owner' 'single owner not required'
    Check ([bool]$profilePolicy.ownership.consumerIndependentLaunchLogicForbidden) 'profile-policy/no-consumer-logic' 'consumer launch logic allowed'
    Check ([bool]$profilePolicy.ownership.rawFallbackForbidden) 'profile-policy/no-fallback' 'raw fallback allowed'
    Check ([bool]$profilePolicy.profiles.android.configurationMayDiffer) 'profile-policy/android' 'Android may not differ'
    Check ($templateProfilePolicy.policyId -eq $profilePolicy.policyId) 'profile-template/id' 'profile policy not inherited'
    Check ($templateProfilePolicy.localRulesMayWeaken -eq $false) 'profile-template/no-weakening' 'profile rules may be weakened'
}
catch { [void]$failures.Add("profile-policy/json`: $($_.Exception.Message)") }

foreach ($doc in @($doctrineText, $templateDoctrineText)) {
    foreach ($token in @('request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision','Action-commitment','30 seconds','runtime-event-contract','Test-RuntimeEventContract.ps1','device-profile-launcher-contract','Test-DeviceProfileLauncherContract.ps1')) {
        Check ($doc.Contains($token)) "doctrine/$token" 'doctrine token missing'
    }
}
foreach ($doc in @($runtimeDoctrineText, $templateRuntimeDoctrineText)) {
    foreach ($token in @('event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink','Static topology does not prove runtime delivery','Test-RuntimeEventContract.ps1')) {
        Check ($doc.Contains($token)) "runtime-doctrine/$token" 'runtime doctrine token missing'
    }
}
foreach ($doc in @($profileDoctrineText, $templateProfileDoctrineText)) {
    foreach ($token in @('Windows Profile','open-or-activate','AgentSwitchboard','Android','Test-DeviceProfileLauncherContract.ps1')) {
        Check ($doc.Contains($token)) "profile-doctrine/$token" 'profile doctrine token missing'
    }
}
foreach ($doc in @($agentsText, $templateAgentsText)) {
    foreach ($token in @('docs/governance/harness-doctrine.md','PR or sprint','validation order','runtime-event-contract','Test-RuntimeEventContract.ps1','device-profile-launcher-contract','Test-DeviceProfileLauncherContract.ps1')) {
        Check ($doc.Contains($token)) "entrypoint/$token" 'doctrine reference missing'
    }
}
foreach ($token in @('Test-only timing contract','30 seconds wall clock','DeepSeek rate-window contract','unknown or stale schedule state blocks DeepSeek')) {
    Check ($skillText.Contains($token)) "skill/$token" 'GNHF doctrine token missing'
}
foreach ($token in @('harness.doctrine.validate','action.commitment.validate','runtime.event-contract.validate','runtime.event-cascade.observe','profile.launcher.contract.validate','profile.consumer.certify')) {
    Check ($capabilitiesText.Contains($token)) "capability/$token" 'capability missing'
}
foreach ($token in @('action.claimed','runtime.event-contract-change','runtime.event-cascade-request','profile.launcher-request','profile.consumer-certification-request')) {
    Check ($triggersText.Contains($token)) "trigger/$token" 'trigger missing'
}
Check ($runtimeValidatorText.Contains('RUNTIME EVENT CONTRACT')) 'runtime-validator/header' 'runtime validator header missing'
Check ($profileValidatorText.Contains('DEVICE PROFILE LAUNCHER CONTRACT')) 'profile-validator/header' 'profile validator header missing'

Check (-not (Test-ActionPrompt 'Install the harness. Return an acknowledgment only.')) 'fixture/reject-ack' 'acknowledgment-only action accepted'
Check (Test-ActionPrompt 'Install by modifying tracked files, validating tests, committing, pushing, and opening a pull request with the commit SHA.') 'fixture/accept-action' 'commit-required action rejected'
Check (-not (Test-EventActionPrompt 'Build an event listener and return an architecture plan only.')) 'fixture/reject-event-plan' 'architecture-only event action accepted'
Check (Test-EventActionPrompt 'Build the event listener by modifying source, observer, handler, successor, and sink contracts; preserve correlation and causation; validate, commit, push, and open a pull request.') 'fixture/accept-event-action' 'commit-required event action rejected'
Check (-not (Test-ProfileActionPrompt 'Build a Windows Profile launcher and return architecture only.')) 'fixture/reject-profile-plan' 'architecture-only profile action accepted'
Check (-not (Test-ProfileActionPrompt 'Configure a WezTerm launcher with independent launch logic and raw fallback.')) 'fixture/reject-profile-owner' 'competing launcher action accepted'
Check (Test-ProfileActionPrompt 'Build the Windows Profile in AgentSwitchboard with open-or-activate behavior; make SysAdminSuite delegate only; modify tracked files, validate fixtures, commit the result, and report the proof ceiling.') 'fixture/accept-profile-action' 'committed profile action rejected'
Check (Test-DeepSeekGate 'standard' 1.0 $true) 'fixture/standard' 'standard rejected'
Check (-not (Test-DeepSeekGate 'double-usage' 2.0 $true)) 'fixture/double-blocked' 'double usage accepted'
Check (-not (Test-DeepSeekGate 'standard' 1.0 $false)) 'fixture/unknown-blocked' 'unverified schedule accepted'

Write-Host 'HARNESS DOCTRINE CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
