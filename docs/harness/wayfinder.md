# ASB Wayfinder Harness

Wayfinder is ASB's ambiguity-resolution workflow for work that is too large or uncertain for one bounded session. Its donor lineage is pinned in `tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json`; imported donor files are provenance evidence, not ASB runtime authority.

The harness exists to move decisions and proof out of transient model context and into typed, inspectable repository/tracker artifacts with deterministic gates.

## Fresh-agent entry

Read in this order:

1. `AGENTS.md` — repository governance (read-only for this harness lane).
2. `HARNESS.md` — repository operational harness.
3. `tooling/harness/wayfinder/codebase-map.json` — Wayfinder structure, commands, and traps.
4. `tooling/harness/wayfinder/manifest.json` — scoped ownership and proof ceiling.
5. `tooling/harness/wayfinder/workflows/runtime-validation.workflow.json` — cross-shell validation workflow.
6. `tooling/harness/wayfinder/validator-registry.json` — owning validation order.
7. `tooling/harness/wayfinder/artifact-registry.json` — canonical artifacts and generation rules.

## When to use Wayfinder

Use Wayfinder when the destination requires more than one bounded session **and** important unresolved decisions/fog prevent a safe executable route. If the route is already clear, use the normal bounded sprint/public-plan workflow instead.

## Authority map

| Surface | Owns | Does not own |
|---|---|---|
| `.ai/skills/wayfinder/SKILL.md` | Wayfinder procedure and ticket routing | tracker state, human decisions, implementation |
| tracker map | low-resolution destination/fog/scope/decision pointers | full decision bodies |
| tracker child ticket | exact question, blockers, claim, resolution/assets | destination implementation slices |
| `plans/` public plan | repository ownership/collision/delivery/proof mirror | Wayfinder question/answer store |
| temporary spec | synthesis of settled decisions | primary decision rationale |
| `to-tickets` / bounded sprint | implementation after clarity | ambiguity decisions |
| `third_party/mattpocock-skills/<commit>/` | immutable donor evidence | ASB runtime behavior |

A decision has one primary owner. The map/public plan may link or gist a ticket, but must not duplicate its detailed answer.

## Ticket gates

- **Research — AFK:** use `research`; require a findings artifact and primary-source evidence.
- **Prototype — HITL:** use `prototype`; require a runnable throwaway artifact and an observed human verdict. Logic/state uncertainty follows pinned `prototype/LOGIC.md`; visual/layout uncertainty follows pinned `prototype/UI.md`.
- **Grilling — HITL:** use `grilling` + `domain-modeling`; actual human answers are required. Domain context/ADR formatting follows the pinned companion files.
- **Task — AFK/HITL:** leave open until the prerequisite action actually happened.

Chart mode stops before non-research resolution. A normal work session resolves at most one non-research decision ticket.

## Runtime/interpreter binding

Wayfinder validation crosses Python and PowerShell. **Never** install `jsonschema` with one Python and then let a nested PowerShell validator discover a different ambient `python`.

Canonical resolver: `tooling/harness/wayfinder/Resolve-WayfinderPython.ps1`.

Precedence:

1. explicit `-PythonPath`;
2. `ASB_WAYFINDER_PYTHON`;
3. active `VIRTUAL_ENV`;
4. repository `.venv`;
5. PATH (`python`, then `python3`).

An invalid explicit path or explicit environment override fails closed; it never silently falls back. After successful execution, `sys.executable` is the canonical interpreter identity. On Windows, short-path expansion, junctions, redirects, case differences, or spelling normalization are informational rather than a failure by themselves.

### Safe isolated Windows validation

```powershell
$Venv = Join-Path $env:TEMP 'asb-wayfinder-proof-venv'
python -m venv $Venv
$Py = Join-Path $Venv 'Scripts\python.exe'
& $Py -m pip install --disable-pip-version-check -r tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt
& $Py tests/test_wayfinder_runtime_binding_contract.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderPythonBinding.ps1 -PythonPath $Py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderHarnessCompleteness.ps1 -PythonPath $Py
& $Py tests/test_wayfinder_companion_source_integrity.py
& $Py tests/test_wayfinder_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderHarness.ps1 -PythonPath $Py
& $Py tests/test_wayfinder_public_plan_contribution.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderPublicPlanContribution.ps1 -PythonPath $Py
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
git diff --check
```

The same bound interpreter must be passed to every nested Wayfinder PowerShell validator.

## Harness components

- **Codebase map:** `tooling/harness/wayfinder/codebase-map.json`
- **Workflow spec:** `tooling/harness/wayfinder/workflows/runtime-validation.workflow.json`
- **Artifact registry:** `tooling/harness/wayfinder/artifact-registry.json`
- **Validator registry:** `tooling/harness/wayfinder/validator-registry.json`
- **Runtime resolver:** `tooling/harness/wayfinder/Resolve-WayfinderPython.ps1`
- **Optional pre-commit helper:** `tooling/harness/wayfinder/hooks/Invoke-WayfinderPreCommit.ps1` (never installed implicitly)
- **Scoped skills:** `.ai/skills/wayfinder*` plus typed ticket skills
- **Operator report template:** `tooling/harness/wayfinder/templates/operator-report.template.md`
- **Completeness check:** `scripts/Test-WayfinderHarnessCompleteness.ps1`
- **Hosted validation:** `.github/workflows/wayfinder-public-plan-contribution.yml`

Generated runtime evidence belongs under an OS temporary directory and remains untracked unless a deliberate fixture is being added. Never place secrets, auth/device codes, or private live-target data in reports.

## Failure handling

Run owning validators first and stop at the first real contract failure. Repair the owning harness surface before broader checks. Do not weaken a validator merely to accept a known failure. Presentation-only assertions should normalize Markdown before checking semantics. Do not confuse a Windows path normalization notice with a Python dependency failure.

## Handoff

Use `tooling/harness/wayfinder/templates/operator-report.template.md`. Record exact repository/ref/HEAD, bound interpreter path/version, focused and broader validator outcomes, working/broken/missing state, proof ceiling, and one owner/dependency-specific executable next action.

## Proof ceiling

Green static/hosted validation proves tracked harness completeness, donor/source integrity, interpreter continuity, schemas, deterministic ticket/HITL gates, frontier/spec algorithms, tracker command construction, and public-plan separation.

It does **not** prove live GitHub sub-issue/dependency/label permissions, actual ticket mutation, human HITL participation, research correctness beyond evidence, prototype usefulness, destination implementation, merge/deployment, or operator acceptance. Those require their owning live/runtime artifacts.
