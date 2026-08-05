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

function Test-ConsumerContract($Value) {
    return (
        $Value.profileId -eq 'windows' -and
        $Value.ownerRepository -eq 'EndeavorEverlasting/AgentSwitchboard' -and
        $Value.consumerRepository -eq 'EndeavorEverlasting/SysAdminSuite' -and
        $Value.operation -eq 'open-or-activate' -and
        [bool]$Value.delegateOnly -and
        [bool]$Value.shortcutTargetsCanonicalLauncher
    )
}

function Test-ProfileActionPrompt([string]$Text) {
    $claims = $Text -match '(?i)\b(install|build|configure|repair|certify|deploy)\b' -and $Text -match '(?i)\b(profile|launcher|wezterm)\b'
    if (-not $claims) { return $true }
    $required = @(
        'AgentSwitchboard',
        'Windows Profile',
        'open-or-activate',
        'SysAdminSuite',
        'tracked',
        'validate',
        'commit',
        'proof ceiling'
    )
    foreach ($token in $required) {
        if (-not $Text.Contains($token, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($Text -match '(?i)\b(plan only|summary only|architecture only|acknowledgment only|raw fallback|independent launch)\b') { return $false }
    return $true
}

$paths = @(
    'docs/governance/device-profile-launcher-contract.md',
    'docs/governance/environment-capability-contract.md',
    '.ai/harness/device-profile-launcher.policy.json',
    '.ai/harness/device-profile-registry.json',
    '.ai/harness/environment-capability.policy.json',
    '.ai/harness/schemas/device-profile-registry.schema.json',
    '.ai/harness/fixtures/device-profiles/valid-sysadminsuite-consumer.json',
    '.ai/harness/fixtures/device-profiles/invalid-competing-consumer.json',
    'docs/workstation/android-termux.md',
    'tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh',
    'Bootstrap-AgentSwitchboard-Termux.sh',
    'AGENTS.md',
    'docs/governance/harness-doctrine.md',
    '.ai/harness/harness-doctrine.policy.json',
    'CAPABILITIES.md',
    'TRIGGERS.md'
)
$text = @{}
foreach ($path in $paths) { $text[$path] = Read-Required $path }

try {
    $policy = $text['.ai/harness/device-profile-launcher.policy.json'] | ConvertFrom-Json
    Check ($policy.policyId -eq 'agentswitchboard.device-profile-launcher.v1') 'policy/id' 'unexpected policy ID'
    Check ($policy.environmentCapabilityPolicy -eq '.ai/harness/environment-capability.policy.json') 'policy/environment-policy' 'environment capability policy is not wired'
    Check ([bool]$policy.ownership.oneCanonicalLauncherPerProfile) 'policy/one-owner' 'one canonical launcher is not required'
    Check ($policy.ownership.canonicalOwnerRepository -eq 'EndeavorEverlasting/AgentSwitchboard') 'policy/owner' 'AgentSwitchboard is not canonical owner'
    Check ([bool]$policy.ownership.consumerIndependentLaunchLogicForbidden) 'policy/no-consumer-logic' 'consumer launch logic is allowed'
    Check ([bool]$policy.ownership.desktopShortcutsDelegateOnly) 'policy/shortcut-delegation' 'shortcuts are not delegate-only'
    Check ([bool]$policy.ownership.rawFallbackForbidden) 'policy/no-raw-fallback' 'raw fallback is allowed'
    foreach ($raw in @('wezterm', 'wezterm.exe', 'wezterm-gui.exe')) {
        Check (@($policy.ownership.rawExecutableEntryPointsForbidden) -contains $raw) "policy/raw/$raw" 'raw executable is not forbidden as an entrypoint'
    }
    Check ($policy.windowsProfile.displayName -eq 'Windows Profile') 'policy/windows-name' 'Windows Profile name is missing'
    Check ($policy.windowsProfile.canonicalOperation -eq 'open-or-activate') 'policy/open-or-activate' 'canonical operation differs'
    Check ($policy.windowsProfile.consumerCertifier -eq 'EndeavorEverlasting/SysAdminSuite') 'policy/sysadminsuite' 'SysAdminSuite is not consumer-certifier'
    Check ($policy.windowsProfile.status -eq 'contract-only') 'policy/windows-status' 'Windows doctrine status differs'

    $androidPolicy = $policy.androidProfile
    Check ($androidPolicy.displayName -eq 'Android Profile') 'policy/android-name' 'Android Profile name is missing'
    Check ($androidPolicy.status -eq 'terminal-client-implemented') 'policy/android-status' 'Android status overclaims or differs'
    Check ($androidPolicy.capabilityRole -eq 'terminal-client') 'policy/android-role' 'Android role differs'
    Check ($androidPolicy.terminalFrontend -eq 'termux') 'policy/android-frontend' 'Android frontend differs'
    Check ($androidPolicy.workspaceBackend -eq 'tmux') 'policy/android-workspace' 'Android workspace backend differs'
    Check ($androidPolicy.localTmuxRole -eq 'local-shell-only') 'policy/android-local-role' 'Android local tmux role differs'
    Check ($androidPolicy.localTmuxScope -eq 'device-local-only') 'policy/android-local-scope' 'Android local scope differs'
    Check ([bool]$androidPolicy.crossDeviceContinuityRequiresRemoteWorkspaceHost) 'policy/android-remote-host' 'remote workspace host is not required'
    Check ([bool]$androidPolicy.remoteShellClassificationRequired) 'policy/android-shell-classification' 'remote shell classification is not required'
    Check (@($androidPolicy.supportedRemoteHostProfiles) -contains 'posix-tmux') 'policy/android-posix-adapter' 'POSIX tmux adapter missing'
    Check ([bool]$androidPolicy.remotePreflightRequired) 'policy/android-preflight' 'remote preflight is not required'
    Check ($androidPolicy.nativeOrchestrationRuntime -eq 'unimplemented') 'policy/android-runtime' 'Android native orchestration runtime is overclaimed'
    Check ($androidPolicy.nativeAgentRuntime -eq 'unproved') 'policy/android-agent-runtime' 'Android native agent runtime is overclaimed'
    Check (-not [bool]$androidPolicy.fullRuntimeClaimAllowed) 'policy/android-no-full-runtime' 'Android full runtime claim is allowed'

    Check ([bool]$policy.idempotence.sameIdentityConverges) 'policy/idempotent' 'repeated calls do not converge'
    Check ([bool]$policy.idempotence.sameIdentityRequiresSameHostAndTmuxServer) 'policy/host-scoped-identity' 'same identity is not host/tmux scoped'
    Check ([bool]$policy.idempotence.duplicateLogicalWorkspaceForbidden) 'policy/no-duplicates' 'duplicate logical workspaces are allowed'
    Check (-not [bool]$policy.delegation.consumerMayFallbackToRawFrontend) 'policy/delegate-only' 'consumer may use raw frontend fallback'
    Check ([bool]$policy.profiles.android.configurationMayDiffer) 'policy/android-differs' 'Android profile may not differ'
    Check ($policy.profiles.android.roleCeiling -eq 'terminal-client') 'policy/android-role-ceiling' 'Android role ceiling differs'
}
catch { [void]$failures.Add("policy/json`: $($_.Exception.Message)") }

try {
    $environmentPolicy = $text['.ai/harness/environment-capability.policy.json'] | ConvertFrom-Json
    Check ($environmentPolicy.policyId -eq 'agentswitchboard.environment-capability.v1') 'environment-policy/id' 'environment policy ID differs'
    Check ($environmentPolicy.android.currentStatus -eq 'terminal-client-implemented') 'environment-policy/android-status' 'environment policy Android status differs'
    Check ($environmentPolicy.android.localTmuxScope -eq 'device-local-only') 'environment-policy/local-scope' 'environment policy local scope differs'
    Check (-not [bool]$environmentPolicy.invariants.sameTmuxNameAcrossHostsIsSameSession) 'environment-policy/tmux-host-scope' 'same tmux name across hosts is accepted'
}
catch { [void]$failures.Add("environment-policy/json`: $($_.Exception.Message)") }

try {
    $registry = $text['.ai/harness/device-profile-registry.json'] | ConvertFrom-Json
    Check ($registry.environmentCapabilityPolicy -eq '.ai/harness/environment-capability.policy.json') 'registry/environment-policy' 'environment capability policy is not wired'
    $ids = @($registry.profiles | ForEach-Object { [string]$_.profileId })
    Check (($ids | Sort-Object) -join ',' -eq 'android,linux,windows') 'registry/profiles' 'expected Windows, Linux, and Android profiles'
    Check (@($ids | Select-Object -Unique).Count -eq 3) 'registry/unique' 'profile IDs are duplicated'
    $windows = @($registry.profiles | Where-Object profileId -eq 'windows')[0]
    Check ($windows.displayName -eq 'Windows Profile') 'registry/windows-name' 'Windows Profile display name differs'
    Check ($windows.frontend -eq 'wezterm') 'registry/windows-frontend' 'Windows frontend is not WezTerm'
    Check ($windows.canonicalOperation -eq 'open-or-activate') 'registry/windows-operation' 'Windows operation differs'
    Check ($windows.ownerRepository -eq 'EndeavorEverlasting/AgentSwitchboard') 'registry/windows-owner' 'Windows owner differs'
    $consumer = @($windows.consumers | Where-Object repository -eq 'EndeavorEverlasting/SysAdminSuite')[0]
    Check ($consumer.role -eq 'consumer-certifier') 'registry/consumer-role' 'SysAdminSuite role differs'
    Check ([bool]$consumer.delegateOnly) 'registry/delegate-only' 'SysAdminSuite is not delegate-only'
    Check (-not [bool]$consumer.rawFallbackAllowed) 'registry/no-fallback' 'SysAdminSuite raw fallback is allowed'

    $android = @($registry.profiles | Where-Object profileId -eq 'android')[0]
    Check ($android.status -eq 'terminal-client-implemented') 'registry/android-status' 'Android status overclaims or differs'
    Check ($android.capabilityRole -eq 'terminal-client') 'registry/android-role' 'Android role differs'
    Check ($android.frontend -eq 'termux') 'registry/android-frontend' 'Android frontend differs'
    Check ($android.localTmuxRole -eq 'local-shell-only') 'registry/android-local-role' 'Android local role differs'
    Check ($android.localTmuxScope -eq 'device-local-only') 'registry/android-local-scope' 'Android local scope differs'
    Check ([bool]$android.crossDeviceContinuityRequiresRemoteWorkspaceHost) 'registry/android-remote-host' 'remote workspace host is not required'
    Check ([bool]$android.remoteShellClassificationRequired) 'registry/android-shell-classification' 'remote shell classification is not required'
    Check ($android.nativeOrchestrationRuntime -eq 'unimplemented') 'registry/android-runtime' 'Android native orchestration runtime is overclaimed'
    Check ($android.nativeAgentRuntime -eq 'unproved') 'registry/android-agent-runtime' 'Android native agent runtime is overclaimed'
    Check (-not [bool]$android.fullRuntimeClaimAllowed) 'registry/android-no-full-runtime' 'Android full runtime claim is allowed'
}
catch { [void]$failures.Add("registry/json`: $($_.Exception.Message)") }

try {
    $valid = $text['.ai/harness/fixtures/device-profiles/valid-sysadminsuite-consumer.json'] | ConvertFrom-Json
    $invalid = $text['.ai/harness/fixtures/device-profiles/invalid-competing-consumer.json'] | ConvertFrom-Json
    Check (Test-ConsumerContract $valid) 'fixture/valid-consumer' 'valid delegated consumer rejected'
    Check (-not (Test-ConsumerContract $invalid)) 'fixture/reject-competing-owner' 'competing consumer ownership accepted'
}
catch { [void]$failures.Add("fixtures/json`: $($_.Exception.Message)") }

$doctrine = $text['docs/governance/device-profile-launcher-contract.md']
foreach ($token in @(
    'Windows Profile',
    'Linux Profile',
    'Android Profile',
    'open-or-activate',
    'EndeavorEverlasting/AgentSwitchboard',
    'EndeavorEverlasting/SysAdminSuite',
    'wezterm-gui.exe',
    'contract-only',
    'terminal-client-implemented',
    'environment-capability-contract.md'
)) {
    Check ($doctrine.Contains($token)) "doctrine/$token" 'required doctrine token missing'
}

$androidDocs = $text['docs/workstation/android-termux.md']
foreach ($token in @('terminal-client-implemented','local-shell-only','device-local-only','remote workspace host','Execution hold','Proof ceiling')) {
    Check ($androidDocs.Contains($token)) "android-docs/$token" 'required Android boundary missing'
}
Check (-not $androidDocs.Contains('The shared continuity boundary is the named')) 'android-docs/reject-old-story' 'obsolete same-name continuity story remains'

$launcher = $text['tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh']
foreach ($token in @('role=terminal-client','continuity_scope=device-local-only','local-shell','--host-profile','posix-tmux','remote-preflight.env')) {
    Check ($launcher.Contains($token)) "android-launcher/$token" 'required Android launcher boundary missing'
}
Check (-not $launcher.Contains('StrictHostKeyChecking=no')) 'android-launcher/no-host-key-bypass' 'host-key verification bypass present'

$bootstrap = $text['Bootstrap-AgentSwitchboard-Termux.sh']
foreach ($token in @('Android terminal client installed','Full AgentSwitchboard runtime is not configured','proof=terminal-client-installed-command-probes')) {
    Check ($bootstrap.Contains($token)) "android-bootstrap/$token" 'required Android bootstrap boundary missing'
}

foreach ($surface in @('AGENTS.md', 'docs/governance/harness-doctrine.md')) {
    Check ($text[$surface].Contains('device-profile-launcher-contract.md')) "authority/$surface" 'device profile doctrine is not referenced'
}
Check ($text['AGENTS.md'].Contains('environment-capability-contract.md')) 'authority/environment-contract' 'environment capability doctrine is not referenced'
Check ($text['.ai/harness/harness-doctrine.policy.json'].Contains('device-profile-launcher.policy.json')) 'authority/policy' 'canonical policy is not wired'
Check ($text['CAPABILITIES.md'].Contains('profile.launcher.contract.validate')) 'authority/capability' 'validation capability is missing'
Check ($text['CAPABILITIES.md'].Contains('environment.capability.validate')) 'authority/environment-capability' 'environment validation capability is missing'
Check ($text['TRIGGERS.md'].Contains('profile.launcher-request')) 'authority/trigger' 'profile trigger is missing'
Check ($text['TRIGGERS.md'].Contains('environment.capability-request')) 'authority/environment-trigger' 'environment trigger is missing'

Check (-not (Test-ProfileActionPrompt 'Build a Windows Profile launcher. Return architecture only.')) 'fixture/reject-architecture-only' 'architecture-only action was accepted'
Check (-not (Test-ProfileActionPrompt 'Configure a WezTerm launcher with an independent launch fallback.')) 'fixture/reject-independent-launch' 'independent launch contract was accepted'
Check (Test-ProfileActionPrompt 'Build the Windows Profile in AgentSwitchboard with open-or-activate behavior; make SysAdminSuite delegate only; modify tracked files, validate fixtures, commit the result, and report the proof ceiling.') 'fixture/accept-committed-profile' 'valid committed action contract was rejected'

Write-Host 'DEVICE PROFILE LAUNCHER CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
