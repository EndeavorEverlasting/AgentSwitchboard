# Agent Operating Contract

`AGENTS.md` is the root operating authority for AgentSwitchboard. It owns precedence, universal safety, proof discipline, and routing law. Detailed clauses from the prior root contract are preserved byte-for-byte in `docs/governance/agent-operating-details.md` and are incorporated by reference when their trigger applies; they are not ambient app context.

## Precedence

1. Platform, security, legal, and repository-owner instructions.
2. This governance contract, including triggered governance details and the nearest nested `AGENTS.md`.
3. Task-specific prompts.
4. Generic defaults.

Local product law may strengthen but never silently weaken a higher-priority boundary. `CLAUDE.md` and other tool adapters specialize execution only.

## Universal operating law

- Evidence before action; current repository/runtime evidence outranks memory, stale handoffs, filenames, and timestamps.
- Establish repository identity, authority, owner, dependencies, safe scope, and proof ceiling before mutation.
- One active writer per branch/worktree. Parallel writers require disjoint ownership and a convergence owner.
- Reuse healthy code, schemas, registries, validators, workflows, and skills before creating alternatives.
- Keep judgment in skills; deterministic behavior belongs in code, schemas, registries, validators, workflows, and artifacts.
- Preserve unrelated dirty work. Never use destructive Git as a cleanup shortcut.
- Protect credentials, personal/customer data, private hostnames, private source, large dumps, and machine-local evidence.
- Do not weaken, skip, reinterpret, or rewrite a valid gate to manufacture a pass.
- Static/synthetic evidence never proves runtime, live-target, provider, deployment, or user-visible success.
- A task or launch pack selects bounded work; it does not grant secrets, destructive Git, merge, deployment, live-target mutation, provider access, or higher proof.
- When safe work remains inside granted authority, continue through mutation, validation, evidence, commit, push, and requested PR work. Stop only at a real authority, capability, safety, ownership, or dependency blocker.
- Merge/release/deployment/live-target authority must be explicit and current. Recheck exact heads and gates just in time.

## Progressive disclosure reading order

1. Read this file and the nearest nested `AGENTS.md`.
2. Read `HARNESS.md` only for 50k repository orientation.
3. Select one 30k domain through `tooling/harness/context/context.routes.json`; load only that domain's `defaultLoad` set.
4. Select one 15k workflow; load only its `defaultLoad` set, then demand-load implementation, schemas, fixtures, reports, history, and validator source when the task actually needs them.
5. Load `SKILLS.md`, `CAPABILITIES.md`, `TRIGGERS.md`, `CODEBASE_MAP.md`, `README.md`, `CONTRIBUTING.md`, plans, full schemas, reports, or implementation files only when the selected route or task explicitly requires them. Do not preload catalogs merely because they exist.
6. Use `tooling/harness/context/glossary.json` only when a repository term is unclear.

For repository-family work, load `.ai/harness/repository-family.registry.json` and the target profile before assuming paths or authority. Public-plan work loads `plans/plan-registry.json` and `.ai/skills/public-plan-coordination/SKILL.md` only after that trigger is selected.

## Triggered governance detail

Load `docs/governance/agent-operating-details.md` when the task involves launch packs or dependency gates, broad multi-surface sprints, cross-device command transport, live continuation channels, AXI/interface design, multi-agent or local-model orchestration, privacy proof, autovalidation loops, or another clause not fully stated above. That appendix remains normative; progressive disclosure changes *when* it is loaded, not its authority.

Also load the owning policy pair when relevant:

- general harness doctrine: `docs/governance/harness-doctrine.md` + `.ai/harness/harness-doctrine.policy.json`;
- runtime events/listeners/evidence sinks: `docs/governance/runtime-event-contract.md` + `.ai/harness/runtime-event-contract.policy.json`; validate changes with `Test-RuntimeEventContract.ps1`;
- device/profile launchers and open-or-activate behavior: `docs/governance/device-profile-launcher-contract.md` + `.ai/harness/device-profile-launcher.policy.json`; validate changes with `Test-DeviceProfileLauncherContract.ps1`.

For a PR or sprint governed by harness doctrine, the selected route must carry its validation order and proof boundary; the deep appendix supplies the detailed launch/dependency rules only when that work triggers them.

## Sprint and proof contract

Before mutation, resolve repository/branch, lane/mission, owned and forbidden scope, dependencies/collisions, canonical owner, expected artifacts, validation order, proof ceiling, and commit/push/PR expectation. If placeholders or unknown ownership prevent that declaration, do read-only intake first.

Run focused owning validators before broader safe gates. Preserve failing evidence and repair the first deterministic boundary without abandoning context. Process exit code zero alone is not delivery proof; record exact Git/PR/runtime evidence appropriate to the claimed level.

Operator-visible work crossing shell/process/platform/terminal/TUI/GUI routes to `.ai/skills/end-to-end-runtime-validation/SKILL.md`. Repository operation routes through `HARNESS.md` and the progressive context registry. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md` remain canonical catalogs, but they are demand-loaded catalogs rather than startup payloads. `.ai/agent-contract.json` remains the machine-readable repository contract.

## Compatibility and preserved authority

The detailed governance appendix is the exact pre-factoring root contract and exists to prove no unique operating rule was deleted during this information-architecture change. If this compact root and that appendix appear to conflict, apply the stricter safe interpretation and repair the routing contract rather than silently weakening either source.
