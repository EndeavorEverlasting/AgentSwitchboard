# Commit-Required Harness Doctrine

Machine-readable authority: `.ai/harness/harness-doctrine.policy.json`.

## Required sprint identity

Every writing sprint names repository, branch or worktree, PR or sprint, lane, owned scope, forbidden scope, expected artifacts, and validation order when specified. Cross-platform or cross-host work also names the selected environment topology and current role ceiling.

Task-specific execution rules override generic closeout behavior when they remain inside higher-priority platform, safety, environment-capability, and repository rules.

## Executable loop

`request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision`

Evidence comes before confidence. Preserve existing work before cleanup. Reuse existing contracts and helpers before invention. Completion requires checks, artifacts, and commit or GitHub evidence appropriate to the requested action.

## Action-commitment rule

A prompt, title, mission, or expected output that claims it will install, set up, build, execute, repair, configure, upgrade, deploy, merge, or release something must require the corresponding mutation and proof.

For repository work, require tracked mutation or an owned GitHub mutation, validation evidence, commit or GitHub evidence, and final repository state. Acknowledgment, advice, a rewritten prompt, a plan, a summary, a repository clone, a package list, or a handoff is not a substitute for requested execution.

Plan-only work is valid only when requested or when an exact blocker makes mutation impossible. The blocker path provides the smallest applicable patch and one safest next command.

## Environment capability contract

Read `docs/governance/environment-capability-contract.md` and `.ai/harness/environment-capability.policy.json` before any request involving another platform, “any environment,” auto-configuration, phone access, cross-device continuity, Termux, SSH, remote tmux, WSL/Linux/Windows boundaries, or an uncertain runtime host.

Classify five layers independently:

`frontend -> transport -> workspace host -> orchestration runtime -> agent runtime`

Select exactly one registered topology and one role ceiling. A terminal client is not a workspace or runtime host. SSH reachability is not remote-shell compatibility. Repository or package presence is not orchestration or agent readiness. Matching tmux session names on different hosts do not identify the same workspace. Phone-local tmux is not cross-device continuity. Termux is not generic Linux. Command acknowledgement and hosted CI are not live environment behavior.

Auto-configuration is not a universal installer. It follows:

`observe -> classify -> select topology -> report blockers -> bounded mutation -> effective-state readback -> focused validation -> authorized runtime certification -> proof report`

Unknown operating system, shell class, workspace-host identity, repository origin/state, tmux server/session, orchestration runtime, agent/provider state, persistence boundary, or authority blocks the dependent mutation.

The Android implementation is currently `terminal-client-implemented`. Its role ceiling is `terminal-client`; phone-local tmux is `local-shell-only` and `device-local-only`; native Android orchestration is `unimplemented`; native Android agent runtime is `unproved`. Cross-device continuity requires both clients to reach the same separately classified workspace host and tmux server/session identity.

Any prompt claiming to auto-configure or certify a new environment must require tracked topology, policy, implementation, validators, commit or GitHub evidence, and an honest role/proof ceiling. Validate with `scripts/Test-EnvironmentCapabilityHarness.ps1` and `tests/test_environment_capability_harness.py`.

## Test-only GNHF timing rule

A GNHF run used only as a test, smoke check, provider probe, fixture, or contract exercise has hard limits:

- maximum wall clock: 30 seconds;
- maximum time for any iteration: 30 seconds;
- default maximum iterations: 1;
- terminate the timed-out process tree;
- record timeout evidence.

Token and iteration-count caps do not replace time limits. When the GNHF CLI cannot enforce both limits, a repository-owned wrapper must enforce them externally.

## DeepSeek usage-window rule

DeepSeek may run only when a fresh, source-attributed schedule classifies the current time as `standard` or `discounted` and the effective usage multiplier is no greater than `1.0`.

Block DeepSeek during `double-usage`, `premium-multiplier`, or `unknown` rate state and whenever the schedule is missing, expired, stale, or unverified. The gate is fail-closed.

The operator-local schedule belongs at `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\deepseek-usage-windows.json`. It records the provider plan, source, verification time, effective dates, timezone, windows, rate class, and multiplier. Do not infer current hours from remembered or historical promotions.

The official DeepSeek API pricing reference currently publishes flat token prices and no active time-of-day window. The historical `16:30-00:30 UTC` off-peak window ended on `2025-09-05T16:00:00Z`; it is inactive historical evidence only. A separate plan-specific schedule must be verified from the applicable source.

## Runtime event contract

Read `docs/governance/runtime-event-contract.md` and `.ai/harness/runtime-event-contract.policy.json` whenever work claims an event source, listener, observer, trigger cascade, handler, successor event, or evidence sink.

The required composition is:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

Every participating node and edge must be registered in `.ai/harness/runtime-event-topology.json`. Root events start their own correlation chain; successor events inherit correlation and identify their immediate parent as causation. Emitted envelopes are immutable.

A static graph proves registration only. Synthetic fixtures prove contract causality only. A runtime completion claim requires observed correlated evidence from source emission through the terminal successor or explicit failure and the evidence sink. Process exit, a plan, or an architecture description is not event-delivery proof.

Any prompt claiming it will build, install, repair, configure, or prove an event listener or cascade must require the corresponding tracked implementation, topology update, validation, commit or GitHub evidence, and honest proof ceiling. Validate the doctrine with `scripts/Test-RuntimeEventContract.ps1`.

## Device profile launcher contract

Read `docs/governance/device-profile-launcher-contract.md`, `.ai/harness/device-profile-launcher.policy.json`, and the environment-capability contract whenever work claims a platform profile, terminal launcher, desktop shortcut, open-or-activate path, phone client, remote workspace, or consumer certification.

AgentSwitchboard owns one canonical launcher per platform profile. The Windows Profile is WezTerm-backed, idempotent `open-or-activate`, and owned by AgentSwitchboard. SysAdminSuite may consume and certify that launcher but may not recreate lifecycle logic or fall back to raw `wezterm`, `wezterm.exe`, or `wezterm-gui.exe`. A desktop shortcut delegates to the canonical launcher only.

The Linux and Android profiles remain separate. The Android implementation is a Termux terminal client, not a native full runtime. Phone-local tmux is device-local only. Remote Android use requires a selected supported host profile and read-only preflight of remote shell, tmux, repository, origin, cleanliness, and session state. Repository cloning and package installation do not prove GNHF, coding agents, providers, authentication, or cross-device continuity.

Any prompt claiming it will install, build, configure, repair, certify, or deploy a profile or launcher must require the corresponding environment topology, tracked implementation, registry update, focused validation, commit or GitHub evidence, and honest role/proof ceiling. Contract-only doctrine may not claim a launcher exists or that a workspace was opened or activated. Validate with `scripts/Test-EnvironmentCapabilityHarness.ps1` and `scripts/Test-DeviceProfileLauncherContract.ps1`.

## Preservation and proof

- preserve unrelated dirty work in a separate worktree or branch;
- stage only owned tracked files;
- run focused checks before broader safe checks;
- run `git diff --check` and review final Git state;
- push normally to a safe feature branch;
- open or update the intended PR;
- report exact files, environment topology and role ceiling when applicable, validation results, commit SHA, push state, PR state, proof level, proof ceiling, gaps, final Git state, and one next command.

## Invalid execution contracts

Reject acknowledgment-only, summary-only, rewritten-prompt-only, handoff-only, or preflight-only substitutes; action language without mutation and proof; event-listener or cascade claims without registered nodes, edges, correlated evidence, and the achieved proof boundary; environment or auto-configuration claims that equate frontend, transport, repository, packages, session names, or command acknowledgement with a workspace or runtime; profile or launcher claims that permit competing owners, consumer-owned lifecycle logic, raw frontend fallback, cross-profile substitution, lower-role topology substitution, or architecture-only delivery; Android full-runtime claims without a tracked native port and live certification; test-only GNHF runs over 30 seconds; and DeepSeek execution during double-usage or unknown schedule state.
