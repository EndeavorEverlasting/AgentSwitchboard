[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [switch]$CheckDonorHead
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$manifestRelative = 'tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json'
$requirementsRelative = 'tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt'
$pythonContribution = 'tests/test_wayfinder_public_plan_contribution.py'
$pythonHarness = 'tests/test_wayfinder_harness.py'

foreach ($relative in @(
    $manifestRelative,
    'tooling/harness/operational/contributions/cross-repository-contribution.schema.json',
    $requirementsRelative,
    '.ai/skills/wayfinder/SKILL.md',
    '.ai/skills/public-plan-coordination/SKILL.md',
    'plans/schemas/public-plan.schema.json',
    'tooling/harness/wayfinder/manifest.json',
    $pythonContribution,
    $pythonHarness,
    'scripts/Test-WayfinderHarness.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf)) {
        throw "Wayfinder contribution missing required file: $relative"
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $RootPath $manifestRelative) -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'agentswitchboard.cross-repository-contribution.v1') { throw 'Unexpected contribution schema.' }
if ($manifest.contributionId -ne 'mattpocock.wayfinder.asb-adaptation.v2') { throw 'Unexpected contribution id.' }
if ($manifest.status -ne 'adopted') { throw 'Wayfinder contribution is not adopted.' }
if ($manifest.donor.repository -ne 'mattpocock/skills') { throw 'Unexpected donor repository.' }
if ($manifest.donor.commit -ne '84fdeffd12f2ee307994d1eb6feb48173b6e0502') { throw 'Donor pin changed without a reviewed refresh.' }
if ($manifest.donor.license.spdx -ne 'MIT') { throw 'Unexpected donor license.' }
if ($manifest.consumer.repository -ne 'EndeavorEverlasting/AgentSwitchboard') { throw 'Unexpected consumer repository.' }
if ($manifest.consumer.canonicalOwner -ne '.ai/skills/wayfinder/SKILL.md') { throw 'Wayfinder skill must be the adapted orchestration owner.' }
if ($manifest.compatibility.consumerContract -ne 'agentswitchboard.wayfinder.v1+public-plan-mirror-1') { throw 'Unexpected compatibility contract.' }
if ($manifest.compatibility.minimumSkillVersion -ne '1.2.0') { throw 'Unexpected public-plan minimum skill version.' }
if ($manifest.compatibility.staleReferencePolicy -ne 'pin-until-reviewed') { throw 'Unexpected stale-reference policy.' }
if ($manifest.compatibility.autoAdvanceDonor -ne $false) { throw 'Donor reference must never auto-advance.' }

$authoritative = @{}
foreach ($item in @($manifest.donor.authoritativePaths)) { $authoritative[[string]$item.path] = [string]$item.blobSha }
$expected = @{
    'skills/engineering/wayfinder/SKILL.md' = 'e4984ed327e12ba65303f4b5de2eb75c01e99c16'
    'skills/engineering/research/SKILL.md' = '0ba594a07f306479baa67104381f48e209ab6aae'
    'skills/engineering/prototype/SKILL.md' = '094571156140f5993cce8557dc31383c82817f3e'
    'skills/productivity/grilling/SKILL.md' = '95bd01ee9049a7e08120d54af9cd6ceeef282335'
    'skills/engineering/domain-modeling/SKILL.md' = 'd0f7e1a5ccb06a7184056ff9af02b67bc77f9dda'
    'skills/engineering/to-spec/SKILL.md' = '3fd64959895b7eb095a13d797e1c7544f1f08c8f'
    'skills/engineering/to-tickets/SKILL.md' = '96deac51d4391a3f691478d48f85f43261516c08'
    'skills/engineering/setup-matt-pocock-skills/issue-tracker-github.md' = 'bf595e2470597fcd316d8b316ad861f05ed630be'
    'skills/engineering/setup-matt-pocock-skills/issue-tracker-local.md' = 'fbda5e04217fcdb73b513720f513abbe0b3014ed'
    'LICENSE' = 'f1dd2c09108dde1a5f56097cee8461b3ea834499'
}
foreach ($path in $expected.Keys) {
    if ($authoritative[$path] -ne $expected[$path]) { throw "Donor authority pin mismatch: $path" }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python is required for Wayfinder contribution validation.' }

& $python.Source -c 'import jsonschema; import sys; sys.exit(0 if jsonschema.__version__.split(".")[:2] == ["4", "26"] else 3)'
if ($LASTEXITCODE -ne 0) {
    throw "jsonschema 4.26.x is required. Run: python -m pip install --disable-pip-version-check -r $requirementsRelative"
}

foreach ($test in @($pythonHarness, $pythonContribution)) {
    & $python.Source (Join-Path $RootPath $test)
    if ($LASTEXITCODE -ne 0) { throw "Wayfinder Python validator failed: $test" }
}

if ($CheckDonorHead) {
    $lines = @(& git ls-remote https://github.com/mattpocock/skills.git refs/heads/main 2>&1)
    if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) { throw 'Unable to read donor main for stale-reference check.' }
    $head = ([string]$lines[0] -split '\s+')[0].Trim().ToLowerInvariant()
    if ($head -eq $manifest.donor.commit) {
        Write-Host "[INFO] Donor main still matches reviewed pin: $head"
    }
    else {
        Write-Host "[INFO] Donor main advanced to $head; ASB remains pinned to $($manifest.donor.commit) until a reviewed refresh."
    }
}

Write-Host 'PASS: Wayfinder cross-repository contribution' -ForegroundColor Green
Write-Host "Manifest: $manifestRelative"
Write-Host 'Proof ceiling: pinned donor/source snapshots, ASB adaptation contracts, public-plan mirror, schemas and offline/hosted validators only; no live tracker or HITL decision proof.'
exit 0
