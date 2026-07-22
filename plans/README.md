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
