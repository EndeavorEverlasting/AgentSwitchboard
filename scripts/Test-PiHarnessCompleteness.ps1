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
    'tooling/pi/Test-PiWorkstationPrereqs.ps1',
    'tooling/pi/Get-PiHarnessStatus.ps1',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'tests/test_pi_harness_contracts.py',
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
    Check ($verification.package -eq '@earendil-works/pi-coding-agent') 'upstream/package' 'current Pi package identity is not pinned'
    Check ($verification.version -eq '0.84.4') 'upstream/version' 'unexpected Pi version pin'
    Check ($verification.sourceRepository -eq 'earendil-works/pi') 'upstream/source' 'unexpected Pi source repository'
    Check ($verification.minimumNodeVersion -eq '22.19.0') 'upstream/node-minimum' 'unexpected minimum Node version'
    Check ($verification.nodeEngine -eq '>=22.19.0') 'upstream/node-engine' 'unexpected Node engine contract'
    Check ($verification.installCommand -eq 'npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.4') 'upstream/install' 'install command is not exact or lifecycle scripts are not disabled'
    Check ($verification.legacyPackage.package -eq '@mariozechner/pi-coding-agent') 'upstream/legacy-package' 'legacy package identity is missing'
    Check ($verification.legacyPackage.deprecated -eq $true) 'upstream/legacy-deprecated' 'legacy package is not recorded as deprecated'
    Check (-not [string]::IsNullOrWhiteSpace([string]$verification.legacyPackage.deprecatedMessage)) 'upstream/legacy-message' 'legacy deprecation message is missing'
}
catch { [void]$failures.Add("upstream/semantic: $($_.Exception.Message)") }

try {
    $registry = $textByPath['tooling/pi/harness/pi-adapter.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.pi-adapter-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.upstream.package -eq '@earendil-works/pi-coding-agent') 'registry/upstream-package' 'registry still points at a deprecated Pi package'
    Check ($registry.upstream.sourceRepository -eq 'earendil-works/pi') 'registry/upstream-source' 'registry points at the wrong Pi source repository'
    Check ($registry.upstream.pinnedVersion -eq $verification.version) 'registry/upstream-version' 'registry pin does not match the verification record'
    Check ($registry.upstream.status -eq 'verified-prerequisite') 'registry/upstream-verification' 'upstream prerequisite identity is not verified'
    Check ($registry.upstream.verificationRecord -eq 'tooling/pi/harness/upstream-verification.json') 'registry/upstream-record' 'registry does not bind the verification record'
    Check ($registry.configuration.preferredScope -eq 'project-local') 'registry/project-local' 'project-local configuration is not preferred'
    Check ($registry.configuration.globalConfigurationMutationAllowed -eq $false) 'registry/no-global-mutation' 'global configuration mutation is allowed'
    Check ($registry.configuration.implicitHookInstallationAllowed -eq $false) 'registry/no-implicit-hooks' 'implicit hook installation is allowed'
    Check ($registry.privacyClaimPolicy.localhostIsSufficient -eq $false) 'registry/privacy-proof' 'localhost is incorrectly treated as privacy proof'
    foreach ($route in @($registry.routes)) {
        Check ($route.writerCount -eq 1) "registry/one-writer/$($route.routeId)" 'route does not require exactly one writer'
        Check ($route.status -eq 'contract-only') "registry/contract-only/$($route.routeId)" 'runtime behavior is claimed without proof'
    }
}
catch { [void]$failures.Add("registry/semantic: $($_.Exception.Message)") }

try {
    $codebase = $textByPath['tooling/pi/harness/codebase-map.json'] | ConvertFrom-Json
    Check ($codebase.entrypoints.workstationPrereqs -eq 'tooling/pi/Test-PiWorkstationPrereqs.ps1') 'codebase/preflight' 'workstation prerequisite entrypoint is not registered'
    Check ($codebase.entrypoints.upstreamVerification -eq 'tooling/pi/harness/upstream-verification.json') 'codebase/upstream' 'upstream verification record is not registered'
    $commandText = (@($codebase.commands | ForEach-Object { [string]$_.command }) -join "`n")
    Check ($commandText -match [regex]::Escape('tooling/pi/Test-PiWorkstationPrereqs.ps1')) 'codebase/preflight-command' 'operator preflight command is missing'
}
catch { [void]$failures.Add("codebase/semantic: $($_.Exception.Message)") }

$preflightText = $textByPath['tooling/pi/Test-PiWorkstationPrereqs.ps1']
foreach ($token in @(
    'agentswitchboard.pi-workstation-prereqs.v1',
    'Invoke-NpmJson',
    '[string]$verification.package',
    '[string]$verification.legacyPackage.package',
    "'engines'",
    "'deprecated'",
    'upstream-drift',
    'installed-version-drift',
    'ready-to-install',
    'NoNetwork',
    'AllowUnready',
    'paths = $npmPaths',
    'legacyPackage'
)) {
    Check ($preflightText.Contains($token)) "preflight/$token" 'workstation prerequisite contract token is missing'
}
Check (-not $preflightText.Contains('npm install -g @mariozechner/pi-coding-agent')) 'preflight/no-legacy-install' 'preflight embeds the deprecated install path'
Check ($preflightText.Contains('Read-only local prerequisite and live npm metadata proof')) 'preflight/proof-ceiling' 'preflight proof ceiling is missing'

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

try {
    $manifest = $textByPath['.ai/harness/manifest.json'] | ConvertFrom-Json
    Check ($manifest.entrypoints.piHarnessValidator -eq 'scripts/Test-PiHarnessCompleteness.ps1') 'central/manifest/validator' 'Pi completeness validator is not registered'
    Check ($manifest.entrypoints.piFusionSkill -eq '.ai/skills/pi-fusion-orchestration/SKILL.md') 'central/manifest/skill' 'Pi skill is not registered'
    Check ($manifest.piOperationalHarness.status -eq 'contract-only') 'central/manifest/status' 'Pi runtime is overclaimed'
    Check ($manifest.piOperationalHarness.writersPerBranch -eq 1) 'central/manifest/one-writer' 'Pi manifest does not enforce one writer'
    Check ($manifest.piOperationalHarness.implicitHookInstallationAllowed -eq $false) 'central/manifest/hooks' 'implicit hook installation is allowed'
    Check ($manifest.piOperationalHarness.providerCallsAllowedByContract -eq $false) 'central/manifest/provider' 'provider calls are allowed by contract-only validation'
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
    'docs/harness/pi-operational-harness.md'
)
$deployableText = ($deployableContractPaths | ForEach-Object { $textByPath[$_] }) -join "`n"
foreach ($forbidden in @(
    'npm install -g @mariozechner/pi-coding-agent',
    '%USERPROFILE%\.pi',
    'pi.llm.generate',
    'dangerously-skip-permissions',
    'localhost means private'
)) {
    Check (-not $deployableText.Contains($forbidden)) "forbidden/$forbidden" 'unverified installation, API, permission bypass, or privacy shortcut is embedded in a deployable contract'
}

$docsText = $textByPath['docs/harness/pi-operational-harness.md']
Check ($docsText.Contains('Test-PiWorkstationPrereqs.ps1')) 'docs/preflight' 'operator guide does not route through the workstation prerequisite preflight'
Check ($docsText.Contains('@earendil-works/pi-coding-agent@0.84.4')) 'docs/current-pin' 'operator guide does not name the current verified Pi pin'

Write-Host 'PI HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
