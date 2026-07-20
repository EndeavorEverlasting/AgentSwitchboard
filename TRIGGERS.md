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
| `runtime.event-contract-change` | event envelope, source, observer, listener, handler, successor, sink, correlation, causation, or runtime topology contract changes | `runtime.event-contract.validate`; update deterministic contracts and run `scripts/Test-RuntimeEventContract.ps1` |
| `runtime.event-cascade-request` | request claims an event listener works, a trigger cascades, or a source-to-sink handoff completes | use `runtime-proof` after contract validation; require correlated observed artifacts and explicit runtime authority |
| `profile.launcher-request` | Windows Profile, Linux Profile, Android Profile, WezTerm launcher, open-or-activate, desktop shortcut, duplicate-window prevention, or canonical launcher ownership | `profile.launcher.contract.validate`; inspect the profile registry and require one AgentSwitchboard owner per profile |
| `profile.consumer-certification-request` | SysAdminSuite or another child claims profile consumption or certification | require a separate consumer PR that delegates to the exact canonical launcher and proves no competing lifecycle or raw frontend fallback |
| `action.claimed` | prompt claims install, setup, build, execute, repair, configure, upgrade, deploy, merge, or release | `action.commitment.validate`; require mutation, validation, and commit or GitHub proof |
| `powershell.interactive-snippet` | PowerShell intended for interactive copy/paste | `powershell-interactive-execution`; preserve complete syntax units |
| `gnhf.prompt-request` | explicit GNHF prompt request | `gnhf-prompt-compilation`; output a copy-ready launch artifact |
| `gnhf.test-only` | test, smoke, provider probe, fixture, or contract-only run | apply `gnhf.test-timeout.enforce`; one iteration and at most 30 seconds wall clock or per iteration |
| `provider.deepseek-request` | selected route uses `deepseek/*` | apply `deepseek.usage-window.evaluate`; block premium, unknown, missing, stale, or unverified state |
| `review.findings` or `validation.requested` | review findings, proof gap, skipped checks, or contract drift | `evidence-validation` |
| `integration.requested` | stacked PRs, consumed commits, branch convergence | `pr-integration` |
| `runtime.requested` | launcher, installer, behavior, harness, or environment proof | `runtime-proof` |
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

## Runtime event invariant

`runtime.event-contract-change` requires the typed envelope, runtime topology, correlation and causation rules, artifact policy, doctrine references, and focused validator to remain coherent.

`runtime.event-cascade-request` is a higher proof request. Before runtime execution it must name the registered source, observer, handler, successor or terminal event, and evidence sink. Root events use their event ID as correlation and no causation; successors inherit correlation, identify the immediate parent as causation, and advance sequence.

Contract and synthetic fixture success do not prove runtime delivery. A runtime completion claim requires correlated observed source, observer, handler, successor or terminal, and sink artifacts from an explicitly authorized runtime lane. Missing or contradictory chain evidence blocks completion.

## Device profile invariant

`profile.launcher-request` requires `.ai/harness/device-profile-registry.json` and the canonical launcher policy to remain coherent. The Windows Profile is WezTerm-backed, idempotent `open-or-activate`, and owned only by AgentSwitchboard. Linux and Android are separate profile implementations; Android configuration may differ.

Raw `wezterm`, `wezterm.exe`, `wezterm-gui.exe`, desktop shortcuts, and consumer repositories are not independent lifecycle owners. SysAdminSuite may locate, invoke, and certify the exact AgentSwitchboard launcher, but a missing or uncertified launcher is `blocked`, not a fallback opportunity.

Contract success proves ownership and fixture shape only. A runtime claim requires observed evidence for both `opened` and `activated`, duplicate-prevention, and the terminal result. SysAdminSuite certification requires its own tracked consumer PR and validators.

## Doctrine invariant

`action.claimed` is fail-closed. A prompt that claims action but permits acknowledgment, advice, a plan, summary, or handoff instead of mutation and proof is invalid. Event-listener, cascade, profile, launcher, and certification claims that permit architecture-only output are also invalid.

The PowerShell trigger preserves compound syntax. Test-only GNHF limits apply even when token or iteration caps exist. DeepSeek requires a fresh verified standard or discounted rate state.

## GNHF invariant

A GNHF prompt request is an artifact-type selector and uses `.ai/skills/gnhf-prompt-compilation/SKILL.md`. Do not substitute a sprint map, plan-only response, ordinary repo-agent prompt, or essay. When spawnability is unknown, emit the bounded probe first.

## Trigger payload

A routed workflow receives repository and branch or worktree, PR or sprint, plan and task when applicable, trigger and evidence, lane, owned and forbidden scope, expected artifacts, acceptance criteria, capabilities and blockers, selected procedure, limits, validation order, evidence requirement, and completion gate.

## Automatic stop triggers

Stop or escalate when work would overwrite unowned changes; a required capability is unknown; scope crosses a forbidden boundary; writers collide; a gate exposes security or data-loss risk; merge, deployment, secret, destructive Git, or live mutation lacks authority; retries are exhausted; evidence contradicts the plan; test timing or DeepSeek gates fail; the app graph is broken; runtime event evidence is incomplete; or a profile has competing owners, raw frontend fallback, independent shortcut logic, cross-profile substitution, or an unproved open-or-activate claim.

## No implicit authority

The presence of a trigger, plan, startup report, event observer, topology registry, profile registry, or capability never authorizes installation, push, merge, release, deployment, target mutation, secret access, or destructive cleanup unless the task and repository contract explicitly allow it.
