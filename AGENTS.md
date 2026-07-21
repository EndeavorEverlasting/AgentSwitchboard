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

Record the PR or sprint identity and the validation order exactly when supplied.

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

## Multi-agent and local-model governance

Pi and other third-party agent runtimes may be evaluated or integrated only through a separately declared implementation sprint. A pasted installer, command line, extension scaffold, video transcript, or remembered API is evidence to investigate, not authority to install or execute.

1. **Verify the upstream contract.** Before adopting a third-party command, path, configuration schema, package name, provider flag, or extension API, verify it against the official source for the pinned version. Record the package identity, version or commit, source URL, supported operating system, expected files, and rollback path.
2. **Treat extensions as executable code.** Agent extensions can inherit the invoking process's permissions. Review their source, dependencies, install scope, filesystem access, subprocess behavior, network behavior, and update mechanism. Prefer project-local, pinned, reviewable configuration over silent global installation.
3. **Prove privacy; do not infer it.** `localhost`, an open-weight model, or a local-looking provider name does not by itself prove that code remains on the machine. A privacy claim requires evidence of the resolved endpoint, listening interface, provider and model identity, authentication behavior, telemetry and update behavior, outbound network activity, logs, persistence, and every fallback route.
4. **Declare orchestration roles.** Multi-agent work must name the architect, builder, validator or adjudicator, designated writer, inputs, outputs, permissions, branch ownership, and stop conditions. Reviewers and adjudicators remain read-only unless a separate write lane is declared.
5. **Preserve independent evidence.** Parallel opinions must be captured separately with provider, model, configuration, prompt digest, timestamp, and result status before fusion. Two aliases for the same model or endpoint do not prove independent review.
6. **Make divergence visible.** Fusion must preserve consensus, disagreements, unresolved risks, rejected alternatives, and source attribution. Agreement among models is not proof of correctness and may not erase contradictory evidence.
7. **Separate test authority from implementation.** In an autovalidation lane, the architect-owned acceptance contract is fixed before builder mutation. The builder may not silently weaken, replace, skip, or reinterpret the gate to manufacture a pass. Any gate change requires an explicit reviewed contract revision.
8. **Bound every loop.** Opinion, fusion, repair, and autovalidation loops require maximum attempts, wall-clock or token bounds, no-progress detection, cancellation behavior, and a terminal failure report. Local capacity does not authorize infinite execution.
9. **One designated writer.** Multi-agent orchestration does not override one writer per branch. Concurrent agents write only to disjoint branches or artifacts, and a named convergence owner performs integration after re-inspection.
10. **Log actual execution identity.** Reports must record the agent, provider, model, endpoint class, role, branch or worktree, and validation result that actually ran. Requested routing is not execution proof.

No governance-only sprint may claim that Pi, Ollama, LM Studio, a local model, a fusion command, or an autovalidation loop was installed, private, functional, unlimited, or production-ready without the corresponding tracked implementation and runtime evidence.

## External skill adoption and prompt-kit gap filling

AgentSwitchboard treats reputable external skill catalogs as evidence sources for reusable procedures, not as automatic authority. Before inventing a project skill, inspect repository-local skills, registered prompt kits, and verified upstream skill sources.

1. **Verify and pin external skills.** Record the upstream repository, exact commit or release, skill path and blob, license, supported agent or runtime, installation scope, dependencies, executable resources, side effects, update mechanism, rollback, and test status. “Industry-recommended” is not a substitute for this review.
2. **Prefer project-local reviewability.** Reuse or adapt a pinned skill through a tracked repository change when team behavior depends on it. A global install changes operator state and requires an explicitly authorized workstation or runtime sprint; governance-only work may record an approved command but must not claim that it ran.
3. **Adopt the verified skill-creator method.** The reviewed reference is `anthropics/skills` at commit `fa0fa64bdc967915dc8399e803be67759e1e62b8`, path `skills/skill-creator/SKILL.md`, blob `65b3a402dbd09b8e83f9d637c6b553875189085c`. The candidate global command is `npx skills add anthropics/skills --skill skill-creator -g`. Use its core method: capture intent from conversation and repository evidence, draft a small skill with a clear trigger and output, use progressive disclosure and bundled deterministic resources, create realistic evaluation prompts, compare against a baseline when outputs are objective, measure quality, time, and token cost, iterate, and improve triggering. Local governance, child-repository product law, security boundaries, and proof requirements remain higher priority.
4. **Inspect before gap filling.** When AgentSwitchboard operates in another repository, inspect the nearest `AGENTS.md`, codebase map, skills, validators, plans, open PRs, current implementation, and Git state. Build a gap ledger containing observed evidence, the existing owner, missing capability, reusable skill candidate, prompt-kit candidate, confidence, and unresolved risk.
5. **Use the prompt kit to estimate bounded sprints.** Map each evidence-backed gap to the smallest matching prompt-kit entry and produce sprint candidates with repository and branch, lane and mission, owned and forbidden scope, dependencies, collision boundaries, expected artifacts, validation commands, proof gate, and proof ceiling. Split work when one sprint would cross owners, repositories, or proof levels.
6. **Keep estimation distinct from authority.** Prompt-kit ranking and external-skill discovery guide routing and estimation only. They do not authorize installation, prompt execution, repository mutation, provider access, merge, deployment, or target changes. Current repository evidence outranks prompt-kit metadata, marketplace popularity, and remembered best practice.
7. **Close the loop.** After a skill is adopted or created, add deterministic validation and record whether it improved the target tasks. Revise, quarantine, or retire skills that fail triggering, correctness, safety, or efficiency expectations.

## Forbidden behaviors

- **Acknowledgment without mutation** when the task safely requires repository change.
- **Plans without execution** when implementation is owned, bounded, and unblocked.
- **Summaries without proof** presented as delivery.
- **Completion claims without running checks** required by the repository or task.
- **Secret or credential exposure** in prompts, logs, commits, fixtures, plans, reports, or PR text.
- Destructive Git, force-push, default-branch writes, merge, release, deployment, or live-target mutation without explicit authority.
- Replacing a healthy canonical contract with a competing file or prompt-only convention.
- Ambiguous empty output, silently ignored flags, interactive prompts in agent automation, or unbounded output when a deterministic compact result is possible.
- Installing or executing unverified third-party agent snippets, packages, extensions, or provider commands as though pasted prose were a tested contract.
- Silently installing a global skill, importing an unpinned skill, or treating popularity or marketplace ranking as compatibility proof.
- Treating a prompt-kit match, generated sprint estimate, or selected skill as authority to execute or as proof that delivery occurred.
- Claiming privacy, model independence, successful fusion, or continuous validation from configuration intent alone.

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

When external skills or prompt-kit estimates affected the work, also report the pinned source, installation scope, whether installation actually ran, the selected prompt-kit candidate, and the evidence that justified the sprint estimate.

Also report generated-artifact policy, skipped checks, blockers, proof level and proof ceiling, final Git state, and relevant artifact paths. Cross-agent handoffs must be schema-backed and require the receiver to re-inspect current state.
