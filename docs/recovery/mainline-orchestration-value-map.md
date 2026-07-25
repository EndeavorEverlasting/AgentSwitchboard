# Mainline GNHF Orchestration Value Map

This map records the value preserved by converging the AgentSwitchboard mainline orchestration contract (P00) with the BlacksmithGuild callable operation surface (P01) and the one-command installed adapter (P02).

## P00: AgentSwitchboard orchestration spine

- **Prompt queue** (`tooling/gnhf/schemas/prompt-queue.schema.json`) lets a human or higher-level harness define a multi-stage, bounded GNHF run without hard-coding stage order in a launcher.
- **Queue plan** (`tooling/gnhf/schemas/queue-plan.schema.json`) is the deterministic, dependency-resolved compilation of a prompt queue. It can be reviewed before any agent starts work.
- **Lane result** (`tooling/gnhf/schemas/lane-result.schema.json`) records what each stage proved, its blockers, and the next command, without claiming higher proof than the evidence supports.
- **Child operation request/result** (`tooling/gnhf/schemas/child-operation-request.schema.json`, `tooling/gnhf/schemas/child-operation-result.schema.json`) gives AgentSwitchboard a typed, authority-bounded way to ask a child repository to run one of its registered operations.
- **Trigger snapshot** (`tooling/gnhf/schemas/trigger-snapshot.schema.json`) preserves the external event that initiated a run, including authorization state, so the run is auditable.

## P01: BlacksmithGuild callable operation surface

- BlacksmithGuild keeps gameplay, launcher, save, and runtime authority.
- AgentSwitchboard may request only registered, read-only or static operations inside the child boundary.
- The six operations from the convergence pack are:
  1. `inspect-harness` — prove the child harness contracts are intact.
  2. `run-default-static` — run the default static E2E profile.
  3. `refresh-read-only-runtime` — refresh read-only runtime evidence only when explicitly authorized.
  4. `generate-sprint-capsule` — produce a machine-readable sprint capsule.
  5. `prepare-runtime-plan` — validate posture before a later live-runtime workflow.
  6. `run-local-build` — run a local build gate when a real game folder is supplied.

## P02: One-command installed adapter

- The adapter `tooling/gnhf/agent-switchboard-blacksmithguild.cmd` and its PowerShell entrypoint `tooling/gnhf/Start-BlacksmithGuildOperation.ps1` let the operator invoke a registered P01 operation from the installed AgentSwitchboard fleet without manually composing GNHF arguments.
- The adapter validates the request schema, dispatches to the child operation surface, and records the result without mutating either repository unless the operation explicitly allows it.

## Why this is not the night panel

The existing BlacksmithGuild night panel (PR #22) is a direct, DeepSeek-first GNHF launcher for the full night-shift chain. It is the right tool for the existing V38 night workflow. The P00/P01/P02 convergence is the callable orchestration layer underneath it: the night panel could later consume a P00 prompt queue and dispatch P01 operations instead of embedding stage logic directly in `Start-BlacksmithGuildNightShift.ps1`.

## Authority boundaries

- AgentSwitchboard owns the orchestration schemas, queue compiler, and dispatcher.
- BlacksmithGuild owns its operation registry, entrypoints, and proof levels.
- The adapter only translates; it does not invent operations or promote proof.
