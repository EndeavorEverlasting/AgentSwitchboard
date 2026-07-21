# Trigger and Routing Contract

Triggers convert repository evidence or explicit requests into a reviewed skill or workflow. A trigger selects procedure; it does not grant authority.

## Trigger precedence

1. explicit owner instruction;
2. repository safety state;
3. active PR, review, and failing validation;
4. repository-local routing rules;
5. canonical fallback mapping.

Safety triggers may narrow or stop work even when a feature trigger is present.

## Canonical trigger map

| Trigger | Evidence | Route |
|---|---|---|
| `repo.new-or-unknown` | unfamiliar repo, placeholder path, stale handoff, uncertain branch | `repo-intake` |
| `repo.dirty-or-conflicted` | unowned changes, conflicts, detached or unsafe state | preserve and isolate, then `repo-intake` |
| `sprint.execute` | scoped request with safe owned files | `bounded-sprint` |
| `plan.coordination-request` | multi-agent, multi-session, multi-wave, cross-PR, sprint-map, launch-pack, or material plan-state request | `public-plan-coordination`; update `plans/` and keep coordination distinct from PR delivery |
| `startup.readiness-request` | startup or agent availability/configuration request | `startup.readiness.report`; read-only guidance without installation or provider calls |
| `harness.proof-request` | one-command proof, synthetic validation, composition observer, node/edge coverage, or PASS/SKIP/FAIL request | `harness.proof.aggregate`; run the offline observer and emit untracked JSON plus English evidence |
| `app.output-context-request` | supplied app, validator, agent, console, JSON, or JSONL output must be minimized and compared with a prompt registry | `app-output-contextualization`; parse supplied output offline, preserve exact execution surface, and emit compact untracked instructions |
| `runtime.event-contract-change` | event envelope, source, observer, listener, handler, successor, sink, correlation, causation, or runtime topology contract changes | `runtime.event-contract.validate`; update deterministic contracts and run `scripts/Test-RuntimeEventContract.ps1` |
| `runtime.event-cascade-request` | request claims an event listener works, a trigger cascades, or a source-to-sink handoff completes | use `runtime-proof` after contract validation; require correlated observed artifacts and explicit runtime authority |
| `profile.launcher-request` | Windows Profile, Linux Profile, Android Profile, WezTerm launcher, open-or-activate, desktop shortcut, duplicate-window prevention, or canonical launcher ownership | `profile.launcher.contract.validate`; inspect the profile registry and require one AgentSwitchboard owner per profile |
| `profile.launch-mode-request` | request distinguishes default open-or-activate from a deliberate separate WezTerm instance, or supplies a named instance identity | `windows-profile-launch-mode-validation`; select exactly one contract workflow and preserve the one-launcher boundary |
| `profile.duplicate-window-observed` | one operator request produced multiple top-level windows, the same workspace appears unexpectedly twice, or two windows attach to one tmux session | `windows-profile-launch-mode-validation` → `duplicate-window-diagnosis`; require correlated before/after inventories and reject process-count-only conclusions |
| `profile.tmux-new-instance-shortcut.install` | request asks for a desktop shortcut, clickable CMD installer, or user-local shortcut refresh for a separate tmux instance | `tmux-new-instance-shortcut` → `install-tmux-new-instance-shortcut`; preserve foreign shortcuts, delegate to the canonical launcher, and emit install/readback evidence |
| `profile.tmux-new-instance-shortcut.double-click` | the installed shortcut is invoked or its resulting window/session behavior must be proved | `tmux-new-instance-shortcut` → `launch-tmux-new-instance`; for completion also use `end-to-end-runtime-validation` across shortcut, PowerShell, WSL, tmux, and WezTerm boundaries |
| `profile.consumer-certification-request` | SysAdminSuite or another child claims profile consumption or certification | require a separate consumer PR that delegates to the exact canonical launcher and proves no competing lifecycle or raw frontend fallback |
| `action.claimed` | prompt claims install, setup, build, execute, repair, configure, upgrade, deploy, merge, or release | `action.commitment.validate`; require mutation, validation, and commit or GitHub proof |
| `powershell.interactive-snippet` | PowerShell intended for interactive copy/paste | `powershell-interactive-execution`; preserve complete syntax units |
| `gnhf.prompt-request` | explicit GNHF prompt request | `gnhf-prompt-compilation`; output a copy-ready launch artifact |
| `gnhf.test-only` | test, smoke, provider probe, fixture, or contract-only run | apply `gnhf.test-timeout.enforce`; one iteration and at most 30 seconds wall clock or per iteration |
| `provider.deepseek-request` | selected route uses `deepseek/*` | apply `deepseek.usage-window.evaluate`; block premium, unknown, missing, stale, or unverified state |
| `review.findings` or `validation.requested` | review findings, proof gap, skipped checks, or contract drift | `evidence-validation` |
| `integration.requested` | stacked PRs, consumed commits, branch convergence | `pr-integration` |
| `runtime.requested` | launcher, installer, behavior, harness, or environment proof contained within one bounded runtime | `runtime-proof` |
| `runtime.end-to-end-request` | exact operator command crosses shells, child processes, WSL, tmux, WezTerm, TUI, GUI, provider, application, installer, launcher, or configuration boundaries | `end-to-end-runtime-validation`; require per-stage diagnostics, effective-state and user-experience readback, idempotence or rollback when applicable, and one exact next command |
| `docs.contract-change` | AGENTS, skills, capabilities, triggers, schemas, governance | `bounded-sprint` plus doctrine and documentation validators |
| `tool.missing-or-unhealthy` | command absent or bounded probe fails | reuse, repair, install, skip, or block according to scope |
| `gnhf.runtime-repair-required` | required provider-route capability absent | repair through the capability installer; do not react only to an unpublished version |
| `gnhf.model-selection-required` | provider-backed run names an exact provider/model | route selection through OpenCode unless the installed GNHF binary exposes a verified model flag |
| `scope.collision` | two writers own overlapping paths | stop one lane or create isolation |
| `secret-or-personal-data` | credentials, tokens, customer data, or private evidence | stop, sanitize, and escalate |
| `live-target-mutation` | external machine, service, deployment, save, or customer target | require explicit authority and runtime-proof boundary |
| `repeated-repair-failure` | bounded retries exhausted | checkpoint and escalate |

## Public plan invariant

`plan.coordination-request` selects a public coordination artifact, not product logic or authority. Material ownership, dependency, task, proof, or handoff changes belong in a schema-valid plan, normally in the implementation branch. PR prose must not become the only durable record.

## Startup readiness invariant

`startup.readiness-request` is read-only. It may inspect existing fleet state and emit local JSON and guidance. It must not install, authenticate, read credentials, contact a hosted model, mutate a repository, or claim adapter presence proves provider readiness.

## Synthetic harness observer invariant

`harness.proof-request` routes to `scripts/Test-AppHarness.ps1`. The observer reads `.ai/harness/app-composition.graph.json`, verifies required nodes and edges, runs only graph-listed validators marked safe offline, and emits untracked JSON and English artifacts outside the repository.

A required node without an edge, a dangling edge, a disconnected route, an unsafe validator, or a broken required validator is a failure. Missing optional MCP/LSP readiness is an honest skip. Static topology proves registered composition only.

## App-output context invariant

`app.output-context-request` accepts output already captured by the operator. It requires a public source label, a valid `ai-harness-prompt-registry/v1` registry, an exact `regular_ai_prompt` or `gnhf_launch_artifact` surface, and an output directory outside the repository.

The route hashes but does not copy raw output, redacts common credentials and private identifiers, extracts bounded signals and excerpts, and ranks prompt entries only inside the requested execution surface. A ranked prompt is guidance, not authorization. Invalid registries, ambiguous surfaces, unsafe output paths, or unredactable private evidence block the route.

## Runtime event invariant

`runtime.event-contract-change` requires the typed envelope, runtime topology, correlation and causation rules, artifact policy, doctrine references, and focused validator to remain coherent.

`runtime.event-cascade-request` is a higher proof request. Before runtime execution it must name the registered source, observer, handler, successor or terminal event, and evidence sink. Root events use their event ID as correlation and no causation; successors inherit correlation, identify the immediate parent as causation, and advance sequence.

Contract and synthetic fixture success do not prove runtime delivery. A runtime completion claim requires correlated observed source, observer, handler, successor or terminal, and sink artifacts from an explicitly authorized runtime lane. Missing or contradictory chain evidence blocks completion.

## End-to-end runtime invariant

`runtime.end-to-end-request` selects `.ai/skills/end-to-end-runtime-validation/SKILL.md`. The route freezes the exact operator invocation, names each boundary, proves lower floors first, captures each child command with stdout, stderr, exit code, and timing, reads back effective state, observes the requested user experience, and checks idempotence or rollback when applicable.

A parent process error that reports only a child exit code is incomplete evidence. A configuration file, successful parser, passing CI run, parent exit zero, command acknowledgement, or manual workaround cannot promote the operator path to end-to-end success. Repair remains in the same evidence chain, and the complete operator path is rerun after the failed stage is fixed.

## Device profile invariant

`profile.launcher-request` requires `.ai/harness/device-profile-registry.json` and the canonical launcher policy to remain coherent. The Windows Profile is WezTerm-backed, idempotent `open-or-activate`, and owned only by AgentSwitchboard. Linux and Android are separate profile implementations; Android configuration may differ.

Raw `wezterm`, `wezterm.exe`, `wezterm-gui.exe`, desktop shortcuts, and consumer repositories are not independent lifecycle owners. SysAdminSuite may locate, invoke, and certify the exact AgentSwitchboard launcher, but a missing or uncertified launcher is `blocked`, not a fallback opportunity.

Contract success proves ownership and fixture shape only. A runtime claim requires observed evidence for both `opened` and `activated`, duplicate-prevention, and the terminal result. SysAdminSuite certification requires its own tracked consumer PR and validators.

## Windows Profile launch-mode invariant

`profile.launch-mode-request` selects `tooling/profiles/windows/harness/launch-modes/workflows/launch-request-intake.workflow.json`. An omitted mode means `open-or-activate`. That mode converges one stable workspace identity to one visible window: an existing identity is activated and a missing identity may create at most one new top-level window.

`new-instance` is explicit only. It requires a stable instance ID, exactly one additional top-level WezTerm window, a distinct frontend process, and a unique tmux session. Repeating the same instance ID must activate that named instance instead of creating another window. Two windows attached to the same tmux session are duplicate views of one workspace, not separate instances.

`profile.duplicate-window-observed` is fail-closed. One request that creates more than one top-level window, repeats the same workspace identity unexpectedly, or exposes one instance ID in multiple windows selects duplicate diagnosis and cannot be reported as success. Static fixtures prove classification only; workstation behavior requires the exact operator command through `end-to-end-runtime-validation`.

## tmux new-instance shortcut invariant

`profile.tmux-new-instance-shortcut.install` selects `Install-TmuxNewInstanceShortcut.cmd`, which must delegate to `tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1`. The installer copies the tracked canonical launcher and manifest to a user-local AgentSwitchboard root, creates or refreshes only an owned shortcut, reads the shortcut back, and never launches tmux or WezTerm during installation.

`profile.tmux-new-instance-shortcut.double-click` delegates to `tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1` with explicit `new-instance` and automatic identity allocation. The route reserves bare `dev`, selects the smallest unused positive suffix, creates and verifies one unique tmux session, and requests `wezterm start --always-new-process` with a unique workspace and window class. An existing explicit instance blocks rather than receives another window. Static and install-readback checks do not prove a visible terminal; completion requires the exact shortcut through `end-to-end-runtime-validation`.

## Doctrine invariant

`action.claimed` is fail-closed. A prompt that claims action but permits acknowledgment, advice, a plan, summary, or handoff instead of mutation and proof is invalid. Event-listener, cascade, profile, launcher, and certification claims that permit architecture-only output are also invalid.

The PowerShell trigger preserves compound syntax. Test-only GNHF limits apply even when token or iteration caps exist. DeepSeek requires a fresh verified standard or discounted rate state.

## GNHF invariant

A GNHF prompt request is an artifact-type selector and uses `.ai/skills/gnhf-prompt-compilation/SKILL.md`. Do not substitute a sprint map, plan-only response, ordinary repo-agent prompt, or essay. When spawnability is unknown, emit the bounded probe first.

## Trigger payload

A routed workflow receives repository and branch or worktree, PR or sprint, plan and task when applicable, trigger and evidence, lane, owned and forbidden scope, expected artifacts, acceptance criteria, capabilities and blockers, selected procedure, limits, validation order, evidence requirement, and completion gate.

## Automatic stop triggers

Stop or escalate when work would overwrite unowned changes; a required capability is unknown; scope crosses a forbidden boundary; writers collide; a gate exposes security or data-loss risk; merge, deployment, secret, destructive Git, or live mutation lacks authority; retries are exhausted; evidence contradicts the plan; test timing or DeepSeek gates fail; the app graph is broken; app-output context would persist raw or cross-surface data; runtime event evidence is incomplete; an end-to-end stage loses child diagnostics, effective-state readback, rollback safety, or exact environment identity; a launch-mode request is ambiguous, lacks a unique instance identity, creates multiple windows, or reuses one tmux session as two claimed instances; a shortcut collision is foreign, a new-instance route reuses bare `dev`, an explicit instance already exists, session allocation is exhausted, or the WezTerm command omits `--always-new-process`; or a profile has competing owners, raw frontend fallback, independent shortcut logic, cross-profile substitution, or an unproved open-or-activate claim.

## No implicit authority

The presence of a trigger, plan, startup report, event observer, topology registry, profile registry, launch-mode registry, shortcut registry, app-output packet, end-to-end skill, or capability never authorizes installation, push, merge, release, deployment, target mutation, prompt execution, provider access, secret access, or destructive cleanup unless the task and repository contract explicitly allow it.
