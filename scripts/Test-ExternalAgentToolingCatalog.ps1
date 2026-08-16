[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RegistryPath = Join-Path $RepoRoot 'tooling/harness/operational/external-agent-tooling/external-agent-tooling.registry.json'
$ManifestPath = Join-Path $RepoRoot 'tooling/harness/operational/external-agent-tooling/manifest.json'
$WorkflowPath = Join-Path $RepoRoot 'tooling/harness/operational/external-agent-tooling/workflows/tool-intake.workflow.json'
$SkillPath = Join-Path $RepoRoot '.ai/skills/external-agent-tooling-intake/SKILL.md'
$GuidePath = Join-Path $RepoRoot 'docs/harness/external-agent-tooling-catalog.md'
$StatePath = Join-Path $RepoRoot 'tooling/harness/operational/external-agent-tooling/reports/CURRENT_STATE.md'

$Required = @($RegistryPath, $ManifestPath, $WorkflowPath, $SkillPath, $GuidePath, $StatePath)
foreach ($Path in $Required) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing external-agent-tooling harness file: $Path"
    }
}

$Registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw | ConvertFrom-Json

if ($Registry.schemaVersion -ne 1) { throw 'Unexpected registry schemaVersion.' }
if ($Registry.catalogId -ne 'agentswitchboard.external-agent-tooling.v1') { throw 'Unexpected catalogId.' }
if (@($Registry.entries).Count -ne 45) { throw "Expected 45 catalog entries; found $(@($Registry.entries).Count)." }
if ($Manifest.catalogCount -ne 45) { throw 'Manifest catalogCount drifted.' }

$Ids = @($Registry.entries | ForEach-Object { $_.id })
if (@($Ids | Sort-Object -Unique).Count -ne $Ids.Count) { throw 'Catalog entry ids must be unique.' }

foreach ($Entry in @($Registry.entries)) {
    if ($Entry.verificationRequiredBeforeAdoption -ne $true) { throw "Entry $($Entry.id) bypasses the verification gate." }
    if ($Entry.integrationAuthority -ne 'none') { throw "Entry $($Entry.id) grants integration authority." }
}

foreach ($Flag in @(
    'sourceClaimsAreFacts',
    'installationAuthorizedByCatalog',
    'providerCallsAuthorizedByCatalog',
    'networkExecutionAuthorizedByCatalog',
    'liveTargetMutationAuthorizedByCatalog'
)) {
    if ($Registry.policy.$Flag -ne $false) { throw "Unsafe catalog policy flag: $Flag" }
}

$Aider = @($Registry.entries | Where-Object { $_.id -eq 'aider' })
if ($Aider.Count -ne 1 -or @($Aider[0].aliases) -notcontains 'Ader') {
    throw 'The source spelling Ader must remain preserved as an Aider alias.'
}

$DeepSeekClaim = @($Registry.reportedClaims | Where-Object { $_.claimId -eq 'deepseek-prefix-caching-cost' })
if ($DeepSeekClaim.Count -ne 1 -or $DeepSeekClaim[0].reuseAllowedWithoutVerification -ne $false) {
    throw 'DeepSeek quantitative source claim must remain explicitly unverified for reuse.'
}

$ExpectedSteps = @('capture','classify','overlap','verify-upstream','risk-boundary','disposition','validate')
$ActualSteps = @($Workflow.steps | ForEach-Object { $_.id })
if (($ActualSteps -join '|') -ne ($ExpectedSteps -join '|')) { throw 'Tool intake workflow order drifted.' }

Write-Host 'PASS: external agent tooling catalog (45 entries)'
