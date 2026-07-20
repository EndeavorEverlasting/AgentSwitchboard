# Commit-Required Harness Doctrine

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`
Machine-readable policy: `.ai/harness/harness-doctrine.policy.json`

Every writing sprint names the repository, branch or worktree, PR or sprint, lane, owned scope, forbidden scope, expected artifacts, and validation order when specified.

Use this loop:

`request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision`

## Action-commitment rule

Evidence precedes confidence. Preserve existing work before cleanup. Reuse existing contracts before invention. An action claim requires the corresponding mutation, validation, and commit or GitHub evidence; acknowledgment, advice, a plan, summary, or handoff is not a substitute.

A GNHF contract-only run is limited to 30 seconds wall clock and 30 seconds per iteration, with one iteration by default.

DeepSeek is eligible only in a fresh verified `standard` or `discounted` rate class with multiplier no greater than `1.0`. Unknown or stale state blocks use.

## Runtime event contract

Event composition also follows `docs/governance/runtime-event-contract.md` and `.ai/harness/runtime-event-contract.policy.json`. Register every source, observer, handler, successor edge, and evidence sink. Preserve correlation and causation. Static topology does not prove runtime delivery. Validate with `scripts/Test-RuntimeEventContract.ps1`.

Local rules may strengthen this doctrine. They may not weaken it.
