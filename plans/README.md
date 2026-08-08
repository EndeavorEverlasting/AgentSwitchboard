# Public Plans

`plans/` is the repository-owned coordination surface for human and AI contributors.

A **plan** and a **pull request** are related but different:

- a plan records intended work, ownership, dependencies, collision boundaries, proof gates, artifacts, and handoffs in a machine-readable form;
- a branch or pull request transports and reviews tracked changes that implement or revise a plan;
- a plan may exist before a branch, span several pull requests, survive a superseded pull request, or close without product code when evidence rejects the work;
- a pull request must not become the only place where agents can discover coordination state.

## Required layout

- `plan-registry.json` — public index of tracked plans.
- `schemas/public-plan.schema.json` — canonical plan contract.
- `active/` — proposed, active, or blocked work.
- `archive/` — completed, superseded, rejected, or retired plans when archival is useful.

## Agent entry procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, and `plans/plan-registry.json`.
2. Reinspect Git, open pull requests, validators, and current repository evidence.
3. Select the smallest active plan whose dependencies are satisfied and whose owned files do not collide with another writer.
4. Update the plan task and evidence fields in the same branch or PR as the implementation when coordination state changes materially.
5. Never mark a task complete from prose, an ACK, or process exit alone. Attach the required commit, artifact, validator, CI, runtime, or operator evidence.
6. Keep secrets, local paths, raw runtime evidence, customer data, and provider state out of public plans.

## Coordination modes

Ordinary plans omit `coordinationMode` and keep the existing execution-coordination behavior.

A plan may opt into `coordinationMode.kind: decision-frontier` when its destination is known but the executable route is still too uncertain to pre-slice safely. This is an additive extension of `agentswitchboard.public-plan.v1`; existing plans do not need migration.

Decision-frontier plans use the existing `tasks[]` array as the single decision-ticket authority:

- `coordinationMode.destination` states what the planning effort is trying to make sufficiently clear;
- `tasks[]` hold precise decisions or investigations, not speculative implementation slices;
- `tasks[].dependencies` encode blockers;
- a frontier task is derived from `status: ready`, satisfied dependencies, and `owner: unassigned` rather than stored in a second list;
- `coordinationMode.notYetSpecified` is in-scope fog that is not precise enough to become a task yet;
- `coordinationMode.outOfScope` records destination-scope exclusions and is distinct from `forbiddenScope`, which remains the stronger safety/authority boundary;
- `coordinationMode.executionAllowed` is fixed to `false`; once the route is clear, hand execution to an ordinary bounded sprint or execution plan.

The provenance and semantic mapping for this mode live at `tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json`. That manifest is attribution/adoption metadata, not a runtime dependency or proof artifact.

## Lifecycle

Plans use one of:

- `proposed`
- `active`
- `blocked`
- `completed`
- `superseded`
- `rejected`
- `retired`

Task status is independent and uses `pending`, `ready`, `in-progress`, `blocked`, `completed`, `skipped`, or `rejected`.

## Public-plan boundary

Plans are coordination contracts, not product implementation. Application behavior belongs in code and domain contracts. Skills describe reusable procedure. Capabilities expose reusable operations. Triggers route deterministic conditions. PRs and commits provide delivery evidence.
