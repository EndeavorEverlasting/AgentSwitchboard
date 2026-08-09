[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath
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
    '.ai/skills/wayfinder-runtime-binding/SKILL.md',
    '.ai/skills/research/SKILL.md',
    '.ai/skills/prototype/SKILL.md',
    '.ai/skills/grilling/SKILL.md',
    '.ai/skills/domain-modeling/SKILL.md',
    '.ai/skills/to-spec/SKILL.md',
    '.ai/skills/to-tickets/SKILL.md',
    'tooling/harness/wayfinder/manifest.json',
    'tooling/harness/wayfinder/codebase-map.json',
    'tooling/harness/wayfinder/workflows/runtime-validation.workflow.json',
    'tooling/harness/wayfinder/artifact-registry.json',
    'tooling/harness/wayfinder/validator-registry.json',
    'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1',
    'tooling/harness/wayfinder/hooks/Invoke-WayfinderPreCommit.ps1',
    'tooling/harness/wayfinder/templates/operator-report.template.md',
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
    'tests/test_wayfinder_runtime_binding_contract.py',
    'tests/test_wayfinder_harness.py',
    'scripts/Test-WayfinderPythonBinding.ps1',
    'scripts/Test-WayfinderHarnessCompleteness.ps1',
    'tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/README.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/LICENSE',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/wayfinder/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/research/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/LOGIC.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/UI.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/grilling/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/domain-modeling/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/domain-modeling/CONTEXT-FORMAT.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/domain-modeling/ADR-FORMAT.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/to-spec/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/to-tickets/SKILL.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/issue-tracker-github.md',
    'third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/issue-tracker-local.md'
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RootPath $_) -PathType Leaf) })
if ($missing.Count -gt 0) { throw "Wayfinder harness missing required files:`n - $($missing -join "`n - ")" }

$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/wayfinder/manifest.json') -Raw | ConvertFrom-Json
if ($manifest.harnessId -ne 'agentswitchboard.wayfinder.v1') { throw 'Unexpected Wayfinder harness id.' }
if ($manifest.authority.doctrine -ne 'docs/governance/wayfinder-doctrine.md') { throw 'Wayfinder doctrine is not registered.' }
if ($manifest.runtimeBinding.resolver -ne 'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1') { throw 'Wayfinder runtime binding resolver is not registered.' }
if (-not $manifest.runtimeBinding.failClosedExplicit) { throw 'Explicit runtime binding must fail closed.' }
if ($manifest.components.codebaseMap -ne 'tooling/harness/wayfinder/codebase-map.json') { throw 'Wayfinder codebase map is not registered.' }
if ($manifest.components.artifactRegistry -ne 'tooling/harness/wayfinder/artifact-registry.json') { throw 'Wayfinder artifact registry is not registered.' }
if ($manifest.components.validatorRegistry -ne 'tooling/harness/wayfinder/validator-registry.json') { throw 'Wayfinder validator registry is not registered.' }
if ($manifest.skills.runtimeBinding -ne '.ai/skills/wayfinder-runtime-binding/SKILL.md') { throw 'Wayfinder runtime binding skill is not registered.' }
if ($manifest.ticketTypes.research.interaction -ne 'afk') { throw 'Research ticket gate must remain AFK.' }
if ($manifest.ticketTypes.prototype.interaction -ne 'hitl') { throw 'Prototype ticket gate must remain HITL.' }
if ($manifest.ticketTypes.grilling.interaction -ne 'hitl') { throw 'Grilling ticket gate must remain HITL.' }
if (@($manifest.ticketTypes.grilling.requiredSkills) -join ',' -ne 'grilling,domain-modeling') { throw 'Grilling must require grilling + domain-modeling.' }
if (-not $manifest.lifecycle.chartStopsBeforeNonResearchResolution) { throw 'Chart mode must stop before non-research ticket resolution.' }
if ($manifest.lifecycle.maxNonResearchResolutionsPerSession -ne 1) { throw 'Wayfinder must limit sessions to one non-research decision resolution.' }
if ($manifest.lifecycle.specLifecycle -ne 'temporary-until-implementation') { throw 'Wayfinder spec lifecycle drifted.' }

$policy = Get-Content -LiteralPath (Join-Path $RootPath '.ai/harness/wayfinder-doctrine.policy.json') -Raw | ConvertFrom-Json
if ($policy.hitl.humanSpeaksForThemselves -ne $true) { throw 'Wayfinder HITL policy must require the human to speak for themselves.' }
if ($policy.hitl.agentMayInferApproval -ne $false) { throw 'Wayfinder HITL policy must forbid inferred approval.' }
if ($policy.frontier.claimBeforeWork -ne $true) { throw 'Wayfinder frontier policy must require claim-before-work.' }
if ($policy.frontier.outOfScopeBlockerCountsAsResolved -ne $false) { throw 'Out-of-scope blockers must not silently satisfy dependencies.' }
if ($policy.chartMode.nonResearchResolutionAllowed -ne $false) { throw 'Chart mode must not resolve non-research tickets.' }
if ($policy.specification.lifecycle -ne 'temporary-until-implementation') { throw 'Wayfinder specification lifecycle drifted.' }

$contract = Get-Content -LiteralPath (Join-Path $RootPath '.ai/agent-contract.json') -Raw | ConvertFrom-Json
if ($contract.entrypoints.wayfinder -ne '.ai/skills/wayfinder/SKILL.md') { throw 'Agent contract does not register Wayfinder.' }

$wayfinderSkill = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/wayfinder/SKILL.md') -Raw
foreach ($token in @('Ticket gates', 'Chart mode', 'Work mode', 'human speaks for themselves', 'to-spec', 'to-tickets', 'Stop.')) {
    if (-not $wayfinderSkill.Contains($token)) { throw "Wayfinder skill missing contract token: $token" }
}

$prototypeSkill = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/prototype/SKILL.md') -Raw
foreach ($token in @('prototype/LOGIC.md', 'prototype/UI.md')) {
    if (-not $prototypeSkill.Contains($token)) { throw "Prototype skill missing pinned companion source: $token" }
}
$domainSkill = Get-Content -LiteralPath (Join-Path $RootPath '.ai/skills/domain-modeling/SKILL.md') -Raw
foreach ($token in @('domain-modeling/CONTEXT-FORMAT.md', 'domain-modeling/ADR-FORMAT.md')) {
    if (-not $domainSkill.Contains($token)) { throw "Domain-modeling skill missing pinned companion source: $token" }
}

. (Join-Path $RootPath 'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1')
$binding = Resolve-WayfinderPython -PythonPath $PythonPath -RootPath $RootPath
Write-Host "[INFO] Wayfinder Python source: $($binding.Source)"
Write-Host "[INFO] Wayfinder Python: $($binding.Path)"
Write-Host "[INFO] Wayfinder Python version: $($binding.Version)"

& $binding.Path -c 'import importlib.metadata as m,sys; sys.exit(0 if m.version("jsonschema").split(".")[:2] == ["4", "26"] else 3)'
if ($LASTEXITCODE -ne 0) {
    throw "jsonschema 4.26.x is required in the bound interpreter: $($binding.Path). Install with: `"$($binding.Path)`" -m pip install --disable-pip-version-check -r tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt"
}

& $binding.Path (Join-Path $RootPath 'tests/test_wayfinder_runtime_binding_contract.py')
if ($LASTEXITCODE -ne 0) { throw 'Wayfinder runtime-binding static contract failed.' }
& $binding.Path (Join-Path $RootPath 'tests/test_wayfinder_harness.py')
if ($LASTEXITCODE -ne 0) { throw 'Wayfinder Python harness failed.' }

Write-Host 'PASS: ASB Wayfinder harness' -ForegroundColor Green
Write-Host 'Proof ceiling: imported-source integrity, scoped harness completeness registration, deterministic runtime binding, typed ticket/HITL gates, fixtures, tracker command construction, frontier/spec lifecycle, and offline/hosted contracts only.'
exit 0
