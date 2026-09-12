# Agent Operating Contract

`AGENTS.md` is the root operating authority and single source of truth for how agents operate in AgentSwitchboard. Detailed triggered rules remain normative in `docs/governance/agent-operating-details.md`; they are incorporated by reference, not loaded as ambient context.

## Agent operating principles

- **Evidence before action.** Current repository/runtime evidence outranks memory and stale handoffs.
- **Floor before furniture.** Establish identity, authority, dependencies, scope, governing contracts, and proof ceiling before convenience work or mutation.
- **Bounded sprints with declared scope.** Every writing sprint declares mission, owned/forbidden scope, artifacts, validation, and proof ceiling.
- **One writer per branch.** Parallel writers require isolated branches/worktrees, disjoint ownership, and one convergence owner.
- **Reuse before replacing.** Search canonical code, schemas, registries, validators, workflows, skills, plans, and helpers before creating alternatives.
- **No completion without proof.** Claims, plans, summaries, generated text, and process exit alone are not completion.

## Precedence

Instruction precedence when instructions conflict:
1. Platform, security, legal, and repository-owner instructions.
2. This governance contract, triggered governance details, and the nearest nested `AGENTS.md`.
3. Task-specific prompts.
4. Generic defaults.

`CLAUDE.md` and other adapters may specialize execution but may not silently weaken a higher-priority boundary.

## Mandatory sprint declaration

Before every writing sprint, state:
- repo and branch;
- lane and mission;
- owned scope and forbidden scope;
- dependencies/collisions and safe parallel work when applicable;
- canonical owner, source of truth, and interfaces when work spans surfaces;
- expected artifacts and validation commands;
- proof ceiling;
- commit, push, and PR expectation.

If remote state or ownership is uncertain, perform read-only intake first. Preserve existing work and keep mutation inside owned scope.

## Universal operating law

- Repository knowledge is compiled state. Search repository law, architecture/specs, manifests/registries, skills, validators/tests, plans/reports, helpers, and relevant history before inventing or searching outward. External research or a new abstraction requires an explicit unresolved gap.
- Keep judgment in skills; deterministic behavior belongs in code, schemas, registries, validators, workflows, and artifacts.
- Preserve unrelated dirty work. Destructive Git is not cleanup.
- Protect credentials, personal/customer data, private hostnames/source, dumps, and machine-local evidence.
- Never weaken or skip a valid gate to manufacture a pass.
- Static/synthetic evidence never proves runtime, live-target, provider, deployment, or user-visible success.
- A task or launch pack grants bounded work only; it does not grant secrets, destructive Git, merge, deployment, live-target mutation, provider access, or higher proof.
- Continue safe authorized work through mutation, validation, evidence, commit, push, and requested PR work. Stop only at a real authority, capability, safety, ownership, or dependency blocker.
- Merge/release/deployment/live-target authority must be explicit and current.

## Progressive disclosure reading order

1. Read this file and the nearest nested `AGENTS.md`.
2. Read `HARNESS.md` only for 50k repository orientation.
3. Select one 30k domain through `tooling/harness/context/context.routes.json`; load only its `defaultLoad`.
4. Select one 15k workflow; load only its `defaultLoad`; demand-load deeper implementation/evidence only as needed.
5. Load `SKILLS.md`, `CAPABILITIES.md`, `TRIGGERS.md`, `CODEBASE_MAP.md`, plans, schemas, reports, or implementation only when the selected route/task requires them.
6. Use `tooling/harness/context/glossary.json` only for unclear repository terms.

Repository-family work loads `.ai/harness/repository-family.registry.json`. Public-plan work loads `plans/plan-registry.json` and `.ai/skills/public-plan-coordination/SKILL.md` after that trigger is selected. `.ai/agent-contract.json` remains the machine-readable repository contract.

## Triggered governance detail

Load `docs/governance/agent-operating-details.md` for launch/dependency gates, broad multi-surface sprints, cross-device transport, live continuation, AXI/interface design, multi-agent/local-model orchestration, privacy proof, autovalidation loops, or another clause not fully stated here.

Relevant policy pairs:
- harness doctrine: `docs/governance/harness-doctrine.md` + `.ai/harness/harness-doctrine.policy.json`;
- runtime events/evidence sinks: `docs/governance/runtime-event-contract.md` + `.ai/harness/runtime-event-contract.policy.json`; validate with `Test-RuntimeEventContract.ps1`;
- device/profile launchers: `docs/governance/device-profile-launcher-contract.md` + `.ai/harness/device-profile-launcher.policy.json`; validate with `Test-DeviceProfileLauncherContract.ps1`.

For a PR or sprint governed by harness doctrine, use its selected route, validation order, and proof boundary.

## Sprint and proof contract

Before mutation, resolve branch, scope, dependencies/collisions, canonical owner, artifacts, validation order, proof ceiling, and commit/push/PR expectation. Run focused owning validators before broader gates. Preserve failing evidence and repair the first deterministic boundary. Process exit code zero alone is not delivery proof.

Operator-visible work crossing shell/process/platform/terminal/TUI/GUI routes to `.ai/skills/end-to-end-runtime-validation/SKILL.md`. Repository operation routes through `HARNESS.md` and progressive context.

## Completion standard

A task is complete only when:
- changed files are named;
- required validation actually ran and results are recorded;
- a commit SHA exists for repository mutation;
- push or PR state is reported;
- proof matches the final candidate identity;
- gaps, skipped checks, and blockers are explicit; and
- one exact next command is given unless no safe actionable work remains.

## Forbidden behaviors

- Acknowledgment without mutation when authorized mutation is required.
- Plans without execution when safe executable work remains.
- Summaries without proof.
- Completion claims without running checks.
- Secret or credential exposure.
- Destructive cleanup, force-push, or silent scope expansion as a shortcut.

## Compatibility and preserved authority

The detailed appendix preserves prior unique operating rules. If this compact root and that appendix appear to conflict, apply the stricter safe interpretation and repair routing rather than silently weakening either source.
