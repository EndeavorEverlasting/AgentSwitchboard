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
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json',
    '.ai/skills/pi-fusion-orchestration/SKILL.md',
    'tooling/pi/Get-PiHarnessStatus.ps1',
    'tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1',
    'tests/test_pi_harness_contracts.py',
    'docs/harness/pi-operational-harness.md',
    '.github/workflows/pi-harness-contract.yml'
)

$textByPath = @{}
foreach ($relativePath in $requiredFiles) {
    $textByPath[$relativePath] = Read-Tracked $relativePath
}

foreach ($relativePath in @(
    'tooling/pi/harness/codebase-map.json',
    'tooling/pi/harness/pi-adapter.registry.json',
    'tooling/pi/harness/artifact-registry.json',
    'tooling/pi/harness/workflows/task-intake.workflow.json',
    'tooling/pi/harness/workflows/opinion-fusion.workflow.json',
    'tooling/pi/harness/workflows/autovalidate.workflow.json',
    'tooling/pi/harness/schemas/pi-harness-contracts.schema.json'
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
    $registry = $textByPath['tooling/pi/harness/pi-adapter.registry.json'] | ConvertFrom-Json
    Check ($registry.schema -eq 'agentswitchboard.pi-adapter-registry.v1') 'registry/schema' 'unexpected registry schema'
    Check ($registry.upstream.status -eq 'verification-required') 'registry/upstream-verification' 'upstream version must fail closed until verified'
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

foreach ($central in @('CODEBASE_MAP.md','SKILLS.md','CAPABILITIES.md','TRIGGERS.md','.ai/harness/manifest.json','.ai/harness/artifact-registry.json')) {
    $text = Read-Tracked $central
    if ($null -ne $text) {
        Check ($text.Contains('pi-operational-harness') -or $text.Contains('pi-fusion-orchestration') -or $text.Contains('pi.harness')) "central/$central" 'Pi harness is not registered in the central surface'
    }
}

$combined = ($textByPath.Values -join "`n")
foreach ($forbidden in @(
    'npm install -g @mariozechner/pi-coding-agent',
    '%USERPROFILE%\\.pi',
    'pi.llm.generate',
    'dangerously-skip-permissions',
    'localhost means private'
)) {
    Check (-not $combined.Contains($forbidden)) "forbidden/$forbidden" 'unverified installation, API, permission bypass, or privacy shortcut is embedded'
}

Write-Host 'PI HARNESS COMPLETENESS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
