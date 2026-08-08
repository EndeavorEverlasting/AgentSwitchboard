[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [switch]$CheckDonorHead
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$Message = ''
    )
    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $Message")
    }
}

function Read-Json {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required/$RelativePath`: missing")
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        [void]$failures.Add("json/$RelativePath`: $($_.Exception.Message)")
        return $null
    }
}

$manifestRelative = 'tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json'
$schemaRelative = 'tooling/harness/operational/contributions/cross-repository-contribution.schema.json'
$skillRelative = '.ai/skills/public-plan-coordination/SKILL.md'
$planSchemaRelative = 'plans/schemas/public-plan.schema.json'
$templateSkillRelative = 'templates/repository-agent-contract/.ai/skills/public-plan-coordination/SKILL.md'
$templatePlanSchemaRelative = 'templates/repository-agent-contract/plans/schemas/public-plan.schema.json'

foreach ($relative in @(
    $manifestRelative,
    $schemaRelative,
    $skillRelative,
    $planSchemaRelative,
    $templateSkillRelative,
    $templatePlanSchemaRelative,
    'plans/README.md',
    'templates/repository-agent-contract/plans/README.md',
    'tests/test_wayfinder_public_plan_contribution.py'
)) {
    Add-Check -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) -Name "required/$relative" -Message 'file is missing'
}

$manifest = Read-Json -RelativePath $manifestRelative
$contributionSchema = Read-Json -RelativePath $schemaRelative
$planSchema = Read-Json -RelativePath $planSchemaRelative
$templatePlanSchema = Read-Json -RelativePath $templatePlanSchemaRelative

if ($manifest) {
    Add-Check -Passed ($manifest.schema -eq 'agentswitchboard.cross-repository-contribution.v1') -Name 'manifest/schema' -Message 'unexpected manifest schema'
    Add-Check -Passed ($manifest.status -eq 'adopted') -Name 'manifest/status' -Message 'contribution is not adopted'
    Add-Check -Passed ($manifest.donor.repository -eq 'mattpocock/skills') -Name 'donor/repository' -Message 'unexpected donor repository'
    Add-Check -Passed ($manifest.donor.commit -eq '84fdeffd12f2ee307994d1eb6feb48173b6e0502') -Name 'donor/commit' -Message 'pinned donor commit changed without reviewed refresh'
    Add-Check -Passed ($manifest.donor.license.spdx -eq 'MIT') -Name 'donor/license' -Message 'unexpected donor license'
    Add-Check -Passed ($manifest.consumer.repository -eq 'EndeavorEverlasting/AgentSwitchboard') -Name 'consumer/repository' -Message 'unexpected consumer repository'
    Add-Check -Passed ($manifest.consumer.canonicalOwner -eq $skillRelative) -Name 'consumer/canonical-owner' -Message 'public-plan skill is not the canonical owner'
    Add-Check -Passed ($manifest.compatibility.consumerContract -eq 'agentswitchboard.public-plan.v1+decision-frontier-1') -Name 'compatibility/contract' -Message 'unexpected consumer contract'
    Add-Check -Passed ($manifest.compatibility.minimumSkillVersion -eq '1.1.0') -Name 'compatibility/skill-version' -Message 'unexpected minimum skill version'
    Add-Check -Passed ($manifest.compatibility.changeKind -eq 'additive') -Name 'compatibility/additive' -Message 'decision-frontier contribution must remain additive'
    Add-Check -Passed ($manifest.compatibility.staleReferencePolicy -eq 'pin-until-reviewed') -Name 'compatibility/stale-policy' -Message 'pinned donor must require reviewed refresh'
    Add-Check -Passed ($manifest.compatibility.autoAdvanceDonor -eq $false) -Name 'compatibility/no-auto-advance' -Message 'donor reference must not auto-advance'

    $authoritative = @{}
    foreach ($item in @($manifest.donor.authoritativePaths)) {
        $authoritative[[string]$item.path] = [string]$item.blobSha
    }
    Add-Check -Passed ($authoritative['skills/engineering/wayfinder/SKILL.md'] -eq 'e4984ed327e12ba65303f4b5de2eb75c01e99c16') -Name 'donor/wayfinder-blob' -Message 'Wayfinder blob pin changed'
    Add-Check -Passed ($authoritative['skills/engineering/wayfinder/agents/openai.yaml'] -eq 'b37544751e0570f9df8de6c02aef238de8c3e1e0') -Name 'donor/openai-blob' -Message 'Wayfinder OpenAI metadata blob pin changed'
    Add-Check -Passed ($authoritative['LICENSE'] -eq 'f1dd2c09108dde1a5f56097cee8461b3ea834499') -Name 'donor/license-blob' -Message 'donor license blob pin changed'

    $classes = @($manifest.classifications | ForEach-Object { [string]$_.classification })
    foreach ($class in @('portable-harness','reusable-skill','adapter','reference-only-doctrine','domain-specific-rejected')) {
        Add-Check -Passed ($classes -contains $class) -Name "classification/$class" -Message 'required contribution classification is absent'
    }
    $badRejected = @($manifest.classifications | Where-Object { $_.classification -eq 'domain-specific-rejected' -and $_.disposition -ne 'reject' })
    Add-Check -Passed ($badRejected.Count -eq 0) -Name 'classification/rejected-remains-rejected' -Message 'domain-specific candidate was adopted'
}

if ($contributionSchema) {
    Add-Check -Passed ($contributionSchema.additionalProperties -eq $false) -Name 'schema/contribution-closed' -Message 'contribution schema must fail closed'
    Add-Check -Passed ($contributionSchema.properties.compatibility.properties.autoAdvanceDonor.const -eq $false) -Name 'schema/no-auto-advance' -Message 'schema must forbid automatic donor advancement'
}

foreach ($schemaPair in @(
    @{ Name = 'consumer'; Value = $planSchema },
    @{ Name = 'template'; Value = $templatePlanSchema }
)) {
    if ($schemaPair.Value) {
        $mode = $schemaPair.Value.properties.coordinationMode
        Add-Check -Passed ($null -ne $mode) -Name "plan-schema/$($schemaPair.Name)/mode" -Message 'coordinationMode is missing'
        if ($mode) {
            Add-Check -Passed ($mode.additionalProperties -eq $false) -Name "plan-schema/$($schemaPair.Name)/closed" -Message 'decision-frontier mode must fail closed'
            Add-Check -Passed ($mode.properties.kind.const -eq 'decision-frontier') -Name "plan-schema/$($schemaPair.Name)/kind" -Message 'unexpected mode kind'
            Add-Check -Passed ($mode.properties.executionAllowed.const -eq $false) -Name "plan-schema/$($schemaPair.Name)/no-execution" -Message 'decision-frontier mode must not execute'
        }
    }
}

$skillPath = Join-Path $RootPath $skillRelative
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($token in @(
        'version: 1.1.0',
        '## Decision-frontier mode',
        'Destination first',
        'Decision tasks, not build slices',
        'Frontier is derived, not stored twice',
        'Fog remains coarse',
        'executionAllowed',
        'pin-until-reviewed'
    )) {
        Add-Check -Passed ($skill.Contains($token)) -Name "skill/$token" -Message 'required decision-frontier contract token is missing'
    }
}

$templateSkillPath = Join-Path $RootPath $templateSkillRelative
if (Test-Path -LiteralPath $templateSkillPath -PathType Leaf) {
    $templateSkill = Get-Content -LiteralPath $templateSkillPath -Raw
    foreach ($token in @('decision-frontier','derive the frontier','executionAllowed')) {
        Add-Check -Passed ($templateSkill.Contains($token)) -Name "template-skill/$token" -Message 'template did not inherit decision-frontier semantics'
    }
}

if ($CheckDonorHead -and $manifest) {
    $remote = 'https://github.com/mattpocock/skills.git'
    $lines = @(& git ls-remote $remote refs/heads/main 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -or $lines.Count -eq 0) {
        [void]$failures.Add("donor/head-check`: git ls-remote failed with exit code $exitCode")
    }
    else {
        $head = ([string]$lines[0] -split '\s+')[0].Trim().ToLowerInvariant()
        Add-Check -Passed ($head -match '^[0-9a-f]{40}$') -Name 'donor/head-shape' -Message 'remote donor head is not a commit SHA'
        if ($head -eq [string]$manifest.donor.commit) {
            Write-Host "[INFO] Donor main still matches the reviewed pin: $head"
        }
        else {
            Write-Host "[INFO] Donor main advanced to $head; reviewed pin remains $($manifest.donor.commit). Open a refresh sprint before changing adopted semantics."
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: Wayfinder public-plan contribution ($($passes.Count) pass, $($failures.Count) fail)" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Wayfinder public-plan contribution ($($passes.Count) checks)" -ForegroundColor Green
Write-Host "Manifest: $manifestRelative"
Write-Host 'Proof ceiling: pinned donor references and consumer contract/adapter validation only; no donor runtime, child-repo adoption, decision quality, or execution proof.'
exit 0
