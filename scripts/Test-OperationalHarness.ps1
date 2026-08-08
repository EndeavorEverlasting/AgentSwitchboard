[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([Parameter(Mandatory)][bool]$Passed, [Parameter(Mandatory)][string]$Name, [string]$FailureMessage = '')
    if ($Passed) { [void]$passes.Add($Name) } else { [void]$failures.Add("${Name}: $FailureMessage") }
}

function Read-Json {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { [void]$failures.Add("required-file/${RelativePath}: missing"); return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { [void]$failures.Add("json/${RelativePath}: $($_.Exception.Message)"); return $null }
}

$required = @(
    'HARNESS.md',
    'tooling/harness/operational/manifest.json',
    'tooling/harness/operational/codebase-map.json',
    'tooling/harness/operational/workflow-registry.json',
    'tooling/harness/operational/artifact-registry.json',
    'tooling/harness/operational/validator-registry.json',
    'tooling/harness/operational/workflows/task-intake.workflow.json',
    'tooling/harness/operational/workflows/pre-commit-validation.workflow.json',
    'tooling/harness/operational/workflows/failure-recovery.workflow.json',
    'tooling/harness/operational/workflows/handoff.workflow.json',
    'tooling/harness/operational/schemas/operational-harness-status.schema.json',
    'tooling/harness/operational/schemas/operational-harness-handoff.schema.json',
    'tooling/harness/operational/templates/operator-report.template.md',
    'tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1',
    'tooling/harness/operational/Get-OperationalHarnessStatus.py',
    '.ai/skills/operational-harness-routing/SKILL.md',
    'scripts/Test-OperationalHarness.ps1',
    'tests/test_operational_harness.py',
    'docs/harness/operational-harness.md',
    '.github/workflows/operational-harness.yml'
)
foreach ($relative in $required) { Add-Result (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) "required-file/$relative" 'required operational harness component is missing' }

$manifest = Read-Json 'tooling/harness/operational/manifest.json'
$codebase = Read-Json 'tooling/harness/operational/codebase-map.json'
$workflowRegistry = Read-Json 'tooling/harness/operational/workflow-registry.json'
$artifactRegistry = Read-Json 'tooling/harness/operational/artifact-registry.json'
$validatorRegistry = Read-Json 'tooling/harness/operational/validator-registry.json'

if ($null -ne $manifest) {
    Add-Result ($manifest.schemaVersion -eq 1) 'manifest/schema-version' 'expected schemaVersion 1'
    Add-Result ($manifest.harnessId -eq 'agentswitchboard.operational-harness.v1') 'manifest/id' 'unexpected harness id'
    Add-Result ($manifest.generatedEvidence.tracked -eq $false) 'manifest/untracked-evidence' 'generated evidence must remain untracked'
    Add-Result ($manifest.hooks.implicitInstallationAllowed -eq $false) 'manifest/opt-in-hooks' 'hooks may not install implicitly'
    Add-Result ($manifest.safety.networkRequired -eq $false) 'manifest/no-network-requirement' 'operational harness must not require network'
    Add-Result ($manifest.safety.liveTargetMutationAllowed -eq $false) 'manifest/no-live-target-mutation' 'live target mutation is forbidden'
    Add-Result ($manifest.safety.productMutationAllowed -eq $false) 'manifest/no-product-mutation' 'product mutation is forbidden'
    Add-Result ($manifest.safety.destructiveGitAllowed -eq $false) 'manifest/no-destructive-git' 'destructive Git is forbidden'
    Add-Result ($manifest.safety.governanceMutationOwned -eq $false) 'manifest/no-governance-ownership' 'governance mutation is not owned'
    foreach ($property in $manifest.entrypoints.PSObject.Properties) {
        $relative = [string]$property.Value
        Add-Result (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) "manifest/entrypoint/$($property.Name)" "entrypoint missing: $relative"
    }
}

if ($null -ne $codebase) {
    $paths = @($codebase.structure | ForEach-Object { [string]$_.path })
    foreach ($expected in @('AGENTS.md', '.ai/harness/', '.ai/skills/', 'scripts/', 'tests/', '.github/workflows/')) { Add-Result ($paths -contains $expected) "codebase/structure/$expected" 'expected structure owner missing' }
    Add-Result ($codebase.commands.build.command -eq 'none') 'codebase/no-invented-build' 'generic build command must not be invented'
    Add-Result ($codebase.commands.deploy.command -eq 'none') 'codebase/no-invented-deploy' 'generic deploy command must not be invented'
    $trapText = (@($codebase.knownTraps) -join "`n")
    Add-Result ($trapText -match 'current shell') 'codebase/cwd-trap' 'caller working-directory trap missing'
    Add-Result ($trapText -match '\.Trim\(\)') 'codebase/null-trim-trap' 'null Trim trap missing'
}

if ($null -ne $workflowRegistry) {
    $ids = @($workflowRegistry.workflows | ForEach-Object { [string]$_.workflowId })
    foreach ($expected in @('task-intake','pre-commit-validation','failure-recovery','handoff')) { Add-Result ($ids -contains $expected) "workflows/$expected" 'lifecycle workflow missing' }
    foreach ($workflow in @($workflowRegistry.workflows)) { Add-Result (Test-Path -LiteralPath (Join-Path $RootPath ([string]$workflow.path)) -PathType Leaf) "workflows/path/$($workflow.workflowId)" 'workflow path missing' }
}

if ($null -ne $artifactRegistry) {
    Add-Result ($artifactRegistry.trackedGeneratedArtifacts -eq $false) 'artifacts/untracked' 'generated artifacts must remain untracked'
    $artifactIds = @($artifactRegistry.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($expected in @('operational-harness-status','operational-harness-operator-report','operational-harness-validation-ledger','operational-harness-handoff')) { Add-Result ($artifactIds -contains $expected) "artifacts/$expected" 'artifact role missing' }
}

if ($null -ne $validatorRegistry) {
    $ids = @($validatorRegistry.validators | ForEach-Object { [string]$_.id })
    foreach ($expected in @('operational-python','operational-powershell','diff-check','harness-doctrine','repository-family','agent-documentation')) { Add-Result ($ids -contains $expected) "validators/$expected" 'validator missing' }
    foreach ($validator in @($validatorRegistry.validators)) { Add-Result ($validator.mutatesTarget -eq $false) "validators/no-target-mutation/$($validator.id)" 'validator may not mutate targets' }
}

foreach ($schemaPath in @('tooling/harness/operational/schemas/operational-harness-status.schema.json','tooling/harness/operational/schemas/operational-harness-handoff.schema.json')) {
    $schema = Read-Json $schemaPath
    if ($null -ne $schema) {
        Add-Result ($schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema') "schema/$schemaPath/draft" 'expected JSON Schema 2020-12'
        Add-Result (-not [string]::IsNullOrWhiteSpace([string]$schema.title)) "schema/$schemaPath/title" 'schema title missing'
    }
}

$hookPath = Join-Path $RootPath 'tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1'
if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($hookPath, [ref]$tokens, [ref]$parseErrors)
    Add-Result ($parseErrors.Count -eq 0) 'hook/powershell-parse' ($parseErrors -join '; ')
    $hookText = Get-Content -LiteralPath $hookPath -Raw
    Add-Result ($hookText.Contains('Test-OperationalHarness.ps1')) 'hook/owning-validator' 'owning validator missing'
    Add-Result ($hookText.Contains('diff --cached --check')) 'hook/staged-diff-check' 'staged diff check missing'
    Add-Result ($hookText -notmatch '(?i)core\.hooksPath|git\s+config|reset\s+--hard|git\s+clean|force-push') 'hook/no-implicit-or-destructive-git' 'hook contains forbidden Git behavior'
}

$skillPath = Join-Path $RootPath '.ai/skills/operational-harness-routing/SKILL.md'
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skillText = Get-Content -LiteralPath $skillPath -Raw
    foreach ($token in @('id: operational-harness-routing','status: canonical','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) { Add-Result ($skillText.Contains($token)) "skill/$token" 'required skill token missing' }
}

Write-Host 'OPERATIONAL HARNESS CONTRACT' -ForegroundColor Cyan
foreach ($pass in $passes) { Write-Host "[PASS] $pass" -ForegroundColor Green }
foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
