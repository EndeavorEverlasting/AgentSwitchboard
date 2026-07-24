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
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/upstream-verification.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    '.pi/settings.json',
    'tooling/pi/Install-AgentSwitchboardPi.ps1',
    'tooling/pi/Start-AgentSwitchboardPi.ps1',
    'Install-AgentSwitchboardPi.cmd',
    'Start-AgentSwitchboardPi.cmd',
    'tooling/pi/Get-PiHarnessStatus.ps1',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'tests/test_pi_harness_contracts.py',
    'tests/test_pi_runtime_support.py',
    'docs/harness/pi-operational-harness.md',
    '.github/workflows/pi-harness-contract.yml',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json'
)

$textByPath = @{}
foreach ($relativePath in $requiredFiles) {
    $textByPath[$relativePath] = Read-Tracked $relativePath
}

foreach ($relativePath in @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/upstream-verification.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.pi/settings.json',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json'
)) {
    try {
        $null = $textByPath[$relativePath] | ConvertFrom-Json
        Check $true "json/$relativePath" ''
    }
    catch {
        Check $false "json/$relativePath" $_.Exception.Message
    }
}

try {
    $verification = $textByPath['tooling/pi/harness/upstream-verification.json'] | ConvertFrom-Json
    Check ($verification.schema -eq 'agentswitchboard.pi-upstream-verification.v1') 'upstream/schema' 'unexpected upstream verification schema'
    Check ($verification.package -eq '@earendil-works/pi-coding-agent') 'upstream/package' 'current official package identity is not pinned'
    Check ($verification.version -eq '0.81.1') 'upstream/version' 'verified Pi version drifted without contract update'
    Check ($verification.sourceRepository -eq 'earendil-works/pi') 'upstream/repository' 'current official source repository is not recorded'
    Check ($verification.minimumNodeVersion -eq '22.19.0') 'upstream/node' 'minimum Node version is not pinned'
    Check ($verification.installCommand -eq 'npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.81.1') 'upstream/install' 'verified installation command is missing or unpinned'
    Check ($verification.providerPolicy -match 'CLI is free' -and $verification.providerPolicy -match 'provider access is separate') 'upstream/free-access' 'free CLI and provider-cost boundary is unclear'
}
catch { [void]$failures.Add("upstream/semantic: $($_.Exception.Message)") }

try {
    $registry = $textByPath['tooling/pi/harness/pi-adapter.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.pi-adapter-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.upstream.status -eq 'verified-install-supported') 'registry/upstream-verification' 'verified installation support is not declared'
    Check ($registry.upstream.package -eq $verification.package) 'registry/package' 'registry and verification package identities disagree'
    Check ($registry.upstream.pinnedVersion -eq $verification.version) 'registry/version' 'registry and verification versions disagree'
    Check ($registry.configuration.preferredScope -eq 'project-local') 'registry/project-local' 'project-local configuration is not preferred'
    Check ($registry.configuration.globalCliInstallationAllowed -eq $true) 'registry/global-cli' 'verified global CLI installation is not allowed'
    Check ($registry.configuration.globalConfigurationMutationAllowed -eq $false) 'registry/no-global-config' 'global Pi configuration mutation is allowed'
    Check ($registry.configuration.implicitHookInstallationAllowed -eq $false) 'registry/no-implicit-hooks' 'implicit hook installation is allowed'
    Check ($registry.configuration.projectTrustBypassAllowed -eq $false) 'registry/no-trust-bypass' 'project trust may be bypassed'
    Check ($registry.configuration.lifecycleScriptsAllowed -eq $false) 'registry/no-lifecycle-scripts' 'npm lifecycle scripts are allowed'
    Check ($registry.privacyClaimPolicy.localhostIsSufficient -eq $false) 'registry/privacy-proof' 'localhost is incorrectly treated as privacy proof'
    Check ($registry.freeAccessPolicy.cliCost -eq 'free') 'registry/free-cli' 'Pi CLI cost classification is missing'
    Check ($registry.freeAccessPolicy.providerAccessIsSeparate -eq $true) 'registry/provider-cost-separate' 'provider cost is conflated with CLI cost'
    foreach ($route in @($registry.routes)) {
        Check ($route.writerCount -eq 1) "registry/one-writer/$($route.routeId)" 'route does not require exactly one writer'
    }
    $singleRoute = @($registry.routes | Where-Object { $_.routeId -eq 'pi-single-agent' })[0]
    Check ($singleRoute.status -eq 'launcher-supported-runtime-unproved') 'registry/single-agent-status' 'single-agent launcher support is not represented honestly'
    foreach ($route in @($registry.routes | Where-Object { $_.routeId -ne 'pi-single-agent' })) {
        Check ($route.status -eq 'contract-only') "registry/contract-only/$($route.routeId)" 'multi-agent runtime behavior is claimed without proof'
    }
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $settings = $textByPath['.pi/settings.json'] | ConvertFrom-Json
    Check ($settings.enableInstallTelemetry -eq $false) 'settings/no-install-telemetry' 'project settings enable install telemetry'
    Check ($settings.enableSkillCommands -eq $true) 'settings/skill-commands' 'repository skills are not command-addressable'
    Check (@($settings.skills).Count -eq 1 -and $settings.skills[0] -eq '../.ai/skills') 'settings/skills' 'Pi does not load the repository skill directory'
    Check (@($settings.packages).Count -eq 0) 'settings/no-third-party-packages' 'unreviewed Pi packages are configured'
    Check (@($settings.extensions).Count -eq 0) 'settings/no-third-party-extensions' 'unreviewed Pi extensions are configured'
}
catch { [void]$failures.Add("settings/semantic: $($_.Exception.Message)") }

$expectedWorkflows = @{
    'tooling/pi/harness/workflows/task-intake.workflow.json' = 'pi-task-intake'
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json' = 'pi-opinion-fusion'
    'tooling/pi/harness/workflows/autovalidate.workflow.json' = 'pi-autovalidate'
}
foreach ($path in $expectedWorkflows.Keys) {
    try {
        $workflow = $textByPath[$path] | ConvertFrom-Json
        Check ($workflow.schema -eq 'agentswitchboard.pi-workflow.v1') "workflow/schema/$path" 'unexpected workflow schema'
        Check ($workflow.workflowId -eq $expectedWorkflows[$path]) "workflow/id/$path" 'unexpected workflow ID'
        Check (@($workflow.steps).Count -ge 5) "workflow/steps/$path" 'workflow is not operationally complete'
        Check (-not [string]::IsNullOrWhiteSpace([string]$workflow.proofCeiling)) "workflow/proof/$path" 'proof ceiling is missing'
    }
    catch { [void]$failures.Add("workflow/$path`: $($_.Exception.Message)") }
}

$fusionText = $textByPath['tooling/pi/harness/workflows/opinion-fusion.workflow.json']
foreach ($token in @('inputSha256','consensus','divergence','unresolved risks','designated writer')) {
    Check ($fusionText -match [regex]::Escape($token)) "fusion/$token" 'fusion workflow token is missing'
}
$autoText = $textByPath['tooling/pi/harness/workflows/autovalidate.workflow.json']
foreach ($token in @('maximumAttempts','maximumWallClockMinutes','maximumNoProgressAttempts','frozen gate','one branch writer')) {
    Check ($autoText -match [regex]::Escape($token)) "autovalidate/$token" 'autovalidate bound or authority rule is missing'
}

$skillText = $textByPath['.ai/skills/pi-fusion-orchestration/SKILL.md']
foreach ($token in @('id: pi-fusion-orchestration','status: experimental','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) {
    Check ($skillText.Contains($token)) "skill/$token" 'skill contract token is missing'
}

$installerText = $textByPath['tooling/pi/Install-AgentSwitchboardPi.ps1']
foreach ($token in @('upstream-verification.json','--ignore-scripts','minimumNodeVersion','Pi version mismatch after operation','configurationMutation = ''none''','authenticationMutation = ''none''','AgentSwitchboard/PiHarness/install')) {
    Check ($installerText.Contains($token)) "installer/$token" 'installer contract token is missing'
}
$launcherText = $textByPath['tooling/pi/Start-AgentSwitchboardPi.ps1']
foreach ($token in @("`$env:PI_TELEMETRY = '0'","`$env:PI_SKIP_VERSION_CHECK = '1'","`$env:PI_OFFLINE = '1'",'PI_CODING_AGENT_SESSION_DIR','never bypassed by this launcher','rawArgumentsRecorded = $false','rawPromptRecorded = $false')) {
    Check ($launcherText.Contains($token)) "launcher/$token" 'launcher contract token is missing'
}
foreach ($forbidden in @('--approve','defaultProjectTrust','auth.json','models.json','dangerously-skip-permissions')) {
    Check (-not $launcherText.Contains($forbidden)) "launcher/forbidden/$forbidden" 'launcher bypasses trust or mutates authentication/model state'
}

try {
    $manifest = $textByPath['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($manifest.entrypoints.piHarnessValidator -eq 'scripts/Test-PiHarnessCompleteness.ps1') 'central/manifest/validator' 'Pi completeness validator is not registered'
    Check ($manifest.entrypoints.piFusionSkill -eq '.ai/skills/pi-fusion-orchestration/SKILL.md') 'central/manifest/skill' 'Pi skill is not registered'
    Check ($manifest.entrypoints.piUpstreamVerification -eq 'tooling/pi/harness/upstream-verification.json') 'central/manifest/upstream' 'Pi upstream verification is not registered'
    Check ($manifest.entrypoints.piInstaller -eq 'tooling/pi/Install-AgentSwitchboardPi.ps1') 'central/manifest/installer' 'Pi installer is not registered'
    Check ($manifest.entrypoints.piLauncher -eq 'tooling/pi/Start-AgentSwitchboardPi.ps1') 'central/manifest/launcher' 'Pi launcher is not registered'
    Check ($manifest.entrypoints.piProjectSettings -eq '.pi/settings.json') 'central/manifest/settings' 'Pi project settings are not registered'
    Check ($manifest.piOperationalHarness.status -eq 'installer-launcher-supported-runtime-unproved') 'central/manifest/status' 'Pi support is over- or under-claimed'
    Check ($manifest.piOperationalHarness.writersPerBranch -eq 1) 'central/manifest/one-writer' 'Pi manifest does not enforce one writer'
    Check ($manifest.piOperationalHarness.implicitHookInstallationAllowed -eq $false) 'central/manifest/hooks' 'implicit hook installation is allowed'
    Check ($manifest.piOperationalHarness.globalConfigurationMutationAllowed -eq $false) 'central/manifest/global-config' 'global Pi configuration mutation is allowed'
    Check ($manifest.piOperationalHarness.projectTrustBypassAllowed -eq $false) 'central/manifest/trust' 'project trust bypass is allowed'
    Check ($manifest.piOperationalHarness.providerCallsAllowedByContractValidation -eq $false) 'central/manifest/provider-validation' 'provider calls are allowed during contract validation'
}
catch { [void]$failures.Add("central/manifest: $($_.Exception.Message)") }

try {
    $centralArtifacts = $textByPath['.ai/harness/artifact-registry.json'] | ConvertFrom-Json
    $artifactIds = @($centralArtifacts.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($artifactId in @('pi-run-context','pi-role-opinion','pi-fusion-result','pi-validation-ledger','pi-operator-report','pi-final-handoff')) {
        Check ($artifactIds -contains $artifactId) "central/artifact/$artifactId" 'Pi artifact is not centrally registered'
    }
    foreach ($artifact in @($centralArtifacts.artifacts | Where-Object { [string]$_.artifactId -like 'pi-*' })) {
        Check ($artifact.tracked -eq $false) "central/artifact-untracked/$($artifact.artifactId)" 'generated Pi evidence is tracked'
        Check ($artifact.sensitivity -eq 'local-operational') "central/artifact-sensitivity/$($artifact.artifactId)" 'unexpected sensitivity classification'
    }
}
catch { [void]$failures.Add("central/artifacts: $($_.Exception.Message)") }

$deployableContractPaths = @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/upstream-verification.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    '.pi/settings.json',
    'docs/harness/pi-operational-harness.md'
)
$deployableText = ($deployableContractPaths | ForEach-Object { $textByPath[$_] }) -join "`n"
foreach ($forbidden in @(
    'npm install -g @mariozechner/pi-coding-agent',
    '%USERPROFILE%\.pi',
    'pi.llm.generate',
    'dangerously-skip-permissions',
    'localhost means private',
    'all Pi model access is free'
)) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'stale package, API, permission bypass, privacy shortcut, or cost overclaim is embedded in a deployable contract'
}

Write-Host 'PI HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
