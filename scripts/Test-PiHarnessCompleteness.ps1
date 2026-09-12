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
    'tooling/pi/harness/system-bootstrap.contract.json',
    'tooling/pi/harness/child-agent-invocation.contract.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    'tooling/pi/Install-AgentSwitchboardPiSystem.ps1',
    'tooling/pi/Invoke-AgentSwitchboardPiChild.ps1',
    'Bootstrap-Pi-SystemWide.cmd',
    'tooling/pi/Test-PiWorkstationPrereqs.ps1',
    'tooling/pi/Get-PiHarnessStatus.ps1',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'tests/Test-PiWorkstationPrereqsContracts.ps1',
    'tests/test_pi_harness_contracts.py',
    'tests/test_pi_system_bootstrap.py',
    'docs/harness/pi-operational-harness.md',
    'docs/harness/pi-system-bootstrap-and-child-agents.md',
    '.github/workflows/pi-harness-contract.yml',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json'
)

$textByPath = @{}
foreach ($relativePath in $requiredFiles) { $textByPath[$relativePath] = Read-Tracked $relativePath }

$jsonPaths = @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/upstream-verification.json',
    'tooling/pi/harness/system-bootstrap.contract.json',
    'tooling/pi/harness/child-agent-invocation.contract.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json'
)
foreach ($relativePath in $jsonPaths) {
    try { $null = $textByPath[$relativePath] | ConvertFrom-Json; Check $true "json/$relativePath" '' }
    catch { Check $false "json/$relativePath" $_.Exception.Message }
}

try {
    $verification = $textByPath['tooling/pi/harness/upstream-verification.json'] | ConvertFrom-Json
    Check ($verification.schema -eq 'agentswitchboard.pi-upstream-verification.v1') 'upstream/schema' 'unexpected upstream verification schema'
    Check ($verification.package -eq '@earendil-works/pi-coding-agent') 'upstream/package' 'current Pi package identity is not pinned'
    Check ($verification.version -eq '0.85.1') 'upstream/version' 'unexpected Pi version pin'
    Check ($verification.versionTag -eq 'v0.85.1') 'upstream/version-tag' 'unexpected Pi version tag'
    Check ($verification.verifiedAt -eq '2026-09-11') 'upstream/verified-at' 'upstream verification date is stale'
    Check ($verification.sourceRepository -eq 'earendil-works/pi') 'upstream/source' 'unexpected Pi source repository'
    Check ($verification.sourceUrl -eq 'https://github.com/earendil-works/pi') 'upstream/source-url' 'source URL is missing'
    Check ($verification.minimumNodeVersion -eq '22.19.0') 'upstream/node-minimum' 'unexpected npm compatibility Node floor'
    Check ($verification.installCommand -eq 'npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.85.1') 'upstream/npm-compatibility-install' 'npm compatibility install command is not exact'
    Check ($verification.nativeRelease.preferredWindowsDistribution -eq 'standalone-release') 'upstream/native-preferred' 'Windows bootstrap is not bound to the standalone release'
    Check ($verification.nativeRelease.windows.x64.assetName -eq 'pi-windows-x64.zip') 'upstream/x64-asset' 'x64 asset identity is wrong'
    Check ($verification.nativeRelease.windows.x64.sha256 -eq '002fa95b90d521245b9985d8f168caebc237ad56e7e30b319807dee1b2e17e1c') 'upstream/x64-sha' 'x64 release digest drifted'
    Check ($verification.nativeRelease.windows.arm64.sha256 -eq 'b25e96fe64c9f41f75a924c0d36f395abb98d6c6fec0b78aaa0b86926f938bb4') 'upstream/arm64-sha' 'ARM64 release digest drifted'
    Check ($verification.nativeRelease.systemBootstrap.packageManagerRequired -eq $false) 'upstream/no-package-manager' 'system bootstrap incorrectly requires a package manager'
    Check ($verification.nativeRelease.systemBootstrap.nodeRuntimeRequired -eq $false) 'upstream/no-node-runtime' 'system bootstrap incorrectly requires Node.js'
    Check ($verification.programmaticModes.rpc -eq $true) 'upstream/rpc' 'official RPC capability is not recorded'
    Check ($verification.programmaticModes.rpcFraming -eq 'strict LF-delimited JSONL') 'upstream/rpc-framing' 'RPC framing contract is missing'
    Check (@($verification.officialEvidence).Count -ge 5) 'upstream/official-evidence' 'official evidence sources are incomplete'
    Check ($verification.legacyPackage.deprecated -eq $true) 'upstream/legacy-deprecated' 'legacy package deprecation is not recorded'
}
catch { [void]$failures.Add("upstream/semantic: $($_.Exception.Message)") }

try {
    $system = $textByPath['tooling/pi/harness/system-bootstrap.contract.json'] | ConvertFrom-Json
    Check ($system.contractId -eq 'agentswitchboard.pi-system-bootstrap.v1') 'system/contract-id' 'unexpected Pi system bootstrap contract'
    Check ($system.owner -eq 'tooling/pi/Install-AgentSwitchboardPiSystem.ps1') 'system/owner' 'system bootstrap owner drifted'
    Check (@($system.preflight.packageManagersAssumed).Count -eq 0) 'system/no-package-manager' 'system bootstrap assumes a package manager'
    Check ($system.preflight.nodeRuntimeRequired -eq $false) 'system/no-node' 'system bootstrap assumes Node.js'
    Check ($system.safety.officialDigestRequired -eq $true) 'system/digest-required' 'official digest is not required'
    Check ($system.safety.globalPiConfigurationMutationAllowed -eq $false) 'system/no-global-config' 'global Pi config mutation is allowed'
    Check ($system.safety.providerAuthenticationMutationAllowed -eq $false) 'system/no-auth' 'provider authentication mutation is allowed'
    Check ($system.safety.projectTrustMutationAllowed -eq $false) 'system/no-trust' 'project trust mutation is allowed'
    Check ($system.safety.wholeScriptPowerShellRequired -eq $true) 'system/whole-script' 'PowerShell whole-script contract is missing'
}
catch { [void]$failures.Add("system/semantic: $($_.Exception.Message)") }

try {
    $registry = $textByPath['tooling/pi/harness/pi-adapter.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.pi-adapter-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.upstream.package -eq '@earendil-works/pi-coding-agent') 'registry/upstream-package' 'registry points at wrong package'
    Check ($registry.upstream.pinnedVersion -eq $verification.version) 'registry/upstream-version' 'registry pin does not match upstream verification'
    Check ($registry.systemRuntime.bootstrap -eq 'tooling/pi/Install-AgentSwitchboardPiSystem.ps1') 'registry/system-bootstrap' 'system bootstrap is not registered'
    Check ($registry.systemRuntime.packageManagerRequired -eq $false) 'registry/system-package-manager' 'system runtime requires package manager'
    Check ($registry.childInvocation.adapter -eq 'tooling/pi/Invoke-AgentSwitchboardPiChild.ps1') 'registry/child-adapter' 'child adapter is not registered'
    Check ($registry.childInvocation.pairwiseAgentConfigurationRequired -eq $false) 'registry/no-pairwise' 'pairwise agent configuration is still required'
    Check ($registry.childInvocation.separateChildContext -eq $true) 'registry/separate-child-context' 'separate child context is not required'
    Check ($registry.configuration.preferredScope -eq 'project-local') 'registry/project-local' 'project-local configuration is not preferred'
    Check ($registry.configuration.globalConfigurationMutationAllowed -eq $false) 'registry/no-global-mutation' 'global Pi configuration mutation is allowed'
    Check ($registry.privacyClaimPolicy.localhostIsSufficient -eq $false) 'registry/privacy-proof' 'localhost is incorrectly treated as privacy proof'
    foreach ($route in @($registry.routes)) {
        Check ($route.writerCount -eq 1) "registry/one-writer/$($route.routeId)" 'route does not require exactly one writer'
        Check ($route.status -eq 'contract-only') "registry/contract-only/$($route.routeId)" 'multi-agent route is overclaimed without live proof'
    }
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $child = $textByPath['tooling/pi/harness/child-agent-invocation.contract.json'] | ConvertFrom-Json
    Check ($child.contractId -eq 'agentswitchboard.pi-child-agent.v1') 'child/contract-id' 'unexpected child contract'
    Check ($child.architecture.pairwiseAgentConfigurationRequired -eq $false) 'child/no-pairwise' 'pairwise configuration is still required'
    Check ($child.piTransport.mode -eq 'json-subprocess') 'child/transport-v1' 'v1 transport is not the bounded JSON subprocess'
    Check ($child.piTransport.upstreamRpcAvailable -eq $true) 'child/rpc-known' 'upstream RPC capability is not recorded'
    Check ($child.writeModes.writer.isolatedWorktreeRequired -eq $true) 'child/writer-isolation' 'writer isolation is not required'
    Check ($child.writeModes.writer.mainOrDefaultBranchAllowed -eq $false) 'child/no-default-writer' 'writer may target default branch'
    Check ($child.writeModes.writer.writersPerMutationSurface -eq 1) 'child/one-writer' 'writer count is not one'
    Check ($child.resultEnvelope.rawEventMayContainPrompt -eq $true) 'child/raw-event-sensitive' 'raw event sensitivity is not explicit'
    Check ($child.resultEnvelope.rawEventsTracked -eq $false) 'child/raw-events-untracked' 'raw child events may be tracked'
    Check ($child.parallelism.coordinatorOwnsRejoin -eq $true) 'child/coordinator-rejoin' 'coordinator does not own rejoin'
    Check ($child.parallelism.childMayMergeDefaultBranch -eq $false) 'child/no-child-merge' 'child may merge default branch'
}
catch { [void]$failures.Add("child/semantic: $($_.Exception.Message)") }

try {
    $codebase = $textByPath['tooling/pi/harness/codebase-map.json'] | ConvertFrom-Json
    Check ($codebase.entrypoints.systemBootstrap -eq 'tooling/pi/Install-AgentSwitchboardPiSystem.ps1') 'codebase/system-bootstrap' 'system bootstrap entrypoint is not registered'
    Check ($codebase.entrypoints.childInvocation -eq 'tooling/pi/Invoke-AgentSwitchboardPiChild.ps1') 'codebase/child' 'child invocation entrypoint is not registered'
    Check ($codebase.entrypoints.workstationPrereqs -eq 'tooling/pi/Test-PiWorkstationPrereqs.ps1') 'codebase/preflight' 'npm compatibility preflight is not registered'
    Check ($codebase.entrypoints.upstreamVerification -eq 'tooling/pi/harness/upstream-verification.json') 'codebase/upstream' 'upstream record is not registered'
}
catch { [void]$failures.Add("codebase/semantic: $($_.Exception.Message)") }

$bootstrapText = [string]$textByPath['tooling/pi/Install-AgentSwitchboardPiSystem.ps1']
foreach ($token in @('agentswitchboard.pi-system-bootstrap.v1','Get-FileHash','Expand-Archive','PI_RELEASE_SHA256_MISMATCH','PI_LAUNCHER_PATH_ALREADY_OWNED','PI_INSTALL_DIRECTORY_ALREADY_OWNED','AgentSwitchboard\agents\pi','AgentSwitchboard\bin','GIT_BASH_REQUIRED')) {
    Check ($bootstrapText.Contains($token)) "bootstrap/$token" 'system bootstrap contract token is missing'
}
foreach ($forbidden in @('npm install','choco install','scoop install','winget install','Invoke-Expression')) {
    Check (-not $bootstrapText.ToLowerInvariant().Contains($forbidden.ToLowerInvariant())) "bootstrap/forbidden/$forbidden" 'package-manager or dynamic-eval path is embedded in system bootstrap'
}

$childText = [string]$textByPath['tooling/pi/Invoke-AgentSwitchboardPiChild.ps1']
foreach ($token in @("--mode','json",'--no-session','--no-extensions','--no-skills','--no-prompt-templates','--no-approve','agent_end','completed-unvalidated','Writer child requires an isolated linked Git worktree','PI_CHILD_READ_ONLY_MUTATION')) {
    Check ($childText.Contains($token)) "child-script/$token" 'child invocation contract token is missing'
}
Check (-not $childText.Contains('Get-Command pi')) 'child-script/no-arbitrary-pi' 'child adapter may resolve an arbitrary PATH Pi'
Check (-not $childText.Contains('ApiKey')) 'child-script/no-api-key' 'child adapter accepts an API key parameter'

$preflightText = [string]$textByPath['tooling/pi/Test-PiWorkstationPrereqs.ps1']
foreach ($token in @('agentswitchboard.pi-workstation-prereqs.v1','Invoke-NpmJson','Invoke-BoundedProbe','Get-ProjectShellPath','Get-BoundedPathEvidence','Test-PathInsideRoot','ProbeTimeoutSeconds','OUTPUT_DIRECTORY_INSIDE_REPOSITORY','UPSTREAM_VERIFICATION_MISSING','UPSTREAM_VERIFICATION_INCOMPLETE','upstream-drift','installed-version-drift','ready-to-install','NoNetwork','AllowUnready')) {
    Check ($preflightText.Contains($token)) "preflight/$token" 'npm compatibility preflight token is missing'
}
Check ($preflightText.Contains('Read-only local prerequisite and bounded live npm metadata proof')) 'preflight/proof-ceiling' 'preflight proof ceiling is missing'

$statusText = [string]$textByPath['tooling/pi/Get-PiHarnessStatus.ps1']
foreach ($token in @('ConvertTo-PowerShellSingleQuotedLiteral','$nextScriptPath = Join-Path $RootPath $nextRelativePath','-RootPath $rootLiteral','runtime-ready-provider-unproved','bootstrap-available-runtime-unproved')) {
    Check ($statusText.Contains($token)) "status/$token" 'status contract token is missing'
}

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

$fusionText = [string]$textByPath['tooling/pi/harness/workflows/opinion-fusion.workflow.json']
foreach ($token in @('inputSha256','consensus','divergence','unresolved risks','designated writer')) { Check ($fusionText -match [regex]::Escape($token)) "fusion/$token" 'fusion workflow token is missing' }
$autoText = [string]$textByPath['tooling/pi/harness/workflows/autovalidate.workflow.json']
foreach ($token in @('maximumAttempts','maximumWallClockMinutes','maximumNoProgressAttempts','frozen gate','one branch writer')) { Check ($autoText -match [regex]::Escape($token)) "autovalidate/$token" 'autovalidate bound or authority rule is missing' }

$skillText = [string]$textByPath['.ai/skills/pi-fusion-orchestration/SKILL.md']
foreach ($token in @('id: pi-fusion-orchestration','status: experimental','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) { Check ($skillText.Contains($token)) "skill/$token" 'skill contract token is missing' }

try {
    $manifest = $textByPath['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($manifest.entrypoints.piHarnessValidator -eq 'scripts/Test-PiHarnessCompleteness.ps1') 'central/manifest/validator' 'Pi validator is not registered'
    Check ($manifest.piOperationalHarness.status -eq 'contract-only') 'central/manifest/status' 'multi-agent Pi workflows are overclaimed'
    Check ($manifest.piOperationalHarness.writersPerBranch -eq 1) 'central/manifest/one-writer' 'Pi manifest does not enforce one writer'
    Check ($manifest.piOperationalHarness.providerCallsAllowedByContract -eq $false) 'central/manifest/provider' 'provider calls are allowed by contract-only workflow validation'
}
catch { [void]$failures.Add("central/manifest: $($_.Exception.Message)") }

try {
    $artifacts = $textByPath['tooling/pi/harness/artifact-registry.json'] | ConvertFrom-Json
    Check ($artifacts.tracked -eq $false) 'artifacts/untracked' 'Pi generated artifacts are tracked'
    $artifactNames = @($artifacts.artifacts | ForEach-Object { [string]$_.fileName })
    Check ($artifactNames -contains 'pi-fusion-result.json') 'artifacts/fusion' 'fusion artifact is missing'
    Check ($artifactNames -contains 'pi-validation-ledger.json') 'artifacts/validation' 'validation ledger is missing'
}
catch { [void]$failures.Add("artifacts/semantic: $($_.Exception.Message)") }

$hookText = [string]$textByPath['tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1']
foreach ($token in @('pi-workstation-prereqs.json','pi-workstation-prereqs.md','pi-harness-status.json','pi-harness-status.md')) { Check ($hookText.Contains($token)) "hook/$token" 'pre-commit does not reject generated Pi evidence filename' }

$deployableContractPaths = @(
    'tooling/pi/harness/codebase-map.json','tooling/pi/harness/pi-adapter.registry.json','tooling/pi/harness/upstream-verification.json','tooling/pi/harness/system-bootstrap.contract.json','tooling/pi/harness/child-agent-invocation.contract.json','tooling/pi/harness/artifact-registry.json','tooling/pi/harness/workflows/task-intake.workflow.json','tooling/pi/harness/workflows/opinion-fusion.workflow.json','tooling/pi/harness/workflows/autovalidate.workflow.json','.ai/skills/pi-fusion-orchestration/SKILL.md','docs/harness/pi-operational-harness.md','docs/harness/pi-system-bootstrap-and-child-agents.md'
)
$deployableText = ($deployableContractPaths | ForEach-Object { [string]$textByPath[$_] }) -join "`n"
foreach ($forbidden in @('npm install -g @mariozechner/pi-coding-agent','%USERPROFILE%\.pi','pi.llm.generate','dangerously-skip-permissions','localhost means private')) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'unverified installation, API, permission bypass, or privacy shortcut is embedded in a deployable contract'
}

$docsText = [string]$textByPath['docs/harness/pi-operational-harness.md']
Check ($docsText.Contains('Test-PiWorkstationPrereqs.ps1')) 'docs/preflight' 'operator guide does not retain the npm compatibility preflight'
Check ($docsText.Contains('@earendil-works/pi-coding-agent@0.85.1')) 'docs/current-pin' 'operator guide does not name current verified Pi pin'
Check ($docsText.Contains('Bootstrap-Pi-SystemWide.cmd')) 'docs/system-bootstrap' 'operator guide does not route through system bootstrap'
Check ($docsText.Contains('Invoke-AgentSwitchboardPiChild.ps1')) 'docs/child' 'operator guide does not route through child adapter'
Check ($docsText.Contains('ProbeTimeoutSeconds')) 'docs/probe-timeout' 'operator guide does not document bounded compatibility probes'
Check ($docsText.Contains('outside the repository')) 'docs/output-root' 'operator guide does not document evidence output-root protection'

Write-Host 'PI HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
