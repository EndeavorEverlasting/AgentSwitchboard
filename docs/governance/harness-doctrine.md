# Commit-Required Harness Doctrine

Machine-readable authority: `.ai/harness/harness-doctrine.policy.json`.

## Required sprint identity

Every writing sprint names repository, branch or worktree, PR or sprint, lane, owned scope, forbidden scope, expected artifacts, and validation order when specified.

Task-specific execution rules override generic closeout behavior when they remain inside higher-priority platform, safety, and repository rules.

## Executable loop

`request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision`

Evidence comes before confidence. Preserve existing work before cleanup. Reuse existing contracts and helpers before invention. Completion requires checks, artifacts, and commit or GitHub evidence appropriate to the requested action.

## Action-commitment rule

A prompt, title, mission, or expected output that claims it will install, set up, build, execute, repair, configure, upgrade, deploy, merge, or release something must require the corresponding mutation and proof.

For repository work, require tracked mutation or an owned GitHub mutation, validation evidence, commit or GitHub evidence, and final repository state. Acknowledgment, advice, a rewritten prompt, a plan, a summary, or a handoff is not a substitute for requested execution.

Plan-only work is valid only when requested or when an exact blocker makes mutation impossible. The blocker path provides the smallest applicable patch and one safest next command.

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

## Preservation and proof

- preserve unrelated dirty work in a separate worktree or branch;
- stage only owned tracked files;
- run focused checks before broader safe checks;
- run `git diff --check` and review final Git state;
- push normally to a safe feature branch;
- open or update the intended PR;
- report exact files, validation results, commit SHA, push state, PR state, proof level, proof ceiling, gaps, final Git state, and one next command.

## Invalid execution contracts

Reject acknowledgment-only, summary-only, rewritten-prompt-only, handoff-only, or preflight-only substitutes; action language without mutation and proof; event-listener or cascade claims without registered nodes, edges, correlated evidence, and the achieved proof boundary; test-only GNHF runs over 30 seconds; and DeepSeek execution during double-usage or unknown schedule state.
