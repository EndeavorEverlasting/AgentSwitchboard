# Agent Operating Contract

`AGENTS.md` is the single source of truth for how agents operate in AgentSwitchboard. AgentSwitchboard is the canonical policy source for the EndeavorEverlasting repository family. Child repositories remain authoritative for their own product behavior, safety boundaries, artifacts, validators, and proof promotion, but local rules may strengthen and never silently weaken this contract.

## Canonical authority

Read `docs/governance/harness-doctrine.md` and `.ai/harness/harness-doctrine.policy.json` before repository work. For event sources, observers, listeners, handlers, trigger cascades, successor events, or evidence sinks, also read `docs/governance/runtime-event-contract.md` and `.ai/harness/runtime-event-contract.policy.json`. For platform profiles, terminal launchers, desktop shortcuts, open-or-activate behavior, or consumer certification, also read `docs/governance/device-profile-launcher-contract.md` and `.ai/harness/device-profile-launcher.policy.json`.

A task prompt selects bounded work. It does not replace this contract, grant a forbidden capability, or lower a proof requirement.

## Agent operating principles

1. **Evidence before action.** Inspect current Git state, repository contracts, plans, validators, active PRs, and relevant implementation before mutating files.
2. **Floor before furniture.** Establish repository identity, authority, safety, ownership, dependencies, and validation before feature polish, automation, or convenience work.
3. **Bounded sprints with declared scope.** Every writing sprint has one mission, explicit boundaries, expected artifacts, validation, and a proof ceiling.
4. **One writer per branch.** A branch or worktree has one active writer. Parallel agents require disjoint branches, disjoint owned paths, and an explicit convergence owner.
5. **Reuse before replacing.** Search for healthy contracts, helpers, schemas, scripts, validators, workflows, and naming patterns before inventing alternatives.
6. **No completion without proof.** Completion is an evidence claim, not a confidence statement. Run the checks and report the resulting Git or PR evidence.

## Instruction precedence

When instructions conflict, apply this order:

1. Platform, security, legal, and repository-owner instructions.
2. This governance contract.
3. Task-specific prompts.
4. Generic defaults.

The nearest nested `AGENTS.md` and child-repository product law operate within this order and may strengthen the applicable boundary. Tool-specific adapters such as `CLAUDE.md` may specialize execution but may not weaken higher-priority rules. When a conflict remains, stop the conflicting action, preserve evidence, and name the conflict.

## Required reading order

1. `AGENTS.md` and the nearest nested `AGENTS.md`.
2. `CODEBASE_MAP.md`, `README.md`, `CONTRIBUTING.md`, and repository operating docs.
3. Tool adapter such as `CLAUDE.md`.
4. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`.
5. The selected `.ai/skills/*/SKILL.md`.
6. `plans/plan-registry.json` and the selected public plan.
7. Applicable governance policies, validators, open PRs, and recent Git history.

For repository-family work, load `.ai/harness/repository-family.registry.json` and the target profile before assuming paths, validators, artifacts, or authority. Current repository evidence outranks remembered chat context, stale handoffs, filenames, and timestamps.

## Mandatory sprint declaration

Every writing sprint must state, before mutation:

- repository and branch;
- lane and mission;
- owned scope and forbidden scope;
- dependencies and safe parallel work when applicable;
- expected artifacts and validation commands;
- proof ceiling;
- commit, push, and PR expectation.

If the declaration cannot be made accurately, perform read-only intake first. Do not begin a broad write lane from a placeholder repository, unknown branch, ambiguous owner, or unbounded task.

## Mandatory execution discipline

- Preserve unrelated dirty work; isolate concurrent writers by branch and worktree.
- Keep judgment in skills and deterministic behavior in code, schemas, registries, validators, workflows, and artifacts.
- Treat prompts as artifacts, never as the sole implementation.
- Put material cross-session coordination under `plans/`; a PR description is not the only durable record.
- Protect credentials, personal data, private hostnames, customer evidence, large logs, dumps, and machine-local junk.
- Run focused checks before broader safe validation and never inflate static or synthetic proof into runtime or target proof.
- When safe and authorized, mutate tracked files, validate, commit, push, and open or update the intended PR.
- Preserve the same repair context when a deterministic gate exposes a correctable defect; do not abandon evidence and restart blindly.

## Agent-facing interface doctrine (AXI)

Agent-facing commands, reports, tools, and wrappers must be designed for reliable operation at low token cost. The enforceable repository interpretation is derived from the Agent eXperience Interface principles at https://axi.md/.

1. **Token-efficient output.** Return only decision-relevant information by default. Prefer compact structured output; use TOON where compatible and retain JSON where schemas or consumers require it.
2. **Minimal default schemas.** Default list records should expose only the few fields needed for the next decision. Additional fields require an explicit option.
3. **Content truncation.** Bound large text, state the original size, state that truncation occurred, and provide an explicit full-content escape hatch.
4. **Pre-computed aggregates.** Include counts, status summaries, derived readiness, and other values that prevent avoidable follow-up calls.
5. **Definitive empty states.** Return an explicit zero-result or no-match state. Silence is not a valid empty result.
6. **Structured errors and exit codes.** Fail non-interactively with machine-readable error identity, stable exit semantics, and loud rejection of unknown flags. Keep structured results on stdout and diagnostic detail on stderr when the interface supports that separation.
7. **Ambient context.** Directory-scoped startup context must be compact, explicit, and opt-in. Do not install implicit hooks merely to inject context.
8. **Content first.** A no-argument status command should show current actionable state, identity, and readiness rather than only generic help.
9. **Contextual disclosure.** Each result should include the smallest concrete next action or command template needed to continue safely. Carry forward fixed disambiguating values and leave unknown runtime values as placeholders.
10. **Consistent help.** Every agent-facing command exposes concise, predictable help. Help complements contextual next steps rather than replacing them.

When safe, combine action and observation so a mutation returns the resulting state and evidence in the same bounded operation. Do not force an agent to spend another call merely to discover whether the preceding action worked.

## Forbidden behaviors

- **Acknowledgment without mutation** when the task safely requires repository change.
- **Plans without execution** when implementation is owned, bounded, and unblocked.
- **Summaries without proof** presented as delivery.
- **Completion claims without running checks** required by the repository or task.
- **Secret or credential exposure** in prompts, logs, commits, fixtures, plans, reports, or PR text.
- Destructive Git, force-push, default-branch writes, merge, release, deployment, or live-target mutation without explicit authority.
- Replacing a healthy canonical contract with a competing file or prompt-only convention.
- Ambiguous empty output, silently ignored flags, interactive prompts in agent automation, or unbounded output when a deterministic compact result is possible.

## Runtime event composition

Every claimed runtime event path registers this chain:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

All participating nodes, edges, and event types belong in `.ai/harness/runtime-event-topology.json`. Emitted envelopes are immutable. A root event begins its own correlation chain; each successor receives a new event ID, inherits correlation, names its immediate parent as causation, and advances sequence.

A claim that an event listener or cascade was built requires the corresponding deterministic implementation, topology update, validation, and commit or GitHub evidence. A runtime-success claim additionally requires correlated source, observer, handler, successor or terminal, and sink artifacts from an explicitly authorized runtime lane. Static topology and synthetic fixtures prove lower levels only.

Validate the runtime-event-contract with `scripts/Test-RuntimeEventContract.ps1`, then validate registration in the wider harness with `Test-AppHarness.cmd`.

## Device profiles and launcher ownership

AgentSwitchboard owns separate **Windows Profile**, **Linux Profile**, and **Android Profile** contracts. Platform implementation may differ; one profile must not silently inherit another profile's launcher or configuration.

The Windows Profile is WezTerm-backed and has exactly one canonical `open-or-activate` launcher owned by AgentSwitchboard. SysAdminSuite is a delegate and certifier, not a second launcher owner. Raw `wezterm`, `wezterm.exe`, `wezterm-gui.exe`, desktop shortcuts, and consumer repositories may not contain independent lifecycle, discovery, activation, or fallback logic. A missing or uncertified canonical launcher is a blocker.

A claim that a profile or launcher was installed, built, repaired, configured, certified, or deployed requires tracked implementation, profile registry updates, focused validation, commit or GitHub evidence, and an honest proof ceiling. Contract-only doctrine must not claim the launcher exists or that a window was opened or activated.

Validate with `scripts/Test-DeviceProfileLauncherContract.ps1`, then run the wider doctrine and aggregate harness validators.

## Public plans

`plans/plan-registry.json` indexes durable public coordination. Plans record mission, ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. Update the machine-readable plan in the implementation branch when material state changes.

Never place secrets, customer data, private hostnames, machine-local paths, provider state, credentials, or raw runtime evidence in a public plan. Plans never grant authentication, merge, deployment, target mutation, secret access, or destructive-Git authority. Use `.ai/skills/public-plan-coordination/SKILL.md` and `scripts/Test-PublicPlanContracts.ps1`.

## Capability, trigger, and skill rules

An action is allowed only when the environment exposes the capability, the capability is verified, the task authorizes it, and repository policy permits it. Capability presence is not authority. See `CAPABILITIES.md`.

Triggers select reviewed workflows or skills; they never grant destructive, secret, runtime, merge, deployment, or target authority. See `TRIGGERS.md`.

Use the smallest applicable skill and follow its inputs, procedure, outputs, deterministic validation, forbidden scope, and stop conditions. See `SKILLS.md`.

## Repository-family contract

`.ai/agent-contract.json` declares the canonical contract. `.ai/harness/repository-family.registry.json` declares operational child entrypoints. Use the read-only status probe before cross-repository work:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1
```

A ready profile proves only observed clone identity and required paths. It does not authorize mutation or prove child validators. Child adoption occurs through tracked reviewable PRs; local rules may strengthen but not silently weaken the canonical baseline.

## Completion standard

A task is complete only when, at minimum:

- files changed are named;
- validation was actually run, with commands and results reported rather than assumed;
- commit SHA exists for a writing sprint;
- push or PR state is reported;
- one exact next command is given.

Also report generated-artifact policy, skipped checks, blockers, proof level and proof ceiling, final Git state, and relevant artifact paths. Cross-agent handoffs must be schema-backed and require the receiver to re-inspect current state.
