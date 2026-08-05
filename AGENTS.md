# Agent Operating Contract

`AGENTS.md` is the single source of truth for how agents operate in AgentSwitchboard. AgentSwitchboard is the canonical policy source for the EndeavorEverlasting repository family. Child repositories remain authoritative for their own product behavior, safety boundaries, artifacts, validators, and proof promotion, but local rules may strengthen and never silently weaken this contract.

## Canonical authority

Read `docs/governance/harness-doctrine.md` and `.ai/harness/harness-doctrine.policy.json` before repository work. For event sources, observers, listeners, handlers, trigger cascades, successor events, or evidence sinks, also read `docs/governance/runtime-event-contract.md` and `.ai/harness/runtime-event-contract.policy.json`. For any-environment, auto-configuration, cross-device, phone, SSH, remote-tmux, WSL/Linux/Windows, frontend, workspace-host, orchestration-runtime, or agent-runtime work, also read `docs/governance/environment-capability-contract.md` and `.ai/harness/environment-capability.policy.json`. For platform profiles, terminal launchers, desktop shortcuts, open-or-activate behavior, or consumer certification, also read `docs/governance/device-profile-launcher-contract.md` and `.ai/harness/device-profile-launcher.policy.json`.

A task prompt selects bounded work. It does not replace this contract, grant a forbidden capability, lower a proof requirement, or allow a lower-role environment topology to be silently substituted for the requested outcome.

## Agent operating principles

1. **Evidence before action.** Inspect current Git state, repository contracts, plans, validators, active PRs, relevant implementation, and the actual execution environment before mutating files or targets.
2. **Floor before furniture.** Establish repository identity, authority, safety, ownership, environment topology, dependencies, and validation before feature polish, automation, or convenience work.
3. **Bounded sprints with declared scope.** Every writing sprint has one mission, explicit boundaries, expected artifacts, validation, and a proof ceiling.
4. **One writer per branch.** A branch or worktree has one active writer. Parallel agents require disjoint branches, disjoint owned paths, and an explicit convergence owner.
5. **Reuse before replacing.** Search for healthy contracts, helpers, schemas, scripts, validators, workflows, and naming patterns before inventing alternatives.
6. **No completion without proof.** Completion is an evidence claim, not a confidence statement. Run the checks and report the resulting Git, PR, environment, and runtime evidence.

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
7. Applicable governance policies, validators, open PRs, recent Git history, and current environment evidence.

For repository-family work, load `.ai/harness/repository-family.registry.json` and the target profile before assuming paths, validators, artifacts, or authority. For cross-environment work, load `.ai/harness/environment-capability.policy.json` and `tooling/profiles/harness/environment-capability/environment-capability.registry.json` before assuming operating-system semantics, shell compatibility, repository hosting, tmux identity, orchestration-runtime availability, agent/provider readiness, or persistence. Current repository and environment evidence outrank remembered chat context, stale handoffs, filenames, session names, and timestamps.

## Mandatory sprint declaration

Every writing sprint must state, before mutation:

- repository and branch;
- lane and mission;
- owned scope and forbidden scope;
- dependencies and safe parallel work when applicable;
- canonical owner, source of truth, and interfaces when work spans multiple surfaces;
- environment topology and role ceiling when work crosses platforms, hosts, shells, frontends, or runtimes;
- expected artifacts and validation commands;
- proof ceiling;
- commit, push, and PR expectation.

Record the PR or sprint identity and the validation order exactly when supplied.

If the declaration cannot be made accurately, perform read-only intake first. Do not begin a broad write lane from a placeholder repository, unknown branch, ambiguous owner, unclassified environment, unsupported topology, or unbounded task.

## Launch order and dependency gates

A multi-chat launch pack is an executable coordination contract, not a convenience list.

1. **One prompt panel goes into one new chat. Run them in this exact order.** The displayed panel order must match the declared launch order; do not introduce an alternate display, category, or convenience order.
2. **A dependency gate is hard.** A downstream sprint may not start until the gate's named repository state, artifacts, validation, review, environment classification, and proof requirements are satisfied with current evidence.
3. **Parallel-group panels remain contiguous.** Parallel work is allowed only when each lane has disjoint branches or worktrees, disjoint owned paths, explicit collision boundaries, and a named convergence owner.
4. **Downstream work is blocked when a gate fails or becomes stale.** Preserve the failed evidence, repair the owning sprint, and re-run the gate before continuing.
5. **Each panel is self-contained.** It must carry its own repository, branch, dependencies, scope, tasks, validation, commit and PR contract, environment topology when applicable, proof ceiling, final response contract, and exact next command. No panel may depend on a separately copied shared preamble.
6. **A launch order coordinates work; it does not grant authority.** It cannot authorize secrets, destructive Git, merge, deployment, live-target mutation, provider access, authentication, or a higher proof claim than the task and repository contract permit.

## Broad-stride execution and principle reuse

Broad strides are encouraged when they complete one coherent vertical slice under one owner, one boundary map, and one acceptance gate. Breadth is not permission to mix unrelated missions, duplicate canonical behavior, blur environment roles, or inflate proof levels.

1. **Classify before creating.** Inspect the canonical contract, codebase map, skills, capabilities, triggers, workflows, schemas, validators, open PRs, implementation, and environment. Classify every requirement as `reuse`, `extend`, `repair`, `retire`, or `create`. Creation requires evidence that no healthy canonical owner already satisfies the need.
2. **Declare the boundary map.** Before mutation, record the canonical owner and source of truth, inputs and outputs, owned and forbidden paths, environment layers and role ceiling when applicable, dependency gates, collision boundaries, rollback boundary, validation order, and proof ceiling. Unknown boundaries require read-only intake, not improvisation.
3. **Keep breadth coherent.** One sprint may span harness spine, agent harness, conventional application logic, integration seams, validation, and documentation only when those surfaces are necessary to one coherent vertical slice, share a lifecycle and acceptance gate, and can be reviewed and reverted together. Split unrelated ownership lanes.
4. **Complete the owned vertical slice.** Prefer broad, useful delivery over trivial-only progress. When safely owned and unblocked, do not stop at scaffolding, a prompt, a map, one trivial file, or a plan while required implementation, registration, validation, reporting, or handoff remains unassigned. This rule never authorizes crossing forbidden scope or substituting an unsupported topology.
5. **Principles stay canonical.** `AGENTS.md` owns operating principles. Skills describe reusable workflow guidance. Capabilities expose reusable operations. Triggers deterministically route conditions to a skill, capability, or workflow. Application behavior remains in code and domain contracts. Prompts may orchestrate work but may not become the only implementation. Other files should reference the canonical principle instead of restating or mutating it. A new principle requires a governance sprint and validator update.
6. **Reconcile instead of forking.** When branches, PRs, skills, launchers, registries, or workflows overlap, compare them explicitly and classify each contribution as preserve, merge, retire, or supersede. Designate one canonical owner; compatibility surfaces must delegate and may not retain competing lifecycle logic.
7. **State accuracy explicitly.** Material claims must be labeled by evidence as verified, inferred, or unresolved. Refresh stale facts before action, identify the source and time of verification when relevant, and stop proof promotion when repository, environment, or runtime evidence contradicts the plan.
8. **Protect gate integrity.** Do not weaken a gate, rewrite a fixture to excuse a defect, skip a required check, or reinterpret acceptance criteria to manufacture a pass. Repair correctable defects within the same bounded context and rerun the complete affected gate.
9. **Stop at the boundary.** Split or escalate when work would cross authority, absorb an unrelated mission, collide with another writer, depend on stale or failed evidence, expose secrets, mutate a live target without authorization, require an unsupported environment topology, or claim proof beyond observation.
10. **Separate delivery from release authority.** A broad writing sprint may implement and validate a coherent surface, but it does not grant merge, release, deployment, authentication, or live-target authority. Those actions require their own explicit authorization and current gates.

## Mandatory execution discipline

- Preserve unrelated dirty work; isolate concurrent writers by branch and worktree.
- Keep judgment in skills and deterministic behavior in code, schemas, registries, validators, workflows, and artifacts.
- Treat prompts as artifacts, never as the sole implementation.
- Put material cross-session coordination under `plans/`; a PR description is not the only durable record.
- Protect credentials, personal data, private hostnames, customer evidence, large logs, dumps, and machine-local junk.
- Run focused checks before broader safe validation and never inflate static, synthetic, repository, package, process, transport, or command-ack evidence into runtime or target proof.
- Select `.ai/skills/environment-capability-routing/SKILL.md` before installation, configuration, launch, repair, or certification when the request crosses platforms, machines, shells, frontends, transports, workspace hosts, orchestration runtimes, or agent runtimes.
- Select `.ai/skills/end-to-end-runtime-validation/SKILL.md` after the topology is fixed when operator success crosses shell, process, platform, terminal, TUI, GUI, provider, or application boundaries. The skill owns the detailed stage order, child diagnostics, effective-state readback, user-experience observation, idempotence, rollback, and handoff evidence.
- When safe and authorized, mutate tracked files, validate, commit, push, and open or update the intended PR.
- Preserve the same repair context when a deterministic gate exposes a correctable defect; do not abandon evidence and restart blindly.

## Environment capability and continuity

“Works on this environment,” “auto-configure anywhere,” “continue from my phone,” and similar claims are invalid until the exact environment role and topology are named.

Every cross-environment request must classify five layers independently:

1. **Frontend** — where the operator sees and enters commands.
2. **Transport** — the local process or connection boundary, such as SSH.
3. **Workspace host** — where the repository, working tree, tmux server, and session socket live.
4. **Orchestration runtime** — where AgentSwitchboard setup, routing, validation, worktree, and GNHF control-plane behavior run.
5. **Agent runtime** — where the coding agent, provider/model route, authentication, and model-backed work run.

One registered topology and one role ceiling must be selected:

- `full-runtime-host`;
- `workspace-host`;
- `terminal-client`;
- `local-shell-only`;
- `transport-only`;
- `unsupported`.

The following equivalences are forbidden:

- a terminal frontend equals a workspace host;
- SSH reachability equals a known remote shell or compatible command contract;
- repository presence equals AgentSwitchboard orchestration or agent readiness;
- package presence equals verified capability;
- matching tmux session names on different hosts equal one workspace;
- phone-local tmux equals cross-device continuity;
- Termux equals generic Linux;
- a terminal client equals a full runtime host;
- command acknowledgement equals attachment or behavior;
- hosted CI equals live phone, workstation, remote-host, provider, or operator proof.

A tmux identity is scoped to the workspace host and tmux server/socket plus session. A session named `dev` in Termux and a session named `dev` in WSL are different sessions unless evidence proves both clients reached the same workspace host and tmux server/session identity.

Auto-configuration is not a universal installer. It must execute this order:

`observe -> classify layers -> select topology -> report blockers -> bounded mutation -> effective-state readback -> focused validation -> authorized runtime certification -> proof report`

Unknown operating system, shell, repository identity, tmux server, orchestration runtime, agent runtime, provider/authentication state, persistence boundary, or authority blocks the dependent action. A lower-role topology must not be substituted for a higher-role requested experience without explicitly stating that mismatch.

The Android implementation is currently `terminal-client-implemented`. Phone-local tmux is `local-shell-only` and `device-local-only`. Android cross-device terminal continuity requires a separately classified remote workspace host and the same tmux server/session identity. Native Android AgentSwitchboard orchestration is `unimplemented`; native agent/provider runtime is `unproved`. Cloning the repository and installing `git`, `openssh`, `tmux`, and `curl` does not change those facts.

Validate with `scripts/Test-EnvironmentCapabilityHarness.ps1` and `tests/test_environment_capability_harness.py`, then run device-profile, doctrine, documentation, repository-family, and aggregate harness validators. Live claims additionally require `end-to-end-runtime-validation`.

## Agent-facing interface doctrine (AXI)

Agent-facing commands, reports, tools, and wrappers must be designed for reliable operation at low token cost. The enforceable repository interpretation is derived from the Agent eXperience Interface principles at https://axi.md/.

1. **Token-efficient output.** Return only decision-relevant information by default. Prefer compact structured output; use TOON where compatible and retain JSON where schemas or consumers require it.
2. **Minimal default schemas.** Default list records should expose only the few fields needed for the next decision. Additional fields require an explicit option.
3. **Content truncation.** Bound large text, state the original size, state that truncation occurred, and provide an explicit full-content escape hatch.
4. **Pre-computed aggregates.** Include counts, status summaries, derived readiness, and other values that prevent avoidable follow-up calls.
5. **Definitive empty states.** Return an explicit zero-result or no-match state. Silence is not a valid empty result.
6. **Structured errors and exit codes.** Fail non-interactively with machine-readable error identity, stable exit semantics, and loud rejection of unknown flags. Keep structured results on stdout and diagnostic detail on stderr when the interface supports that separation.
7. **Ambient context.** Directory-scoped startup context must be compact, explicit, and opt-in. Do not install implicit hooks merely to inject context.
8. **Content first.** A no-argument status command should show current actionable state, identity, topology, role ceiling, and readiness rather than only generic help.
9. **Contextual disclosure.** Each result should include the smallest concrete next action or command template needed to continue safely. Carry forward fixed disambiguating values and leave unknown runtime values as placeholders.
10. **Consistent help.** Every agent-facing command exposes concise, predictable help. Help complements contextual next steps rather than replacing them.

When safe, combine action and observation so a mutation returns the resulting state and evidence in the same bounded operation. Do not force an agent to spend another call merely to discover whether the preceding action worked.

## Multi-agent and local-model governance

Pi and other third-party agent runtimes may be evaluated or integrated only through a separately declared implementation sprint. A pasted installer, command line, extension scaffold, video transcript, or remembered API is evidence to investigate, not authority to install or execute.

1. **Verify the upstream contract.** Before adopting a third-party command, path, configuration schema, package name, provider flag, or extension API, verify it against the official source for the pinned version. Record the package identity, version or commit, source URL, supported operating system, expected files, and rollback path.
2. **Treat extensions as executable code.** Agent extensions can inherit the invoking process's permissions. Review their source, dependencies, install scope, filesystem access, subprocess behavior, network behavior, and update mechanism. Prefer project-local, pinned, reviewable configuration over silent global installation.
3. **Prove privacy; do not infer it.** `localhost`, an open-weight model, or a local-looking provider name does not by itself prove that code remains on the machine. A privacy claim requires evidence of the resolved endpoint, listening interface, provider and model identity, authentication behavior, telemetry and update behavior, outbound network activity, logs, persistence, and every fallback route.
4. **Declare orchestration roles.** Multi-agent work must name the architect, builder, validator or adjudicator, designated writer, inputs, outputs, permissions, branch ownership, environment topology, and stop conditions. Reviewers and adjudicators remain read-only unless a separate write lane is declared.
5. **Preserve independent evidence.** Parallel opinions must be captured separately with provider, model, configuration, prompt digest, timestamp, and result status before fusion. Two aliases for the same model or endpoint do not prove independent review.
6. **Make divergence visible.** Fusion must preserve consensus, disagreements, unresolved risks, rejected alternatives, and source attribution. Agreement among models is not proof of correctness and may not erase contradictory evidence.
7. **Separate test authority from implementation.** In an autovalidation lane, the architect-owned acceptance contract is fixed before builder mutation. The builder may not silently weaken, replace, skip, or reinterpret the gate to manufacture a pass. Any gate change requires an explicit reviewed contract revision.
8. **Bound every loop.** Opinion, fusion, repair, and autovalidation loops require maximum attempts, wall-clock or token bounds, no-progress detection, cancellation behavior, and a terminal failure report. Local capacity does not authorize infinite execution.
9. **One designated writer.** Multi-agent orchestration does not override one writer per branch. Concurrent agents write only to disjoint branches or artifacts, and a named convergence owner performs integration after re-inspection.
10. **Log actual execution identity.** Reports must record the agent, provider, model, endpoint class, environment topology, role, branch or worktree, and validation result that actually ran. Requested routing is not execution proof.

No governance-only sprint may claim that Pi, Ollama, LM Studio, a local model, a fusion command, an autovalidation loop, or an Android agent runtime was installed, private, functional, unlimited, or production-ready without the corresponding tracked implementation and runtime evidence.

## Forbidden behaviors

- **Acknowledgment without mutation** when the task safely requires repository change.
- **Plans without execution** when implementation is owned, bounded, and unblocked.
- **Summaries without proof** presented as delivery.
- **Completion claims without running checks** required by the repository or task.
- **Secret or credential exposure** in prompts, logs, commits, fixtures, plans, reports, or PR text.
- **Re-inventing an established principle** in a prompt, skill, capability, workflow, or product surface instead of referencing and extending the canonical owner through its declared contract.
- **Trivial-only progress** that leaves a safely owned coherent vertical slice incomplete, or a giant mixed-scope change that bundles unrelated missions merely to appear broad.
- Destructive Git, force-push, default-branch writes, merge, release, deployment, authentication, or live-target mutation without explicit authority.
- Replacing a healthy canonical contract with a competing file or prompt-only convention.
- Ambiguous empty output, silently ignored flags, interactive prompts in agent automation, or unbounded output when a deterministic compact result is possible.
- Installing or executing unverified third-party agent snippets, packages, extensions, or provider commands as though pasted prose were a tested contract.
- Claiming privacy, model independence, successful fusion, continuous validation, cross-device continuity, remote compatibility, or full runtime readiness from configuration intent, repository presence, package presence, session-name equality, transport reachability, command acknowledgement, or hosted CI alone.

## Runtime event composition

Every claimed runtime event path registers this chain:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

All participating nodes, edges, and event types belong in `.ai/harness/runtime-event-topology.json`. Emitted envelopes are immutable. A root event begins its own correlation chain; each successor receives a new event ID, inherits correlation, names its immediate parent as causation, and advances sequence.

A claim that an event listener or cascade was built requires the corresponding deterministic implementation, topology update, validation, and commit or GitHub evidence. A runtime-success claim additionally requires correlated source, observer, handler, successor or terminal, and sink artifacts from an explicitly authorized runtime lane. Static topology and synthetic fixtures prove lower levels only.

Validate the runtime-event contract with `scripts/Test-RuntimeEventContract.ps1`, then validate registration in the wider harness with `Test-AppHarness.cmd`. Use `end-to-end-runtime-validation` when the claim includes the operator invocation or a complete source-to-sink runtime path across process boundaries.

## Device profiles and launcher ownership

AgentSwitchboard owns separate **Windows Profile**, **Linux Profile**, and **Android Profile** contracts. Platform implementation may differ; one profile must not silently inherit another profile's launcher, shell semantics, environment role, or configuration.

The Windows Profile is WezTerm-backed and has exactly one canonical `open-or-activate` launcher owned by AgentSwitchboard. SysAdminSuite is a delegate and certifier, not a second launcher owner. Raw `wezterm`, `wezterm.exe`, `wezterm-gui.exe`, desktop shortcuts, and consumer repositories may not contain independent lifecycle, discovery, activation, or fallback logic. A missing or uncertified canonical launcher is a blocker.

The Android Profile is currently a Termux terminal client. Its launcher may provide phone-local shell behavior or attach through SSH to a preflighted supported remote workspace host. It may not claim native Windows AgentSwitchboard setup, GNHF, coding-agent/provider readiness, authentication, remote-shell compatibility without classification, durable Android execution, or cross-device continuity from phone-local tmux.

A claim that a profile or launcher was installed, built, repaired, configured, certified, or deployed requires tracked implementation, environment-topology selection, profile registry updates, focused validation, commit or GitHub evidence, and an honest role/proof ceiling. Contract-only doctrine must not claim the launcher exists or that a window, terminal, attachment, agent, or provider behavior was observed.

Validate with `scripts/Test-EnvironmentCapabilityHarness.ps1` and `scripts/Test-DeviceProfileLauncherContract.ps1`, then run the wider doctrine, documentation, repository-family, and aggregate harness validators. Use `end-to-end-runtime-validation` to prove the exact operator command, frontend-to-backend chain, effective configuration, workspace-host identity, tmux server/session identity, open-or-activate behavior, user-visible result, idempotence, and rollback when applicable.

## Public plans

`plans/plan-registry.json` indexes durable public coordination. Plans record mission, ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. Update the machine-readable plan in the implementation branch when material state changes.

Never place secrets, customer data, private hostnames, machine-local paths, provider state, credentials, or raw runtime evidence in a public plan. Plans never grant authentication, merge, deployment, target mutation, secret access, or destructive-Git authority. Use `.ai/skills/public-plan-coordination/SKILL.md` and `scripts/Test-PublicPlanContracts.ps1`.

## Capability, trigger, and skill rules

An action is allowed only when the exact environment exposes the capability, the capability is verified, the task authorizes it, and repository policy permits it. Capability presence is not authority. See `CAPABILITIES.md`.

Triggers select reviewed workflows or skills; they never grant destructive, secret, runtime, authentication, merge, deployment, or target authority. See `TRIGGERS.md`.

Use the smallest applicable skill and follow its inputs, procedure, outputs, deterministic validation, forbidden scope, and stop conditions. See `SKILLS.md`.

## Repository-family contract

`.ai/agent-contract.json` declares the canonical contract. `.ai/harness/repository-family.registry.json` declares operational child entrypoints. Use the read-only status probe before cross-repository work:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1
```

A ready profile proves only observed clone identity and required paths. It does not authorize mutation or prove child validators, environment compatibility, orchestration runtime, agent runtime, or provider readiness. Child adoption occurs through tracked reviewable PRs; local rules may strengthen but not silently weaken the canonical baseline.

## Completion standard

A task is complete only when, at minimum:

- files changed are named;
- validation was actually run, with commands and results reported rather than assumed;
- environment topology and role ceiling are reported when applicable;
- commit SHA exists for a writing sprint;
- push or PR state is reported;
- one exact next command is given.

When an end-to-end route was required, also report the exact operator command, the successful or failed stage, child stdout and stderr evidence, effective-state readback, user-visible observation, idempotence and rollback result when applicable, and the remaining proof gap.

Also report generated-artifact policy, skipped checks, blockers, proof level and proof ceiling, final Git state, and relevant artifact paths. Cross-agent handoffs must be schema-backed and require the receiver to re-inspect current state.
