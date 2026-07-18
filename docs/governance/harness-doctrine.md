# Commit-Required Harness Doctrine

This doctrine is a tracked execution contract. Its machine-readable authority is `.ai/harness/harness-doctrine.policy.json`.

## Required sprint identity

Every writing sprint names:

- repository;
- branch or worktree;
- PR or sprint;
- lane;
- owned scope;
- forbidden scope;
- expected artifacts;
- validation order when specified.

Task-specific execution rules override generic closeout behavior when they remain inside higher-priority platform, safety, and repository rules.

## Executable loop

Use this loop:

`request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision`

Evidence comes before confidence. Preserve existing work before cleanup. Reuse existing contracts and helpers before invention. A completion claim requires checks, artifacts, and commit or GitHub evidence appropriate to the requested action.

## Action-commitment rule

A prompt, title, mission, or expected output that claims it will install, set up, build, execute, repair, configure, upgrade, deploy, merge, or release something must require the corresponding mutation and proof.

For repository work, require tracked mutation or an owned GitHub mutation, validation evidence, commit or GitHub evidence, and the final repository state. Acknowledgment, advice, a rewritten prompt, a plan, a summary, or a handoff is not a substitute for requested execution.

Plan-only work is valid only when the operator requested a plan or an exact blocker makes mutation impossible. The blocker path must provide the smallest applicable patch and one safest next command.

## Test-only GNHF timing rule

A GNHF run used only as a test, smoke check, provider probe, fixture, or contract exercise has these hard limits:

- maximum wall clock: 30 seconds;
- maximum time for any iteration: 30 seconds;
- default maximum iterations: 1;
- timed-out process tree must be terminated;
- timeout evidence must be recorded.

A test-only launch permitting a longer wall-clock or iteration duration is invalid even when its token or iteration count is otherwise small. When the GNHF CLI cannot enforce both time limits, a repository-owned wrapper must enforce them externally.

## DeepSeek usage-window rule

DeepSeek may run only when a fresh, source-attributed schedule classifies the current time as `standard` or `discounted`, and the effective usage multiplier is no greater than `1.0`.

Block DeepSeek when the rate class is `double-usage`, `premium-multiplier`, or `unknown`, and whenever the schedule is missing, expired, stale, or unverified. The gate is fail-closed.

The operator-local schedule belongs at:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\deepseek-usage-windows.json
```

It must record the provider plan, source, verification time, effective dates, timezone, windows, rate class, and multiplier. Do not infer current hours from remembered or historical provider promotions.

The official DeepSeek API pricing reference currently publishes flat token prices and no active time-of-day window. The historical `16:30-00:30 UTC` off-peak window ended on `2025-09-05T16:00:00Z`; it is retained only as inactive historical evidence. A separate plan-specific double-usage schedule must be verified from the applicable provider or plan source before use.

## Preservation and proof

- preserve unrelated dirty work in a separate worktree or branch;
- do not reset, discard, or delete unknown partial work;
- stage only owned tracked files;
- run focused checks before broader safe checks;
- use `git diff --check`, `git status --short`, `git diff --stat`, and reviewed diff output before commit;
- push normally to a safe feature branch;
- open or update the intended PR;
- report exact files, validation results, commit SHA, push state, PR state, proof level, proof ceiling, gaps, final Git state, and one next command.

## Invalid execution contracts

Reject:

- acknowledgment only;
- summary only;
- rewritten prompt only;
- plan only when mutation is safe and requested;
- handoff only;
- preflight only;
- action language without mutation and proof;
- test-only GNHF runs over 30 seconds;
- DeepSeek execution during double-usage or unknown schedule state.
