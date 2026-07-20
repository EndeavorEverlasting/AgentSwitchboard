# Commit-Required Harness Doctrine

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`
Machine-readable policy: `.ai/harness/harness-doctrine.policy.json`

Every writing sprint names the repository, branch or worktree, PR or sprint, lane, owned scope, forbidden scope, expected artifacts, and validation order when specified.

Use this loop:

`request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision`

## Action-commitment rule

Evidence precedes confidence. Preserve existing work before cleanup. Reuse existing contracts before invention. An action claim requires the corresponding mutation, validation, and commit or GitHub evidence; acknowledgment, advice, a plan, summary, or handoff is not a substitute.

## Device-profile taxonomy

Platform- or device-specific work uses the `<Platform> Profile` name. **Windows Profile** is the current Windows-host lane. **Linux Profile** and **Android Profile** are reserved peer names and may not claim implementation or runtime proof before their own tracked delivery. Shared policy, schemas, routing, and handoffs stay **platform-neutral**. A device-specific sprint declares its target profile and profile-specific proof ceiling.

A GNHF run used only as a test, smoke check, provider probe, fixture, or contract exercise is limited to 30 seconds wall clock and 30 seconds per iteration, with one iteration by default. A repository-owned wrapper terminates the process tree when the CLI cannot enforce both limits and records explicit timeout evidence.

DeepSeek is eligible only in a fresh, verified `standard` or `discounted` rate class with multiplier no greater than `1.0`. Block `double-usage`, premium, unknown, missing, expired, stale, or unverified schedule state. The operator-local schedule belongs at `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\deepseek-usage-windows.json` or a repository-approved platform equivalent.

Local rules may strengthen this doctrine. They may not weaken it.
