# Agent Operating Contract

AgentSwitchboard is the canonical policy source for the EndeavorEverlasting repository family. Child repositories remain authoritative for their own product behavior, safety boundaries, artifacts, validators, and proof promotion.

## Canonical authority

Read `docs/governance/harness-doctrine.md` and `.ai/harness/harness-doctrine.policy.json` before repository work. For event sources, observers, listeners, handlers, trigger cascades, successor events, or evidence sinks, also read `docs/governance/runtime-event-contract.md` and `.ai/harness/runtime-event-contract.policy.json`.

Task-specific execution rules override generic closeout behavior while remaining subject to higher-priority platform, safety, and repository law.

## Required reading order

1. `AGENTS.md` and the nearest nested `AGENTS.md`.
2. `CODEBASE_MAP.md`, `README.md`, `CONTRIBUTING.md`, and repository operating docs.
3. Tool adapter such as `CLAUDE.md`.
4. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`.
5. The selected `.ai/skills/*/SKILL.md`.
6. `plans/plan-registry.json` and the selected public plan.
7. Applicable governance policies, validators, open PRs, and recent Git history.

For repository-family work, load `.ai/harness/repository-family.registry.json` and the target profile before assuming paths, validators, artifacts, or authority. Current repository evidence outranks remembered chat context, stale handoffs, filenames, and timestamps.

## Instruction precedence

1. Platform, security, legal, and repository-owner instructions.
2. Current child-repository product and safety law.
3. Nearest nested `AGENTS.md`.
4. Tool-specific adapters, which may not weaken this contract.
5. Task prompts, which select work but do not grant forbidden capabilities.

When rules conflict, stop the conflicting action, preserve evidence, and name the conflict.

## Mandatory discipline

- Inspect Git state, contracts, plans, patterns, and validators before invention.
- State repository, branch or worktree, PR or sprint, lane, owned scope, forbidden scope, dependencies, expected artifacts, validation order when specified, proof ceiling, and commit or PR expectation.
- Preserve unrelated dirty work; isolate concurrent writers by branch and worktree.
- Reuse healthy contracts and helpers before creating replacements.
- Keep judgment in skills and deterministic behavior in code, schemas, registries, validators, workflows, and artifacts.
- Treat prompts as artifacts, never as the sole implementation.
- Put material cross-session coordination under `plans/`; a PR description is not the only durable record.
- Protect credentials, personal data, private hostnames, customer evidence, large logs, dumps, and machine-local junk.
- Run focused checks before broader safe validation and never inflate static or synthetic proof into runtime or target proof.
- When safe and authorized, mutate tracked files, validate, commit, push, and open or update the intended PR.

## Runtime event composition

Every claimed runtime event path registers this chain:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

All participating nodes, edges, and event types belong in `.ai/harness/runtime-event-topology.json`. Emitted envelopes are immutable. A root event begins its own correlation chain; each successor receives a new event ID, inherits correlation, names its immediate parent as causation, and advances sequence.

A claim that an event listener or cascade was built requires the corresponding deterministic implementation, topology update, validation, and commit or GitHub evidence. A runtime-success claim additionally requires correlated source, observer, handler, successor or terminal, and sink artifacts from an explicitly authorized runtime lane. Static topology and synthetic fixtures prove lower levels only.

Validate the runtime-event-contract with `scripts/Test-RuntimeEventContract.ps1`, then validate registration in the wider harness with `Test-AppHarness.cmd`.

## Public plans

`plans/plan-registry.json` indexes durable public coordination. Plans record mission, ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. Update the machine-readable plan in the implementation branch when material state changes.

Never place secrets, customer data, private hostnames, machine-local paths, provider state, credentials, or raw runtime evidence in a public plan. Plans never grant authentication, merge, deployment, target mutation, secret access, or destructive-Git authority. Use `.ai/skills/public-plan-coordination/SKILL.md` and `scripts/Test-PublicPlanContracts.ps1`.

## Capability, trigger, and skill rules

An action is allowed only when the environment exposes the capability, the capability is verified, the task authorizes it, and repository policy permits it. Capability presence is not authority. See `CAPABILITIES.md`.

Triggers select reviewed workflows or skills; they never grant destructive, secret, runtime, merge, deployment, or target authority. See `TRIGGERS.md`.

Use the smallest applicable skill and follow its inputs, procedure, outputs, deterministic validation, forbidden scope, and stop conditions. See `SKILLS.md`.

## Repository-family harness

`.ai/agent-contract.json` declares the canonical contract. `.ai/harness/repository-family.registry.json` declares operational child entrypoints. Use the read-only status probe before cross-repository work:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1
```

A ready profile proves only observed clone identity and required paths. It does not authorize mutation or prove child validators. Child adoption occurs through tracked reviewable PRs; local rules may strengthen but not silently weaken the canonical baseline.

## Completion standard

Completion requires exact files changed, generated-artifact policy, checks run, skipped checks, commit SHA, push and PR state, blockers, proof level and ceiling, final Git state, and one exact next command. Cross-agent handoffs must be schema-backed and require the receiver to re-inspect current state.
