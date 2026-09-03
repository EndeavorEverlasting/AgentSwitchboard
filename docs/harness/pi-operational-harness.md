# Pi Operational Harness

AgentSwitchboard treats Pi as an execution adapter beneath repository governance, workflow selection, evidence policy, and branch ownership. The harness now owns a read-only workstation prerequisite gate, but it does not install Pi and does not assume that a local endpoint, extension, provider, or model is safe or available.

## What is working

- A fresh agent can start at `AGENTS.md`, `CODEBASE_MAP.md`, and `.ai/harness/manifest.json`, then follow the Pi-specific codebase map.
- `tooling/pi/Test-PiWorkstationPrereqs.ps1` is the canonical request -> workstation evidence -> install-decision gate.
- The tracked upstream prerequisite record pins `@earendil-works/pi-coding-agent@0.84.4`, source repository `earendil-works/pi`, and Node.js `>=22.19.0`, verified on 2026-09-03.
- The preflight resolves PowerShell, Node, npm, Git, bash, and any existing Pi command; preserves every discovered npm/Pi path; and reports whether Pi is absent, exact, unverifiable, or version-drifted.
- In normal mode the preflight resolves live npm metadata for the current package and the deprecated `@mariozechner/pi-coding-agent` package. Installation is not eligible if live metadata differs from the tracked verification record.
- CI may use explicit `-NoNetwork -NoWrite -AllowUnready` report-only mode to prove parser/contract behavior without pretending a hosted runner is an installable Pi workstation.
- Task intake selects exactly one route: single-agent, opinion fusion, autovalidate, or blocked.
- Opinion fusion separates architect, builder, adjudicator, and designated-writer responsibilities.
- Autovalidation freezes architect-owned acceptance gates before builder mutation.
- Every multi-agent route requires one writer per branch, attributed execution identity, explicit limits, local-only artifacts, and a proof ceiling.
- A repository-owned validator proves the component set is present, tracked, parseable, centrally registered, bound to the current Pi upstream identity, and free of known unverified install/API shortcuts.
- The opt-in pre-commit script runs focused contracts and rejects generated Pi runtime evidence from staged changes.
- Windows and Linux CI run the focused PowerShell and dependency-free Python contracts.

## What remains blocked

- Repository validation does not install or invoke Pi as an agent.
- The tracked package/version prerequisite identity is verified, but extension API compatibility remains unproven until extensions are separately reviewed against the installed exact version.
- No local or hosted provider is configured by this harness.
- No endpoint is classified private merely because it resolves to `localhost`.
- No fusion quality, model independence, autovalidation effectiveness, provider response, or committed delivery is claimed.
- No global Pi configuration, implicit Git hook, authentication, merge, deployment, or live-target mutation is allowed by this harness.

## Repository surfaces

| Surface | Path |
|---|---|
| Workstation prerequisite preflight | `tooling/pi/Test-PiWorkstationPrereqs.ps1` |
| Upstream verification | `tooling/pi/harness/upstream-verification.json` |
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

## Workstation prerequisite gate

Run the normal operator preflight before any Pi installation decision:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Test-PiWorkstationPrereqs.ps1
```

The gate is read-only. It checks:

1. PowerShell identity;
2. Node version against the tracked minimum;
3. npm version and every resolved npm command path;
4. Git availability;
5. Git Bash on Windows or bash on non-Windows systems;
6. existing Pi executable path/version when present;
7. live `@earendil-works/pi-coding-agent` version and Node engine;
8. live legacy-package deprecation metadata;
9. exact equality between live upstream metadata and the tracked verification record.

Terminal decisions are:

- `ready-to-install` — local prerequisites pass, Pi is absent, and live npm metadata matches the tracked pin;
- `already-installed` — local prerequisites pass and installed Pi exactly matches the tracked pin;
- `blocked-prerequisite` — Node/npm/Git/bash is missing or unverifiable;
- `upstream-drift` — live package/version/engine/deprecation metadata differs from the tracked record;
- `upstream-unavailable` — current npm metadata cannot be resolved;
- `installed-version-drift` — Pi exists but does not match the tracked version;
- `offline-upstream-unverified` — network verification was explicitly skipped.

`-AllowUnready` changes only the process exit behavior for report/CI use. It never promotes an unready status to installable. `-NoNetwork` never proves the current upstream state.

Generated prerequisite evidence is local-only under the system temporary directory by default and must not be committed.

## Workflow selection

Use **single-agent** for one bounded implementation lane where a second opinion adds little value.

Use **opinion-fusion** when two genuinely independent perspectives materially reduce architecture or routing risk. Both receive the same hashed minimized input. Their outputs remain separate and attributed. The adjudicator must preserve consensus, divergence, unresolved risks, rejected alternatives, and provenance before a designated writer begins.

Use **autovalidate** when deterministic acceptance criteria can be written independently before implementation. The architect owns the frozen gate; the builder owns scoped implementation; the validator owns execution evidence. Stop after five attempts, 45 minutes, two no-progress attempts, cancellation, changed assumptions, or contradictory evidence—whichever occurs first.

Use **blocked** when repository state, authority, live upstream identity, provider/model identity, privacy evidence, limits, artifact location, or branch ownership is missing.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Test-PiWorkstationPrereqs.ps1 -NoNetwork -NoWrite -AllowUnready
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
python tests/test_pi_harness_contracts.py
pwsh -NoLogo -NoProfile -File tooling/pi/Get-PiHarnessStatus.ps1
Test-AppHarness.cmd
git diff --check
```

The preflight report-only invocation proves the tracked/offline command path without making a live registry or workstation-readiness claim. The next two checks are the focused Pi harness proof. The status report renders what is working, broken, and missing. The aggregate harness verifies the wider registered repository composition.

## Hook policy

The repository tracks `tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1`, but never installs it implicitly. An operator may invoke it directly or deliberately wire it into a local hook after reviewing the script. It runs focused contracts, staged diff hygiene, and generated-evidence exclusion.

## Artifact policy

Runtime and prerequisite artifacts belong outside the repository under an operator-controlled local root such as:

```text
%LOCALAPPDATA%\AgentSwitchboard\PiHarness\runs\<run-id>\
```

or the system temporary Pi harness directory used by the prerequisite reporter.

Do not track credentials, raw prompts, raw model transcripts, customer data, private hostnames, local usernames, provider state, endpoint observations, or generated run evidence.

## Proof ceiling

This harness proves repository structure, the tracked Pi upstream prerequisite identity, workstation-preflight contract shape, route contracts, schema and registry shape, one-writer enforcement, bounded workflow semantics, focused validators, hook availability, CI wiring, and English operator guidance. A successful live workstation preflight additionally proves only the observed local prerequisites and current npm metadata at that run. It does not install Pi, prove extension compatibility, authenticate a provider, prove endpoint privacy, prove a model response, prove fusion/autovalidation success, deliver repository changes, deploy, or establish operator acceptance.
