# Agent Operating Contract

`AGENTS.md` is the root operating authority for AgentSwitchboard. It is the single source of truth for precedence, universal safety, sprint discipline, proof, and routing law. Detailed triggered clauses remain normative in `docs/governance/agent-operating-details.md`; they are not ambient startup context.

## Agent operating principles

- **Evidence before action.** Current repository/runtime evidence outranks memory, stale handoffs, and filenames.
- **Floor before furniture.** Establish identity, authority, dependencies, scope, governing contracts, and proof ceiling before convenience work or mutation.
- **Bounded sprints with declared scope.** Every writing sprint declares mission, owned/forbidden scope, artifacts, validation, and proof ceiling before mutation.
- **One writer per branch.** Parallel writers require isolated branches/worktrees, disjoint ownership, and one convergence owner.
- **Reuse before replacing.** Search canonical code, schemas, registries, validators, workflows, skills, plans, and helpers before creating alternatives.
- **No completion without proof.** Claims, plans, summaries, generated text, and process exit alone are not completion.

## Precedence

Instruction precedence when instructions conflict:
1. Platform, security, legal, and repository-owner instructions.
2. This governance contract, triggered governance details, and the nearest nested `AGENTS.md`.
3. Task-specific prompts.
4. Generic defaults.

Local law may strengthen but never silently weaken a higher-priority boundary. `CLAUDE.md` and other tool adapters specialize execution only.

## Mandatory sprint declaration

Before every writing sprint, state:
- repo and branch;
- lane and mission;
- owned scope and forbidden scope;
- expected artifacts and validation commands;
- proof ceiling: the highest claim the planned evidence can support.

If stale remote state, placeholders, or unknown ownership prevent that declaration, do read-only intake first. Preserve existing work and keep mutation inside owned scope.

## Universal operating law

- Repository knowledge is compiled state. Search canonical law, architecture/specs, manifests/registries, skills, validators/tests, plans/reports, implementation helpers, and relevant history before inventing or searching outward. External research or a new abstraction requires an explicit unresolved gap.
- Keep judgment in skills; deterministic behavior belongs in code, schemas, registries, validators, workflows, and artifacts.
- Preserve unrelated dirty work; destructive Git is not a cleanup shortcut.
- Protect credentials, personal/customer data, private hostnames/source, large dumps, and machine-local evidence.
- Never weaken, skip, reinterpret, or rewrite a valid gate to manufacture a pass.
- Static/synthetic evidence never proves runtime, live-target, provider, deployment, or user-visible success.
- A task or launch pack grants bounded work only; it does not grant secrets, destructive Git, merge, deployment, live-target mutation, provider access, or higher proof.
- When safe authorized work remains, continue through mutation, validation, evidence, commit, push, and requested PR work. Stop only at a real authority, capability, safety, ownership, or dependency blocker.
- Merge/release/deployment/live-target authority must be explicit and current; recheck heads and gates just in time.

## Progressive disclosure reading order

1. Read this file and the nearest nested `AGENTS.md`.
2. Read `HARNESS.md` only for 50k repository orientation.
3. Select one 30k domain through `tooling/harness/context/context.routes.json`; load only its `defaultLoad`.
4. Select one 15k workflow; load only its `defaultLoad`, then demand-load implementation, schemas, fixtures, reports, history, and validator source as required.
5. Load `SKILLS.md`, `CAPABILITIES.md`, `TRIGGERS.md`, `CODEBASE_MAP.md`, `README.md`, `CONTRIBUTING.md`, plans, schemas, reports, or implementation only when the selected route/task requires them.
6. Use `tooling/harness/context/glossary.json` only for unclear repository terms.

Repository-family work loads `.ai/harness/repository-family.registry.json` and the target profile. Public-plan work loads `plans/plan-registry.json` and `.ai/skills/public-plan-coordination/SKILL.md` only after that trigger is selected.

## Triggered governance detail

Load `docs/governance/agent-operating-details.md` for launch/dependency gates, broad multi-surface sprints, cross-device transport, live continuation, AXI/interface design, multi-agent/local-model orchestration, privacy proof, autovalidation loops, or another clause not fully stated above.

Relevant policy pairs:
- harness doctrine: `docs/governance/harness-doctrine.md` + `.ai/harness/harness-doctrine.policy.json`;
- runtime events/evidence sinks: `docs/governance/runtime-event-contract.md` + `.ai/harness/runtime-event-contract.policy.json`; validate with `Test-RuntimeEventContract.ps1`;
- device/profile launchers: `docs/governance/device-profile-launcher-contract.md` + `.ai/harness/device-profile-launcher.policy.json`; validate with `Test-DeviceProfileLauncherContract.ps1`.

For a PR or sprint governed by harness doctrine, the selected route carries its validation order and proof boundary.

## Sprint and proof contract

Resolve branch, scope, dependencies/collisions, canonical owner, artifacts, validation order, proof ceiling, and commit/push/PR expectation before mutation. Run focused owning validators before broader safe gates. Preserve failing evidence and repair the first deterministic boundary. Process exit code zero alone is not delivery proof.

Operator-visible shell/process/platform/TUI/GUI work routes to `.ai/skills/end-to-end-runtime-validation/SKILL.md`. Repository operation routes through `HARNESS.md` and progressive context. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md` are demand-loaded catalogs. `.ai/agent-contract.json` is the machine-readable repository contract.

## Completion standard

A task is complete only when:
- changed files are named;
- required validation was actually run and results recorded;
- a commit SHA exists for repository mutation;
- push or PR state is reported;
- proof corresponds to the final candidate identity;
- gaps, skipped checks, and blockers are explicit; and
- one exact next command is given unless no safe actionable work remains.

## Forbidden behaviors

- Acknowledgment without mutation when authorized mutation is required.
- Plans without execution when safe executable work remains.
- Summaries without proof.
- Completion claims without running checks.
- Secret or credential exposure.
- Destructive cleanup, force-push, or silent scope expansion used as a shortcut.

## Compatibility and preserved authority

The detailed appendix preserves prior unique operating rules. If this compact root and that appendix appear to conflict, apply the stricter safe interpretation and repair routing rather than silently weakening either source.
