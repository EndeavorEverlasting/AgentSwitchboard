# Pi Operational Harness

AgentSwitchboard treats Pi as an execution adapter beneath repository governance, workflow selection, evidence policy, branch ownership, and now a machine-owned Windows bootstrap. The system bootstrap owns only the Pi runtime, AgentSwitchboard launchers, and Machine PATH entry; provider authentication, Pi settings, project trust, sessions, model preferences, and project resources remain user/project scoped.

## What is working

- `Bootstrap-Pi-SystemWide.cmd` is the canonical Windows operator front door for the ASB-managed standalone Pi runtime.
- `tooling/pi/Install-AgentSwitchboardPiSystem.ps1` installs the exact tracked standalone Windows release archive under `%ProgramFiles%\AgentSwitchboard\agents\pi\<version>` and exposes it through `%ProgramFiles%\AgentSwitchboard\bin\pi.cmd`.
- The tracked upstream record pins `@earendil-works/pi-coding-agent@0.85.1`, upstream tag `v0.85.1`, the official Windows x64/ARM64 asset names, and their official SHA-256 digests, verified on 2026-09-11.
- The system bootstrap does not require npm or Node.js. It verifies the tracked digest, staged version, whole archive layout, Git Bash, runtime ownership, launcher ownership, Machine PATH, and final exact-version launch.
- `tooling/pi/Invoke-AgentSwitchboardPiChild.ps1` is the first common child-agent execution seam. It gives child agents separate processes/contexts and bounded packets/results instead of requiring pairwise agent configuration.
- Read-only child roles receive only `read,grep,find,ls`. Writer children receive the bounded write tool set only on clean isolated linked worktrees, on non-default branches, with one writer per mutation surface.
- A child transport success remains `completed-unvalidated` until the coordinator independently verifies task-specific artifacts, diffs, tests, commits, and integration state.
- `tooling/pi/Test-PiWorkstationPrereqs.ps1` remains the canonical **npm compatibility/adoption** preflight. It is read-only and is no longer the dependency floor for Windows standalone system bootstrap.
- The compatibility preflight resolves PowerShell, Node, npm, Git, bash, and any existing Pi command. Command-path evidence is bounded and external probes are limited by `ProbeTimeoutSeconds` (default 15 seconds).
- Generated compatibility evidence is rejected if `OutputDirectory` resolves inside the repository (`OUTPUT_DIRECTORY_INSIDE_REPOSITORY`).
- On Windows, Bash discovery for project/runtime use honors a reviewed project-local `.pi/settings.json` `shellPath` before Git-for-Windows defaults and PATH fallbacks.
- In normal compatibility mode, live npm metadata is compared against the current `@earendil-works/pi-coding-agent@0.85.1` metadata and the deprecated legacy package record. Reachable incomplete metadata is drift, not network success.
- CI can use `-NoNetwork -NoWrite -AllowUnready` to prove the compatibility parser/contracts without pretending a hosted runner is an operator workstation.
- Task intake selects exactly one route: single-agent, opinion fusion, autovalidate, or blocked.
- Opinion fusion separates architect, builder, adjudicator, and designated-writer responsibilities.
- Autovalidation freezes architect-owned acceptance gates before builder mutation.
- Every multi-agent route requires one writer per branch, attributed execution identity, explicit limits, local-only artifacts, and a proof ceiling.
- The broader single-agent/fusion/autovalidate routes remain `contract-only`; the new system and child adapters are primitives beneath those routes, not proof that multi-agent delivery is already field-certified.

## Machine runtime versus user state

The split is deliberate:

| Scope | Owner |
|---|---|
| Pi standalone runtime archive | AgentSwitchboard / machine |
| `pi.cmd` and `asb-pi.cmd` launchers | AgentSwitchboard / machine |
| AgentSwitchboard Machine PATH entry | AgentSwitchboard / machine |
| Provider login/API/subscription state | user |
| Pi settings and model preference | user/project |
| Project trust decisions | user/project |
| Sessions, extensions, packages, skills | user/project |

The system bootstrap does not mutate provider credentials, global Pi settings, project trust, sessions, models, extensions, packages, or Git history.

## Repository surfaces

| Surface | Path |
|---|---|
| System bootstrap CMD | `Bootstrap-Pi-SystemWide.cmd` |
| System bootstrap owner | `tooling/pi/Install-AgentSwitchboardPiSystem.ps1` |
| System bootstrap contract | `tooling/pi/harness/system-bootstrap.contract.json` |
| Child-agent adapter | `tooling/pi/Invoke-AgentSwitchboardPiChild.ps1` |
| Child-agent contract | `tooling/pi/harness/child-agent-invocation.contract.json` |
| npm compatibility preflight | `tooling/pi/Test-PiWorkstationPrereqs.ps1` |
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
| Executable compatibility contracts | `tests/Test-PiWorkstationPrereqsContracts.ps1` |
| Dependency-free structural contracts | `tests/test_pi_harness_contracts.py` |
| System/bootstrap contracts | `tests/test_pi_system_bootstrap.py` |
| System/child guide | `docs/harness/pi-system-bootstrap-and-child-agents.md` |
| Optional hook | `tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1` |
| CI | `.github/workflows/pi-harness-contract.yml` |

## System-wide bootstrap

From an elevated Windows shell:

```cmd
Bootstrap-Pi-SystemWide.cmd
```

The bootstrap ascertains Windows/PowerShell/architecture/elevation, the tracked architecture-specific release identity, SHA-256, existing ASB runtime ownership, launcher ownership, and Git Bash before mutation. It downloads only the tracked release asset and installs the complete archive rather than copying only `pi.exe`.

Non-mutating inspection:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPiSystem.ps1 -Mode Inspect -RootPath .
```

System evidence stays outside the repository under `%LOCALAPPDATA%\AgentSwitchboard\PiHarness\system-bootstrap\runs\...`.

## npm compatibility/adoption preflight

The older workstation preflight remains useful when inspecting npm/package compatibility or a non-system Pi installation:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Test-PiWorkstationPrereqs.ps1
```

It checks the tracked upstream record, Node/npm/Git/bash/Pi paths, live npm metadata, legacy-package deprecation, and exact equality to the tracked npm-compatible version metadata. `-AllowUnready` changes process exit behavior only; it never makes an unready state installable. `-NoNetwork` never proves current upstream state.

This preflight does **not** gate the Windows standalone `Bootstrap-Pi-SystemWide.cmd` path. The standalone runtime is intentionally package-manager independent.

## Agents working within agents

The first supported pattern is **not** agent A configured directly to agent B, C, D, and E. Instead every parent uses one AgentSwitchboard request/result contract. The parent creates a bounded packet; ASB selects the exact managed child runtime, applies repository/write guards, launches the child with a separate context, captures local evidence, and returns a bounded result envelope to the coordinator.

Pi v1 child execution uses one-shot JSON mode. Persistent RPC is known upstream capability, but it remains a separate transport upgrade until strict LF-delimited JSONL framing, cancellation, session isolation, correlation, and crash-recovery behavior have dedicated executable tests.

Example read-only child:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Invoke-AgentSwitchboardPiChild.ps1 `
  -PromptPath .\packet.txt `
  -RepositoryPath C:\path\to\repo `
  -Role architect `
  -WriteMode read-only
```

Raw JSON child events can include prompt/model transcript content and therefore remain local-only outside the repository. The bounded `child-result.json` is also local operational evidence.

## Workflow selection

Use **single-agent** for one bounded implementation lane where a second opinion adds little value.

Use **opinion-fusion** when genuinely independent perspectives materially reduce architecture/routing risk. Outputs stay separate and attributed; adjudication preserves consensus, divergence, unresolved risks, rejected alternatives, and provenance before a designated writer begins.

Use **autovalidate** when deterministic acceptance criteria can be written independently before implementation. The architect owns the frozen gate, the builder owns scoped implementation, and the validator owns execution evidence. Stop at the configured attempt/time/no-progress/token/cancellation boundaries.

Use **blocked** when repository state, authority, provider/model identity, privacy evidence, limits, artifact location, or branch ownership is missing.

## Validation

```powershell
python -m unittest tests.test_pi_system_bootstrap -v
python tests/test_pi_harness_contracts.py
pwsh -NoLogo -NoProfile -File tooling/pi/Test-PiWorkstationPrereqs.ps1 -NoNetwork -NoWrite -AllowUnready
pwsh -NoLogo -NoProfile -File tests/Test-PiWorkstationPrereqsContracts.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File tooling/pi/Get-PiHarnessStatus.ps1 -NoWrite
Test-AppHarness.cmd
git diff --check
```

The Windows CI lane also parses the touched PowerShell and runs non-mutating system inspection. CI deliberately does not perform machine `Apply`, provider login, or a paid/model-backed child run.

## Artifact policy

System bootstrap, compatibility, child-agent, and workflow runtime artifacts belong outside the repository under operator-local paths such as:

```text
%LOCALAPPDATA%\AgentSwitchboard\PiHarness\...\<run-id>\
```

Do not track credentials, raw prompts, raw model transcripts, customer data, private hostnames, local usernames, provider state, endpoint observations, or generated run evidence. Raw Pi child JSON event streams are especially sensitive because they may echo prompt/model transcript content.

## Proof ceiling

This harness proves repository structure, tracked Pi upstream identity, exact standalone Windows asset/digest records, system bootstrap and launcher implementation, machine/user ownership boundaries, compatibility-preflight behavior, child-process isolation/write guards, route contracts, one-writer semantics, deterministic validators, and CI wiring. It does not prove a physical workstation installation until `Bootstrap-Pi-SystemWide.cmd` runs there; it does not authenticate a provider, prove endpoint privacy, prove a model response, prove child-agent quality, prove actual parallel fan-out, prove fusion/autovalidation success, deliver repository changes, deploy, or establish operator acceptance.
