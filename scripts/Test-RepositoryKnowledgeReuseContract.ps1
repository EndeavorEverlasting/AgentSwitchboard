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

$policyText = Read-Required '.ai/harness/harness-doctrine.policy.json'
$templatePolicyText = Read-Required 'templates/repository-agent-contract/.ai/harness/harness-doctrine.policy.json'
$doctrineText = Read-Required 'docs/governance/harness-doctrine.md'
$templateDoctrineText = Read-Required 'templates/repository-agent-contract/docs/governance/harness-doctrine.md'
$agentsText = Read-Required 'AGENTS.md'
$templateAgentsText = Read-Required 'templates/repository-agent-contract/AGENTS.md'
$repoIntakeText = Read-Required '.ai/skills/repo-intake/SKILL.md'
$architectureText = Read-Required 'docs/architecture/agentic-software-factory.md'

$requiredOrder = @(
    'repository-law-and-ownership',
    'architecture-adrs-specifications-external-contracts',
    'manifests-registries-schemas-workflow-maps-context-routes',
    'skills-validators-tests-plans-reports-generated-evidence',
    'implementation-helpers-and-relevant-history',
    'repository-family-shared-doctrine',
    'approved-external-or-drive-authoritative-gap-evidence'
)
$requiredEvidence = @(
    'question',
    'surfacesSearched',
    'canonicalOwnerFound',
    'reusableTruth',
    'unresolvedGap',
    'externalSearchNeeded'
)

foreach ($pair in @(
    @{ Name = 'root'; Text = $policyText },
    @{ Name = 'template'; Text = $templatePolicyText }
)) {
    try {
        $policy = $pair.Text | ConvertFrom-Json
        $reuse = $policy.knowledgeReuse
        Check ([bool]$reuse.repositoryKnowledgeIsCompiledState) "policy/$($pair.Name)/compiled-state" 'compiled-state law missing'
        Check ([bool]$reuse.requireLocalCanonicalSearchBeforeInvention) "policy/$($pair.Name)/local-first" 'local canonical search not required'
        Check ([bool]$reuse.requireUnresolvedGapBeforeExternalResearch) "policy/$($pair.Name)/gap-before-external" 'unresolved gap not required before external research'
        Check ([bool]$reuse.externalResearchCannotOverrideRepositoryAuthority) "policy/$($pair.Name)/authority" 'external evidence may override repository authority'
        Check ([bool]$reuse.preferDeterministicHydrationForRepeatedKnownState) "policy/$($pair.Name)/hydration" 'deterministic hydration preference missing'
        Check ((@($reuse.discoveryOrder) -join '|') -eq ($requiredOrder -join '|')) "policy/$($pair.Name)/order" 'canonical discovery order changed'
        foreach ($field in $requiredEvidence) {
            Check (@($reuse.requiredEvidenceFields) -contains $field) "policy/$($pair.Name)/evidence/$field" 'anti-rediscovery evidence field missing'
        }
    }
    catch {
        [void]$failures.Add("policy/$($pair.Name)/json`: $($_.Exception.Message)")
    }
}

foreach ($pair in @(
    @{ Name = 'root-doctrine'; Text = $doctrineText },
    @{ Name = 'template-doctrine'; Text = $templateDoctrineText },
    @{ Name = 'root-agents'; Text = $agentsText },
    @{ Name = 'template-agents'; Text = $templateAgentsText }
)) {
    foreach ($token in @('Repository knowledge is compiled state', 'unresolved gap', 'external research')) {
        Check ($pair.Text.Contains($token, [StringComparison]::OrdinalIgnoreCase)) "docs/$($pair.Name)/$token" 'required anti-rediscovery doctrine missing'
    }
}

foreach ($token in @(
    'anti-rediscovery record',
    'canonical owner found',
    'reusable truth',
    'unresolved gap',
    'external search needed',
    're-derive repository-owned principles',
    'Deterministic hydration'
)) {
    Check ($repoIntakeText.Contains($token, [StringComparison]::OrdinalIgnoreCase)) "repo-intake/$token" 'repo-intake does not operationalize the doctrine'
}

foreach ($token in @(
    'Knowledge reuse and bottleneck discipline',
    'known-state hydration',
    'unresolved reasoning',
    'Search local truth before inventing or searching outward',
    'Expert insight ledger boundary',
    'Drive-authoritative research inbox'
)) {
    Check ($architectureText.Contains($token, [StringComparison]::OrdinalIgnoreCase)) "architecture/$token" 'architecture linkage missing'
}

Check (-not $architectureText.Contains('docs.google.com/spreadsheets/', [StringComparison]::OrdinalIgnoreCase)) 'privacy/no-drive-url' 'tracked architecture contains a private Drive spreadsheet URL'
Check (-not $architectureText.Contains('service-account JSON', [StringComparison]::OrdinalIgnoreCase)) 'privacy/no-credential-payload-guidance' 'architecture should not carry credential payload material'

Write-Host 'REPOSITORY KNOWLEDGE REUSE CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
