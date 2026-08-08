[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$required = @(
    '.ai/agent-contract.json',
    'SKILLS.md',
    'HARNESS.md',
    '.ai/harness/wayfinder-doctrine.policy.json',
    'docs/governance/wayfinder-doctrine.md',
    '.ai/skills/wayfinder/SKILL.md',
    '.ai/skills/research/SKILL.md',
    '.ai/skills/prototype/SKILL.md',
    '.ai/skills/grilling/SKILL.md',
    '.ai/skills/domain-modeling/SKILL.md',
    '.ai/skills/to-spec/SKILL.md',
    '.ai/skills/to-tickets/SKILL.md',
    'tooling/harness/wayfinder/manifest.json',
    'tooling/harness/wayfinder/wayfinder_contract.py',
    'tooling/harness/wayfinder/github_tracker.py',
    'tooling/harness/wayfinder/schemas/decision-ticket.schema.json',
    'tooling/harness/wayfinder/schemas/map.schema.json',
    'tooling/harness/wayfinder/schemas/spec.schema.json',
    'tooling/harness/wayfinder/fixtures/map.json',
    'tooling/harness/wayfinder/fixtures/ticket-research.json',
    'tooling/harness/wayfinder/fixtures/ticket-prototype.json',
    'tooling/harness/wayfinder/fixtures/ticket-grilling.json',
    'tooling/harness/wayfinder/fixtures/ticket-task.json',
    'tooling/harness/wayfinder/fixtures/spec.json',
    'docs/harness/wayfinder.md',
    'tests/test_wayfinder_harness.py',
    'tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/README.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/LICENSE',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/wayfinder/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/research/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/grilling/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/domain-modeling/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/to-spec/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/to-tickets/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/issue-tracker-github.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/issue-tracker-local.md'
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RootPath $_) -PathType Leaf) })
if ($missing.Count -gt 0) {
    throw "Wayfinder harness missing required files:`n - $($missing -join "`n - ")"
}

$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/wayfinder/manifest.json') -Raw | ConvertFrom-Json
if ($manifest.harnessId -ne 'agentswitchboard.wayfinder.v1') { throw 'Unexpected Wayfinder harness id.' }
if ($manifest.authority.doctrine -ne 'docs/governance/wayfinder-doctrine.md') { throw 'Wayfinder doctrine is not registered in the harness manifest.' }
if ($manifest.authority.doctrinePolicy -ne '.ai/harness/wayfinder-doctrine.policy.json') { throw 'Wayfinder doctrine policy is not registered in the harness manifest.' }
if ($manifest.authority.donorRepository -ne 'mattpocock/skills') { throw 'Unexpected Wayfinder donor repository.' }
if ($manifest.authority.donorCommit -ne '84fdeffd12f2ee307994d1eb6feb48173b6e0502') { throw 'Wayfinder donor pin changed without reviewed refresh.' }
if ($manifest.ticketTypes.research.interaction -ne 'afk') { throw 'Research ticket gate must remain AFK.' }
if ($manifest.ticketTypes.prototype.interaction -ne 'hitl') { throw 'Prototype ticket gate must remain HITL.' }
if ($manifest.ticketTypes.grilling.interaction -ne 'hitl') { throw 'Grilling ticket gate must remain HITL.' }
if (@($manifest.ticketTypes.grilling.requiredSkills) -join ',' -ne 'grilling,domain-modeling') { throw 'Grilling must require grilling + domain-modeling.' }
if (-not $manifest.lifecycle.chartStopsBeforeNonResearchResolution) { throw 'Chart mode must stop before non-research ticket resolution.' }
if ($manifest.lifecycle.maxNonResearchResolutionsPerSession -ne 1) { throw 'Wayfinder must limit sessions to one non-research decision resolution.' }
if ($manifest.lifecycle.specLifecycle -ne 'temporary-until-implementation') { throw 'Wayfinder spec lifecycle drifted.' }
if ($manifest.lifecycle.decisionHistoryRetention -ne 'retain tracker decision tickets after spec retirement') { throw 'Decision history retention drifted.' }

$policy = Get-Content -LiteralPath (Join-Path $RootPath '.ai/harness/wayfinder-doctrine.policy.json') -Raw | ConvertFrom-Json
if ($policy.policyId -ne 'agentswitchboard.wayfinder-doctrine.v1') { throw 'Unexpected Wayfinder doctrine policy id.' }
if ($policy.authority.decisionAuthority -ne 'tracker-child-tickets') { throw 'Wayfinder decision authority must remain tracker child tickets.' }
if ($policy.authority.publicPlanRole -ne 'repository-coordination-mirror') { throw 'Public plans must remain Wayfinder coordination mirrors.' }
if ($policy.hitl.humanSpeaksForThemselves -ne $true) { throw 'Wayfinder HITL policy must require the human to speak for themselves.' }
if ($policy.hitl.agentMayInferApproval -ne $false) { throw 'Wayfinder HITL policy must forbid inferred approval.' }
if ($policy.frontier.claimBeforeWork -ne $true) { throw 'Wayfinder frontier policy must require claim-before-work.' }
if ($policy.frontier.outOfScopeBlockerCountsAsResolved -ne $false) { throw 'Out-of-scope blockers must not silently satisfy dependencies.' }
if ($policy.chartMode.nonResearchResolutionAllowed -ne $false) { throw 'Chart mode must not resolve non-research tickets.' }
if ($policy.chartMode.stopAfterChart -ne $true) { throw 'Chart mode must stop after map/ticket charting.' }
if ($policy.specification.lifecycle -ne 'temporary-until-implementation') { throw 'Wayfinder specification lifecycle drifted.' }
if ($policy.specification.primaryDecisionAuthority -ne 'tracker-child-tickets') { throw 'Specifications must not replace tracker decision authority.' }
if ($policy.donorRefresh.policy -ne 'pin-until-reviewed' -or $policy.donorRefresh.autoAdvance -ne $false) { throw 'Wayfinder donor refresh policy drifted.' }

$doctrine = Get-Content -LiteralPath (Join-Path $RootPath 'docs/governance/wayfinder-doctrine.md') -Raw
foreach ($token in @('the human speaks for themselves', 'Decision tickets are not implementation tickets', 'Chart-mode stop doctrine', 'temporary synthesis artifact', 'pin-until-reviewed')) {
    if (-not $doctrine.ToLowerInvariant().Contains($token.ToLowerInvariant())) { throw "Wayfinder governance doctrine missing invariant: $token" }
}

$contract = Get-Content -LiteralPath (Join-Path $RootPath '.ai/agent-contract.json') -Raw | ConvertFrom-Json
if ($contract.entrypoints.wayfinder -ne '.ai/skills/wayfinder/SKILL.md') { throw 'Agent contract does not register the Wayfinder entrypoint.' }
if ($contract.wayfinder.trackerDecisionAuthority -ne $true) { throw 'Agent contract must keep tracker decision authority.' }
if ($contract.wayfinder.publicPlanIsMirror -ne $true) { throw 'Agent contract must keep public plans as Wayfinder mirrors.' }
if ($contract.wayfinder.chartMayResolveNonResearch -ne $false) { throw 'Agent contract must forbid non-research chart resolution.' }
if ($contract.wayfinder.specLifecycle -ne 'temporary-until-implementation') { throw 'Agent contract spec lifecycle drifted.' }

$catalog = Get-Content -LiteralPath (Join-Path $RootPath 'SKILLS.md') -Raw
foreach ($token in @('wayfinder', 'research', 'prototype', 'grilling', 'domain-modeling', 'to-spec', 'to-tickets', 'Decision ticket', 'Implementation ticket')) {
    if (-not $catalog.Contains($token)) { throw "SKILLS.md missing Wayfinder catalog token: $token" }
}

$wayfinderSkill = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/wayfinder/SKILL.md') -Raw
foreach ($token in @('Ticket gates', 'Chart mode', 'Work mode', 'human speaks for themselves', 'to-spec', 'to-tickets', 'Stop.')) {
    if (-not $wayfinderSkill.Contains($token)) { throw "Wayfinder skill missing contract token: $token" }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python is required for the Wayfinder harness validator.' }

& $python.Source -c 'import jsonschema; import sys; sys.exit(0 if jsonschema.__version__.split(".")[:2] == ["4", "26"] else 3)'
if ($LASTEXITCODE -ne 0) {
    throw 'Wayfinder Draft 2020-12 validator dependency is unavailable. Run: python -m pip install --disable-pip-version-check -r tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt'
}

& $python.Source (Join-Path $RootPath 'tests/test_wayfinder_harness.py')
if ($LASTEXITCODE -ne 0) { throw 'Wayfinder Python harness failed.' }

Write-Host 'PASS: ASB Wayfinder harness' -ForegroundColor Green
Write-Host 'Proof ceiling: imported-source integrity, governance doctrine, typed ticket/HITL gates, fixtures, tracker command construction, frontier/spec lifecycle, and offline/hosted contracts only.'
exit 0
