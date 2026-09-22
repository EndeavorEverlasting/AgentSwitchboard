[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Base = 'tooling/harness/operational/external-agent-tooling'
$Required = @(
    "$Base/external-agent-tooling.registry.json",
    "$Base/manifest.json",
    "$Base/codebase-map.json",
    "$Base/artifact-registry.json",
    "$Base/schemas/external-agent-tooling-registry.schema.json",
    "$Base/workflows/tool-intake.workflow.json",
    "$Base/fixtures/valid-source-only.fixture.json",
    "$Base/fixtures/invalid-proof-promotion.fixture.json",
    "$Base/reports/CURRENT_STATE.md",
    'docs/harness/external-agent-tooling-catalog.md',
    'tests/test_external_agent_tooling_catalog.py',
    'scripts/Test-ExternalAgentToolingCatalog.ps1',
    '.github/workflows/external-agent-tooling-catalog.yml'
)
foreach ($Relative in $Required) {
    $Path = Join-Path $RepoRoot $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing external-agent-tooling harness file: $Relative" }
    & git -C $RepoRoot ls-files --error-unmatch -- $Relative *> $null
    if ($LASTEXITCODE -ne 0) { throw "External-agent-tooling file is not tracked: $Relative" }
}

$Registry = Get-Content -LiteralPath (Join-Path $RepoRoot "$Base/external-agent-tooling.registry.json") -Raw | ConvertFrom-Json
$Manifest = Get-Content -LiteralPath (Join-Path $RepoRoot "$Base/manifest.json") -Raw | ConvertFrom-Json
$Schema = Get-Content -LiteralPath (Join-Path $RepoRoot "$Base/schemas/external-agent-tooling-registry.schema.json") -Raw | ConvertFrom-Json
$Workflow = Get-Content -LiteralPath (Join-Path $RepoRoot "$Base/workflows/tool-intake.workflow.json") -Raw | ConvertFrom-Json
$Valid = Get-Content -LiteralPath (Join-Path $RepoRoot "$Base/fixtures/valid-source-only.fixture.json") -Raw | ConvertFrom-Json
$Invalid = Get-Content -LiteralPath (Join-Path $RepoRoot "$Base/fixtures/invalid-proof-promotion.fixture.json") -Raw | ConvertFrom-Json

if ($Registry.schemaVersion -ne 1) { throw 'Unexpected registry schemaVersion.' }
if ($Registry.catalogId -ne 'agentswitchboard.external-agent-tooling.v1') { throw 'Unexpected catalogId.' }
if (@($Registry.entries).Count -ne 45) { throw "Expected 45 catalog entries; found $(@($Registry.entries).Count)." }
if ($Manifest.catalogCount -ne 45) { throw 'Manifest catalogCount drifted.' }

$Ids = @($Registry.entries | ForEach-Object { $_.id })
if (@($Ids | Sort-Object -Unique).Count -ne $Ids.Count) { throw 'Catalog entry ids must be unique.' }
foreach ($Entry in @($Registry.entries)) {
    if ($Entry.verificationRequiredBeforeAdoption -ne $true) { throw "Entry $($Entry.id) bypasses the verification gate." }
    if ($Entry.integrationAuthority -ne 'none') { throw "Entry $($Entry.id) grants integration authority." }
    if ($Entry.capabilityState -ne 'unknown') { throw "Entry $($Entry.id) promotes capability without owning proof." }
    if ($Entry.runtimeProof -ne 'unproved') { throw "Entry $($Entry.id) promotes runtime proof." }
    if ($Entry.trustProof -ne 'unproved') { throw "Entry $($Entry.id) promotes trust proof." }
    if ($Entry.privacyProof -ne 'unproved') { throw "Entry $($Entry.id) promotes privacy proof." }
}

foreach ($Flag in @(
    'sourceClaimsAreFacts','installationAuthorizedByCatalog','providerCallsAuthorizedByCatalog',
    'networkExecutionAuthorizedByCatalog','liveTargetMutationAuthorizedByCatalog',
    'catalogPresenceProvesInstalled','catalogPresenceProvesExecutable','catalogPresenceProvesTrusted',
    'catalogPresenceProvesPrivate','catalogPresenceProvesRuntimeReady'
)) {
    if ($Registry.policy.$Flag -ne $false) { throw "Unsafe catalog policy flag: $Flag" }
}
if ($Registry.policy.capabilityTruthOwner -ne 'CAPABILITIES.md and runtime-specific canonical owners') { throw 'Capability truth owner drifted.' }

$Aider = @($Registry.entries | Where-Object { $_.id -eq 'aider' })
if ($Aider.Count -ne 1 -or @($Aider[0].aliases) -notcontains 'Ader') { throw 'The source spelling Ader must remain preserved as an Aider alias.' }
$DeepSeekClaim = @($Registry.reportedClaims | Where-Object { $_.claimId -eq 'deepseek-prefix-caching-cost' })
if ($DeepSeekClaim.Count -ne 1 -or $DeepSeekClaim[0].reuseAllowedWithoutVerification -ne $false) { throw 'DeepSeek quantitative source claim must remain explicitly unverified for reuse.' }

$ExpectedSteps = @('capture','classify','overlap','verify-upstream','risk-boundary','proof-boundary','disposition','validate')
$ActualSteps = @($Workflow.steps | ForEach-Object { $_.id })
if (($ActualSteps -join '|') -ne ($ExpectedSteps -join '|')) { throw 'Tool intake workflow order drifted.' }

foreach ($Name in @('capabilityState','runtimeProof','trustProof','privacyProof')) {
    if (@($Schema.properties.entries.items.required) -notcontains $Name) { throw "Schema does not require proof-boundary field: $Name" }
}
if ($Valid.capabilityState -ne 'unknown' -or $Valid.runtimeProof -ne 'unproved' -or $Valid.trustProof -ne 'unproved' -or $Valid.privacyProof -ne 'unproved') { throw 'Positive fixture violates source-only proof boundary.' }
if ($Invalid.capabilityState -eq 'unknown' -and $Invalid.runtimeProof -eq 'unproved' -and $Invalid.trustProof -eq 'unproved' -and $Invalid.privacyProof -eq 'unproved') { throw 'Negative proof-promotion fixture no longer reproduces the defect.' }

if ($Manifest.entrypoints.PSObject.Properties['skill']) { throw 'Leaf salvage must not revive historical skill ownership.' }
if ($Manifest.salvage.sourcePullRequest -ne 118 -or $Manifest.salvage.sourceHead -ne '87abb4546ee1ef440897dfd86a49e58dab827ee6') { throw 'PR #118 salvage provenance drifted.' }
if ($Manifest.salvage.deferredSharedRegistration.manifest.key -ne 'externalAgentToolingManifest') { throw 'Deferred shared manifest delta drifted.' }

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $Python) { throw 'Python is required for the portable external-agent-tooling contract.' }
& $Python.Source (Join-Path $RepoRoot 'tests/test_external_agent_tooling_catalog.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'PASS: external agent tooling source-only catalog (45 entries)'
