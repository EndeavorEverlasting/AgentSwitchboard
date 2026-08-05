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

$paths = @(
    'docs/governance/environment-capability-contract.md',
    '.ai/harness/environment-capability.policy.json',
    'tooling/profiles/harness/environment-capability/environment-capability.registry.json',
    'tooling/profiles/harness/environment-capability/schemas/environment-capability.schema.json',
    'tooling/profiles/harness/environment-capability/codebase-map.json',
    'tooling/profiles/harness/environment-capability/artifact-registry.json',
    'tooling/profiles/harness/environment-capability/workflows/environment-intake.workflow.json',
    'tooling/profiles/harness/environment-capability/workflows/topology-selection.workflow.json',
    'tooling/profiles/harness/environment-capability/workflows/certification.workflow.json',
    'tooling/profiles/harness/environment-capability/fixtures/valid-windows-control-plane.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/valid-android-terminal-client.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/invalid-android-full-runtime-claim.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/invalid-local-tmux-continuity-claim.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/invalid-unclassified-ssh-target.fixture.json',
    '.ai/skills/environment-capability-routing/SKILL.md',
    'docs/harness/environment-capability-harness.md',
    'tests/test_environment_capability_harness.py',
    '.ai/harness/device-profile-registry.json',
    '.ai/harness/device-profile-launcher.policy.json',
    'Bootstrap-AgentSwitchboard-Termux.sh',
    'tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh',
    'AGENTS.md',
    'SKILLS.md',
    'CAPABILITIES.md',
    'TRIGGERS.md',
    'CODEBASE_MAP.md',
    '.ai/agent-contract.json',
    '.ai/harness/manifest.json'
)
$text = @{}
foreach ($path in $paths) { $text[$path] = Read-Required $path }

try {
    $policy = $text['.ai/harness/environment-capability.policy.json'] | ConvertFrom-Json
    Check ($policy.policyId -eq 'agentswitchboard.environment-capability.v1') 'policy/id' 'unexpected policy ID'
    Check (($policy.layers -join ',') -eq 'frontend,transport,workspaceHost,orchestrationRuntime,agentRuntime') 'policy/layers' 'five layers differ'
    Check (@($policy.roles) -contains 'terminal-client') 'policy/role-terminal-client' 'terminal-client role missing'
    Check (@($policy.roles) -contains 'local-shell-only') 'policy/role-local-shell' 'local-shell-only role missing'
    Check (@($policy.forbiddenStatuses) -contains 'repository-implemented') 'policy/forbid-ambiguous-status' 'repository-implemented is not forbidden'
    Check ([bool]$policy.invariants.terminalClientIsNotRuntimeHost) 'policy/client-not-runtime' 'terminal client may become runtime host'
    Check ([bool]$policy.invariants.repositoryPresenceIsNotRuntimeReadiness) 'policy/repo-not-runtime' 'repository presence may prove runtime'
    Check (-not [bool]$policy.invariants.sameTmuxNameAcrossHostsIsSameSession) 'policy/tmux-host-scope' 'same name across hosts is accepted'
    Check (-not [bool]$policy.invariants.phoneLocalTmuxIsCrossDeviceContinuity) 'policy/local-tmux-boundary' 'phone-local tmux is treated as cross-device'
    Check (-not [bool]$policy.invariants.androidIsGenericLinux) 'policy/android-not-linux-assumption' 'Android is treated as generic Linux'
    Check (-not [bool]$policy.autoConfiguration.universalInstallerAllowed) 'policy/no-universal-installer' 'universal installer is allowed'
    Check ($policy.android.currentStatus -eq 'terminal-client-implemented') 'policy/android-status' 'Android status overclaims implementation'
    Check ($policy.android.currentRole -eq 'terminal-client') 'policy/android-role' 'Android role differs'
    Check ($policy.android.localTmuxScope -eq 'device-local-only') 'policy/android-local-scope' 'Android local tmux scope differs'
    Check (-not [bool]$policy.android.fullRuntimeClaimAllowed) 'policy/android-no-full-runtime' 'Android full runtime claim is allowed'
}
catch { [void]$failures.Add("policy/json`: $($_.Exception.Message)") }

try {
    $registry = $text['tooling/profiles/harness/environment-capability/environment-capability.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.environment-capability-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.canonicalOwner -eq 'EndeavorEverlasting/AgentSwitchboard') 'registry/owner' 'canonical owner differs'
    $ids = @($registry.topologies | ForEach-Object { [string]$_.topologyId })
    foreach ($id in @(
        'windows-wezterm-wsl-control-plane',
        'android-termux-local-shell',
        'android-termux-ssh-posix-workspace-client',
        'android-native-agentswitchboard-full-runtime'
    )) {
        Check ($ids -contains $id) "registry/topology/$id" 'topology missing'
    }
    Check (@($ids | Select-Object -Unique).Count -eq $ids.Count) 'registry/unique' 'topology IDs are duplicated'
    $local = @($registry.topologies | Where-Object topologyId -eq 'android-termux-local-shell')[0]
    $remote = @($registry.topologies | Where-Object topologyId -eq 'android-termux-ssh-posix-workspace-client')[0]
    $native = @($registry.topologies | Where-Object topologyId -eq 'android-native-agentswitchboard-full-runtime')[0]
    Check ($local.implementedRoleCeiling -eq 'local-shell-only') 'registry/local-role-ceiling' 'local Android role ceiling differs'
    Check ($local.workspaceHost.continuityScope -eq 'device-local-only') 'registry/local-continuity' 'local continuity scope differs'
    Check ($remote.implementedRoleCeiling -eq 'terminal-client') 'registry/remote-role-ceiling' 'remote Android role ceiling differs'
    Check ([bool]$remote.workspaceHost.preflightRequired) 'registry/remote-preflight' 'remote preflight is not required'
    Check ($native.implementationStatus -eq 'reserved') 'registry/native-status' 'native Android runtime is not reserved'
    Check ($native.implementedRoleCeiling -eq 'unsupported') 'registry/native-role' 'native Android runtime is not unsupported'
}
catch { [void]$failures.Add("registry/json`: $($_.Exception.Message)") }

foreach ($jsonPath in @(
    'tooling/profiles/harness/environment-capability/schemas/environment-capability.schema.json',
    'tooling/profiles/harness/environment-capability/codebase-map.json',
    'tooling/profiles/harness/environment-capability/artifact-registry.json',
    'tooling/profiles/harness/environment-capability/workflows/environment-intake.workflow.json',
    'tooling/profiles/harness/environment-capability/workflows/topology-selection.workflow.json',
    'tooling/profiles/harness/environment-capability/workflows/certification.workflow.json',
    'tooling/profiles/harness/environment-capability/fixtures/valid-windows-control-plane.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/valid-android-terminal-client.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/invalid-android-full-runtime-claim.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/invalid-local-tmux-continuity-claim.fixture.json',
    'tooling/profiles/harness/environment-capability/fixtures/invalid-unclassified-ssh-target.fixture.json'
)) {
    try {
        [void]($text[$jsonPath] | ConvertFrom-Json)
        [void]$passes.Add("json/$jsonPath")
    }
    catch { [void]$failures.Add("json/$jsonPath`: $($_.Exception.Message)") }
}

try {
    $deviceRegistry = $text['.ai/harness/device-profile-registry.json'] | ConvertFrom-Json
    $android = @($deviceRegistry.profiles | Where-Object profileId -eq 'android')[0]
    Check ($android.status -eq 'terminal-client-implemented') 'device-registry/android-status' 'Android status is not terminal-client-implemented'
    Check ($android.capabilityRole -eq 'terminal-client') 'device-registry/android-role' 'Android role differs'
    Check ($android.localTmuxScope -eq 'device-local-only') 'device-registry/android-local-scope' 'Android local tmux scope differs'
    Check ($android.nativeOrchestrationRuntime -eq 'unimplemented') 'device-registry/android-runtime' 'Android orchestration runtime is overclaimed'
    Check ([bool]$android.crossDeviceContinuityRequiresRemoteWorkspaceHost) 'device-registry/android-remote-host' 'remote workspace host is not required'
}
catch { [void]$failures.Add("device-registry/json`: $($_.Exception.Message)") }

try {
    $devicePolicy = $text['.ai/harness/device-profile-launcher.policy.json'] | ConvertFrom-Json
    $androidPolicy = $devicePolicy.androidProfile
    Check ($androidPolicy.status -eq 'terminal-client-implemented') 'device-policy/android-status' 'Android policy status overclaims implementation'
    Check ($androidPolicy.capabilityRole -eq 'terminal-client') 'device-policy/android-role' 'Android policy role differs'
    Check ($androidPolicy.localTmuxScope -eq 'device-local-only') 'device-policy/android-local-scope' 'Android local tmux scope differs'
    Check ($androidPolicy.nativeOrchestrationRuntime -eq 'unimplemented') 'device-policy/android-runtime' 'Android native runtime is overclaimed'
    Check (-not [bool]$androidPolicy.fullRuntimeClaimAllowed) 'device-policy/android-no-full-runtime' 'Android full runtime claim is allowed'
}
catch { [void]$failures.Add("device-policy/json`: $($_.Exception.Message)") }

$launcher = $text['tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh']
foreach ($token in @('role=terminal-client','continuity_scope=device-local-only','local-shell','--host-profile','posix-tmux','remote-preflight.env')) {
    Check ($launcher.Contains($token)) "launcher/$token" 'required capability boundary token missing'
}
foreach ($forbidden in @('StrictHostKeyChecking=no','role=full-runtime-host','continuity_scope=cross-device')) {
    Check (-not $launcher.Contains($forbidden)) "launcher/reject/$forbidden" 'forbidden launcher claim or bypass present'
}

$bootstrap = $text['Bootstrap-AgentSwitchboard-Termux.sh']
foreach ($token in @('Android terminal client installed','Full AgentSwitchboard runtime is not configured','proof=terminal-client-installed-command-probes')) {
    Check ($bootstrap.Contains($token)) "bootstrap/$token" 'bootstrap capability ceiling is missing'
}

$doctrine = $text['docs/governance/environment-capability-contract.md']
foreach ($token in @('Five-layer topology','tmux identity is host-scoped','repository-implemented','Auto-configuration rule','Remote-host preflight')) {
    Check ($doctrine.Contains($token)) "doctrine/$token" 'required doctrine token missing'
}

$skill = $text['.ai/skills/environment-capability-routing/SKILL.md']
foreach ($section in @('## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) {
    Check ($skill.Contains($section)) "skill/$section" 'required skill section missing'
}

foreach ($surface in @('AGENTS.md','SKILLS.md','CAPABILITIES.md','TRIGGERS.md','CODEBASE_MAP.md')) {
    Check ($text[$surface].Contains('environment-capability')) "registration/$surface" 'environment capability harness is not registered'
}

try {
    $contract = $text['.ai/agent-contract.json'] | ConvertFrom-Json
    Check (@($contract.canonicalSkills) -contains 'environment-capability-routing') 'contract/skill' 'canonical skill is not registered'
    Check ($contract.entrypoints.environmentCapabilities -eq 'docs/governance/environment-capability-contract.md') 'contract/entrypoint' 'environment entrypoint missing'
}
catch { [void]$failures.Add("contract/json`: $($_.Exception.Message)") }

try {
    $manifest = $text['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($manifest.entrypoints.environmentCapabilityPolicy -eq '.ai/harness/environment-capability.policy.json') 'manifest/policy' 'policy entrypoint missing'
    Check ($manifest.environmentCapabilities.androidRoleCeiling -eq 'terminal-client') 'manifest/android-role' 'manifest Android role ceiling differs'
}
catch { [void]$failures.Add("manifest/json`: $($_.Exception.Message)") }

Write-Host 'ENVIRONMENT CAPABILITY HARNESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
