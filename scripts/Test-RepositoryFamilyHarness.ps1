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
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ''
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("${Name}: $FailureMessage")
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/${RelativePath}: file is missing")
        return $null
    }

    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        [void]$failures.Add("json/${RelativePath}: $($_.Exception.Message)")
        return $null
    }
}

function Test-RelativeRepoPath {
    param([Parameter(Mandatory)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ([IO.Path]::IsPathRooted($Value)) { return $false }
    if ($Value -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    return $true
}

$requiredFiles = @(
    'CODEBASE_MAP.md',
    '.ai/harness/manifest.json',
    '.ai/harness/repository-family.registry.json',
    '.ai/harness/artifact-registry.json',
    '.ai/harness/operator-report.template.md',
    '.ai/harness/workflows/repository-family-intake.workflow.json',
    '.ai/harness/schemas/repository-family-registry.schema.json',
    '.ai/harness/schemas/run-context.schema.json',
    '.ai/harness/schemas/repository-family-status.schema.json',
    '.ai/harness/schemas/final-handoff.schema.json',
    'scripts/Get-RepositoryFamilyHarnessStatus.ps1',
    'scripts/Test-RepositoryFamilyHarness.ps1'
)

foreach ($relativePath in $requiredFiles) {
    Add-Result `
        -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) `
        -Name "required-file/${relativePath}" `
        -FailureMessage 'required harness file is missing'
}

$manifest = Read-JsonFile '.ai/harness/manifest.json'
$registry = Read-JsonFile '.ai/harness/repository-family.registry.json'
$artifactRegistry = Read-JsonFile '.ai/harness/artifact-registry.json'
$workflow = Read-JsonFile '.ai/harness/workflows/repository-family-intake.workflow.json'

if ($null -ne $manifest) {
    Add-Result ($manifest.schemaVersion -eq 1) 'manifest/schema-version' 'expected schemaVersion 1'
    Add-Result ($manifest.harnessId -eq 'agentswitchboard.repository-family-harness.v1') 'manifest/id' 'unexpected harnessId'
    Add-Result ($manifest.canonicalRepository -eq 'EndeavorEverlasting/AgentSwitchboard') 'manifest/canonical-repository' 'unexpected canonical repository'
    Add-Result ($manifest.generatedEvidence.tracked -eq $false) 'manifest/untracked-evidence' 'generated family evidence must remain untracked'
    Add-Result ($manifest.localHooks.enabled -eq $false) 'manifest/no-implicit-hooks' 'local hooks must remain disabled in the first slice'

    foreach ($property in @('agentRules', 'codebaseMap', 'skillsCatalog', 'familyRegistry', 'artifactRegistry', 'workflow', 'statusProbe', 'validator', 'operatorReportTemplate', 'finalHandoffSchema')) {
        $value = [string]$manifest.entrypoints.$property
        Add-Result (Test-RelativeRepoPath $value) "manifest/entrypoint/${property}" 'entrypoint must be a non-empty repository-relative path'
    }
}

if ($null -ne $registry) {
    Add-Result ($registry.schemaVersion -eq 1) 'registry/schema-version' 'expected schemaVersion 1'
    Add-Result ($registry.registryId -eq 'agentswitchboard.repository-family.v1') 'registry/id' 'unexpected registryId'
    Add-Result ($registry.canonicalRepository -eq 'EndeavorEverlasting/AgentSwitchboard') 'registry/canonical-repository' 'unexpected canonical repository'
    Add-Result ($registry.defaultBranchAuthorityRequired -eq $true) 'registry/default-branch-authority' 'default branch authority must be required'

    $repositories = @($registry.repositories)
    $expectedRepositories = @(
        'EndeavorEverlasting/AgentSwitchboard',
        'EndeavorEverlasting/BlacksmithGuild',
        'EndeavorEverlasting/web-excel-repair-triage',
        'EndeavorEverlasting/SysAdminSuite'
    )

    Add-Result ($repositories.Count -eq 4) 'registry/repository-count' 'registry must contain exactly four repositories'
    $actualNames = @($repositories | ForEach-Object { [string]$_.fullName })
    foreach ($expected in $expectedRepositories) {
        Add-Result ($actualNames -contains $expected) "registry/repository/${expected}" 'required repository is not registered'
    }
    Add-Result ((@($actualNames | Select-Object -Unique)).Count -eq $actualNames.Count) 'registry/unique-repositories' 'repository names must be unique'

    $entrypointProperties = @(
        'agentRules',
        'codebaseMap',
        'skillRoots',
        'workflowRoots',
        'runContextAuthorities',
        'artifactRegistryAuthorities',
        'validatorEntrypoints',
        'operatorReportAuthorities',
        'handoffAuthorities',
        'readOnlyIntelligence'
    )

    foreach ($repository in $repositories) {
        $id = [string]$repository.id
        Add-Result (-not [string]::IsNullOrWhiteSpace($id)) "registry/${id}/id" 'repository id is missing'
        Add-Result (@($repository.directoryNames).Count -gt 0) "registry/${id}/directory-names" 'at least one local directory name is required'
        Add-Result (@($repository.requiredPaths).Count -gt 0) "registry/${id}/required-paths" 'requiredPaths must not be empty'
        Add-Result (@($repository.validationCommands).Count -gt 0) "registry/${id}/validators" 'validationCommands must not be empty'
        Add-Result ($repository.generatedOutputPolicy.tracked -eq $false) "registry/${id}/untracked-output" 'generated output must remain untracked'
        Add-Result ([string]$repository.proofCeiling -match 'only|Only') "registry/${id}/proof-ceiling" 'proof ceiling must explicitly limit claims'

        foreach ($path in @($repository.requiredPaths)) {
            Add-Result (Test-RelativeRepoPath ([string]$path)) "registry/${id}/required-path/${path}" 'required path must be repository-relative'
        }

        foreach ($property in $entrypointProperties) {
            $value = $repository.entrypoints.$property
            if ($property -eq 'codebaseMap') {
                Add-Result (Test-RelativeRepoPath ([string]$value)) "registry/${id}/entrypoint/${property}" 'codebase map must be repository-relative'
            }
            else {
                $values = @($value)
                Add-Result ($values.Count -gt 0) "registry/${id}/entrypoint/${property}" 'entrypoint list must not be empty'
                foreach ($path in $values) {
                    Add-Result (Test-RelativeRepoPath ([string]$path)) "registry/${id}/entrypoint/${property}/${path}" 'entrypoint must be repository-relative'
                }
            }
        }
    }

    $canonical = @($repositories | Where-Object { $_.role -eq 'canonical-root' })
    Add-Result ($canonical.Count -eq 1) 'registry/single-canonical-root' 'exactly one canonical root is required'
    if ($canonical.Count -eq 1) {
        Add-Result ($canonical[0].fullName -eq 'EndeavorEverlasting/AgentSwitchboard') 'registry/canonical-root-identity' 'AgentSwitchboard must be the canonical root'
        foreach ($path in @($canonical[0].requiredPaths)) {
            Add-Result (Test-Path -LiteralPath (Join-Path $RootPath $path)) "registry/self-path/${path}" 'AgentSwitchboard required path is missing on this branch'
        }
    }

    $rawRegistry = Get-Content -LiteralPath (Join-Path $RootPath '.ai/harness/repository-family.registry.json') -Raw
    Add-Result ($rawRegistry -notmatch '(?i)pull/[0-9]+|PR\s*#[0-9]+|\b[a-f0-9]{40}\b') 'registry/no-mutable-pr-state' 'durable registry must not embed PR numbers or commit SHAs'
    Add-Result ($rawRegistry -notmatch '(?i)[A-Z]:\\Users\\|/home/[^/]+/') 'registry/no-machine-paths' 'durable registry must not embed machine-local user paths'
}

if ($null -ne $artifactRegistry) {
    Add-Result ($artifactRegistry.schemaVersion -eq 1) 'artifacts/schema-version' 'expected schemaVersion 1'
    $artifacts = @($artifactRegistry.artifacts)
    Add-Result ($artifacts.Count -eq 4) 'artifacts/count' 'exactly four family artifact roles are required'
    foreach ($artifact in $artifacts) {
        Add-Result ($artifact.tracked -eq $false) "artifacts/$($artifact.artifactId)/untracked" 'family run evidence must remain untracked'
        Add-Result ($artifact.sensitivity -eq 'local-operational') "artifacts/$($artifact.artifactId)/sensitivity" 'unexpected sensitivity class'
    }
}

if ($null -ne $workflow) {
    Add-Result ($workflow.workflowId -eq 'repository-family-intake') 'workflow/id' 'unexpected workflow id'
    Add-Result ($workflow.entrypoint -eq 'scripts/Get-RepositoryFamilyHarnessStatus.ps1') 'workflow/entrypoint' 'unexpected workflow entrypoint'
    Add-Result ($workflow.proofLevel -eq 'read-only-repository-intake') 'workflow/proof-level' 'unexpected workflow proof level'
    foreach ($token in @('clone', 'fetch', 'push', 'merge', 'provider invocation', 'live target mutation')) {
        Add-Result (@($workflow.forbidden) -contains $token) "workflow/forbidden/${token}" 'required forbidden action is missing'
    }
}

$schemaPaths = @(
    '.ai/harness/schemas/repository-family-registry.schema.json',
    '.ai/harness/schemas/run-context.schema.json',
    '.ai/harness/schemas/repository-family-status.schema.json',
    '.ai/harness/schemas/final-handoff.schema.json'
)
foreach ($schemaPath in $schemaPaths) {
    $schema = Read-JsonFile $schemaPath
    if ($null -ne $schema) {
        Add-Result ($schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema') "schema/${schemaPath}/draft" 'schema must use JSON Schema 2020-12'
        Add-Result (-not [string]::IsNullOrWhiteSpace([string]$schema.title)) "schema/${schemaPath}/title" 'schema title is missing'
    }
}

foreach ($scriptPath in @('scripts/Test-RepositoryFamilyHarness.ps1', 'scripts/Get-RepositoryFamilyHarnessStatus.ps1')) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $RootPath $scriptPath),
        [ref]$tokens,
        [ref]$parseErrors
    )
    Add-Result ($parseErrors.Count -eq 0) "powershell/${scriptPath}/parse" ($parseErrors -join '; ')
}

Write-Host 'REPOSITORY FAMILY HARNESS CONTRACT' -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
