# Pi Operational Harness

AgentSwitchboard treats Pi as an execution adapter beneath repository governance, workflow selection, evidence policy, and branch ownership. This harness does not install Pi and does not assume that a local endpoint, extension, provider, or model is safe or available.

## What is working

- A fresh agent can start at `AGENTS.md`, `CODEBASE_MAP.md`, and `.ai/harness/manifest.json`, then follow the Pi-specific codebase map.
- Task intake selects exactly one route: single-agent, opinion fusion, autovalidation, or blocked.
- Opinion fusion separates architect, builder, adjudicator, and designated-writer responsibilities.
- Autovalidation freezes architect-owned acceptance gates before builder mutation.
- Every multi-agent route requires one writer per branch, attributed execution identity, explicit limits, local-only artifacts, and a proof ceiling.
- A repository-owned validator proves the component set is present, tracked, parseable, centrally registered, and free of known unverified install/API shortcuts.
- The opt-in pre-commit script runs focused contracts and rejects generated Pi runtime evidence from staged changes.
- Windows and Linux CI run the focused PowerShell and dependency-free Python contracts.

## What remains blocked

- Pi is not installed or invoked by repository validation.
- No Pi extension API is treated as stable until an exact upstream version is pinned and verified.
- No local or hosted provider is configured by this harness.
- No endpoint is classified private merely because it resolves to `localhost`.
- No fusion quality, model independence, autovalidation effectiveness, provider response, or committed delivery is claimed.
- No global Pi configuration, implicit Git hook, authentication, merge, deployment, or live-target mutation is allowed.

## Repository surfaces

| Surface | Path |
|---|---|
| Pi codebase map | `tooling/pi/harness/codebase-map.json` |
| Adapter registry | `tooling/pi/harness/pi-adapter.registry.json` |
| Task intake | `tooling/pi/harness/workflows/task-intake.workflow.json` |
| Opinion fusion | `tooling/pi/harness/workflows/opinion-fusion.workflow.json` |
| Autovalidation | `tooling/pi/harness/workflows/autovalidate.workflow.json` |
| Artifact registry | `tooling/pi/harness/artifact-registry.json` |
| Artifact schemas | `tooling/pi/harness/schemas/pi-harness-contracts.schema.json` |
| Scoped skill | `.ai/skills/pi-fusion-orchestration/SKILL.md` |
| Status report | `tooling/pi/Get-PiHarnessStatus.ps1` |
| Completeness validator | `scripts/Test-PiHarnessCompleteness.ps1` |
| Dependency-free test | `tests/test_pi_harness_contracts.py` |
| Optional hook | `tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1` |
| CI | `.github/workflows/pi-harness-contract.yml` |

## Workflow selection

Use **single-agent** for one bounded implementation lane where a second opinion adds little value.

Use **opinion-fusion** when two genuinely independent perspectives materially reduce architecture or routing risk. Both receive the same hashed minimized input. Their outputs remain separate and attributed. The adjudicator must preserve consensus, divergence, unresolved risks, rejected alternatives, and provenance before a designated writer begins.

Use **autovalidate** when deterministic acceptance criteria can be written independently before implementation. The architect owns the frozen gate; the builder owns scoped implementation; the validator owns execution evidence. Stop after five attempts, 45 minutes, two no-progress attempts, cancellation, changed assumptions, or contradictory evidence—whichever occurs first.

Use **blocked** when repository state, authority, upstream API identity, provider/model identity, privacy evidence, limits, artifact location, or branch ownership is missing.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
python tests/test_pi_harness_contracts.py
pwsh -NoLogo -NoProfile -File tooling/pi/Get-PiHarnessStatus.ps1
Test-AppHarness.cmd
git diff --check
```

The first two checks are the focused Pi harness proof. The status report renders what is working, broken, and missing. The aggregate harness verifies the wider registered repository composition.

## Hook policy

The repository tracks `tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1`, but never installs it implicitly. An operator may invoke it directly or deliberately wire it into a local hook after reviewing the script. It runs focused contracts, staged diff hygiene, and generated-evidence exclusion.

## Artifact policy

Runtime artifacts belong outside the repository under an operator-controlled local root such as:

```text
%LOCALAPPDATA%\AgentSwitchboard\PiHarness\runs\<run-id>\
```

Do not track credentials, raw prompts, raw model transcripts, customer data, private hostnames, local usernames, provider state, endpoint observations, or generated run evidence.

## Proof ceiling

This harness proves repository structure, route contracts, schema and registry shape, one-writer enforcement, bounded workflow semantics, focused validators, hook availability, CI wiring, and English operator guidance. It does not prove Pi installation, extension compatibility, provider availability, endpoint privacy, telemetry behavior, model response, fusion quality, autovalidation success, repository delivery, deployment, or operator acceptance.
