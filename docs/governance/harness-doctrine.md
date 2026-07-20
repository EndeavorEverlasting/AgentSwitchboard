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

## Device-profile taxonomy

Platform- or device-specific work names its target with the canonical `<Platform> Profile` form. The current Windows, WezTerm, WSL, tmux, and Windows-host automation lane is the **Windows Profile**. Do not describe that lane as a universal workstation or all-device profile.

**Linux Profile** and **Android Profile** are reserved peer names for future implementation lanes. A reserved name is architecture, not delivery proof: neither profile may be presented as implemented, installed, validated, or released until its own tracked behavior and platform-appropriate runtime evidence exist.

Cross-platform policy, schemas, routing, handoffs, and shared orchestration remain **platform-neutral**. Shared contracts may be consumed by multiple profiles, but one profile must not silently absorb another platform's lifecycle or proof. Every device-specific sprint declares its target profile, and every completion report states the profile-specific proof ceiling.

The product goal may converge a common terminal and agent experience across devices, but Windows, Linux, and Android each earn separate implementation, validation, operator acceptance, and release evidence.

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

## Preservation and proof

- preserve unrelated dirty work in a separate worktree or branch;
- stage only owned tracked files;
- run focused checks before broader safe checks;
- run `git diff --check` and review final Git state;
- push normally to a safe feature branch;
- open or update the intended PR;
- report exact files, validation results, commit SHA, push state, PR state, proof level, proof ceiling, gaps, final Git state, and one next command.

## Invalid execution contracts

Reject acknowledgment-only, summary-only, rewritten-prompt-only, handoff-only, or preflight-only substitutes; action language without mutation and proof; platform-specific work that omits or misnames its device profile; implementation claims for reserved profiles without tracked and runtime evidence; test-only GNHF runs over 30 seconds; and DeepSeek execution during double-usage or unknown schedule state.
