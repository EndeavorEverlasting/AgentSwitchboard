# Architecture decision: AgentSwitchboard / FirstMate runtime boundary

| Field | Value |
|---|---|
| Decision ID | `ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME` |
| Status | accepted |
| Date | 2026-09-13 |
| Owner plan | `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json` |
| Evidence floor | AgentSwitchboard `main@3a1aa4fb4c700af251a7e94cbbcccf3cb5fb0016` (contains ADR merge of PR #164); FirstMate `main@b182d0f908b78d08c7ccb8dce3775bdca8c5d657` |
| Related | FirstMate interop PR [#96](https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/96) (not on `main`); child-bus spine merge `85ecf77`; ADR integration PR [#164](https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/164) |

## Decision

**Promote the simplification thesis.** FirstMate (`kunchenguid/firstmate`) is the **canonical live crew runtime**. AgentSwitchboard retains workstation/bootstrap convergence, environment and provider readiness, cross-repository policy, semantic guidance (including Prompt Kit), deterministic validation, proof ceilings, public planning, and evidence sinks. AgentSwitchboard must **not** expand the child-agent-bus into a second crew orchestration platform beside FirstMate.

This decision is architecture and ownership only. It does **not** delete GNHF or the child-bus spine, implement adapters, rewrite product identity, or authorize live Admin Box mutation.

## Decision gate result

| Gate | Result |
|---|---|
| Every critical live-execution responsibility planned for child-bus / nested program has a proven FirstMate owner | **Pass for crew execution** — spawn, worktrees, supervision/wake, interrupt/exit/relaunch, secondmates, delivery postures |
| ASB-unique constraints enforceable before launch, as validated inputs, or via a narrow supported interop seam | **Pass with one Windows exception** — GNHF remains the ASB-owned Windows bounded single-agent launcher until FirstMate crew execution is proved on the Windows→WSL floor |
| Essential ASB guarantee requires continuous ASB-owned live lifecycle control | **Not found** for multi-agent crew orchestration; lineage/authority/budget contracts can be pre-launch policy or interop envelope |

**Clarification (post-trace):** FirstMate secondmates are **flat direct reports**, not an ASB-shaped maxDepth lineage bus. That does **not** reopen ASB nested live runtime. ASB nested lineage/budget-inheritance schemas remain optional **POLICY-INPUT** / future bridge material; they are not a reason to keep ASB as a second live supervisor.

## Path traces (end-to-end)

### Path 1 — ASB workstation / bootstrap → FirstMate (WSL) → one worker

**ASB side (intended; tracked on PR #96, not yet on `main`):**

`Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` → WSL distro probe + LF-normalized bootstrap → WSL-owned standalone clone at exact ASB SHA → `Test-FirstMateInterop.sh` / `Select-FirstMateWorkflow.py` → `firstmate-local-only` route with `yolo_enabled: false` → FirstMate project registration → one isolated treehouse worktree worker.

**FirstMate side (upstream `b182d0f`):** captain intent → firstmate distro (`AGENTS.md`, skills, `bin/fm-*`) → `fm-backend` / tmux reference session → treehouse worktree → harness worker → `fm-watch` event-driven wake → `fm-control` lifecycle verbs (`interrupt` / `exit` / `relaunch`) → project delivery mode (`local-only` / `direct-PR` / `no-mistakes`).

**Proof ceiling today:** PR #96 proves harness contracts and Windows→WSL anti-regression structure against an older FirstMate pin (`833a9a25…`, hundreds of commits behind `b182d0f`). Live crew dispatch and refreshed-pin physical floor remain unproved. ASB stops at floor/route evidence; it does not yet call `fm-spawn`.

### Path 2 — Child-agent-bus request → intended Pi/OpenCode child

**Actual shared-bus call stack:**

`Invoke-AgentSwitchboardChild.ps1` → load `adapter-registry.json` (**`adapters: []`**) → validate `invocationId` / head SHA / default-branch write block / dirty worktree → emit `DISPATCH_OK` **or** fail closed `adapter-absent` — **does not launch a child**.

Schemas already encode `lineage`, `authority`, `budgets`, `evidenceRoot`, `writeMode` (`read-only` | `writer-isolated`). Validator `scripts/Test-ChildAgentBus.ps1` proves fail-closed absence only. CAPABILITIES/TRIGGERS/CI wiring for the shared bus remains incomplete relative to ASQ-007 DONE language — coordination drift, not a reason to expand adapters.

**Parallel private Pi path (outside the bus):** `tooling/pi/Invoke-AgentSwitchboardPiChild.ps1` can launch managed Pi under a private child-invocation contract. Disposition: **NARROW / HAND-OFF** — do not grow it into the ASB crew platform; prefer FirstMate harness adapters for live multi-agent work; keep Pi system bootstrap and experimental fusion skill separately.

### Path 3 — GNHF bounded sprint → isolated worker / delivery

**Actual call stack:**

`Setup-AgentSwitchboard` / fleet `state.json` → `Start-GnhfSprint.ps1` → readiness + clean-tree gates → `gnhf --worktree` (or `--current-branch` repair) with iteration/token/`--stop-when` bounds → local transcript + `launcher-summary.json` under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\…` → optional `--push` (off by default).

Unique ASB surfaces retained here: Windows click launchers, fleet/capability installers, DeepSeek usage windows, thinker/token-saving routes, Hermes/ACP readiness probes, provider-routed GNHF, and local evidence roots. GNHF is a **bounded single-agent / fleet launcher**, not a multi-crew control plane. Thinker-route live planning that overlaps FirstMate captain planning is a **DUPLICATED** risk to narrow under ASQ-016, not a crew-runtime expansion license.

## Ownership matrix (exactly one disposition per responsibility)

Dispositions: `ASB-UNIQUE` | `FIRSTMATE-OWNED` | `POLICY-INPUT` | `DUPLICATED` | `BRIDGE-NEEDED` | `UNKNOWN`

| Responsibility | Disposition | Runtime owner | Notes |
|---|---|---|---|
| environment provisioning | `ASB-UNIQUE` | AgentSwitchboard | System bootstrap lifecycle, Windows installers, WSL bridge, machine PATH/ProgramFiles ownership |
| provider / readiness facts | `ASB-UNIQUE` | AgentSwitchboard | Startup readiness, fleet probes, provider windows; FirstMate consumes harness readiness |
| task intake | `BRIDGE-NEEDED` | ASB policy → FirstMate intake | ASB compiles bounds/plan; FirstMate owns captain→crew intake once routed |
| authority / bounds | `POLICY-INPUT` | AgentSwitchboard encodes; FirstMate enforces delivery/autonomy postures | Child-bus authority/budget fields become pre-launch policy or interop envelope, not ASB live control |
| task decomposition | `FIRSTMATE-OWNED` | FirstMate | Crew brief / scout / ship decomposition |
| harness / model / quota selection | `POLICY-INPUT` | Split | ASB owns provider/model policy and readiness; FirstMate owns crew harness adapters; GNHF may select a single agent from fleet state |
| worktree allocation | `FIRSTMATE-OWNED` (crew); `DUPLICATED` under GNHF | FirstMate treehouse; GNHF `--worktree` for Windows single-agent | Do not build a third ASB worktree allocator for child-bus adapters |
| worker spawn | `FIRSTMATE-OWNED` | FirstMate | Shared bus has no spawn path; private Pi child launcher is not the crew platform |
| runtime state | `FIRSTMATE-OWNED` | FirstMate | Crew state, wake markers, secondmate homes |
| supervision / polling | `FIRSTMATE-OWNED` | FirstMate `fm-watch` | ASB must not grow a competing live supervisor |
| intervention | `FIRSTMATE-OWNED` | FirstMate captain escalation path | ASB retains human escalation policy language only |
| interrupt / exit / relaunch | `FIRSTMATE-OWNED` | FirstMate `fm-control` | |
| validation | `ASB-UNIQUE` | AgentSwitchboard | Schemas, validators, CI, proof vocabulary; FirstMate project modes invoke checks but ASB owns ASB contracts |
| branch / PR delivery | `FIRSTMATE-OWNED` for crew delivery; `ASB-UNIQUE` for ASB integration governance | FirstMate delivery postures; ASB PR/ledger/convergence | |
| completion evidence | `BRIDGE-NEEDED` | FirstMate outcomes → ASB evidence sinks / proof ceilings | Keep ASB proof vocabulary; no correlated ASB↔FM evidence handoff yet |
| durable planning | `ASB-UNIQUE` | AgentSwitchboard | Public plans, work ledger, collision ownership; do not let GNHF thinker routes become a second durable plan authority |

## Subtraction analysis

If FirstMate owns live crew execution, AgentSwitchboard can **stop expanding** without losing required ASB contracts:

| Component | Can disappear / stop expanding? | Required ASB remainder |
|---|---|---|
| Child-bus Pi/OpenCode adapters (Panels 05–06) | **Stop expanding** — do not implement as ASB live launchers | Optional narrow envelope validation; managed runtime bootstrap remains |
| Heterogeneous fan-out / nested ASB bus (Panels 07–09) | **Stop expanding** — use FirstMate flat crew/secondmates for live parallelism | ASB one-writer / proof-ceiling / lineage schemas may remain POLICY-INPUT only |
| Private `Invoke-AgentSwitchboardPiChild.ps1` live loop | **Stop expanding as ASB crew runtime** | Keep only if needed as a thin managed-Pi helper; prefer FirstMate harness path |
| Pi fusion as private child protocol | **Stop expanding as child runtime** | Keep experimental opinion-fusion / autovalidate skill as semantic procedure; keep Pi **system bootstrap** |
| ASB-owned live runtime-event observer for crew panes | **Stop expanding** | Keep contract-only runtime-event doctrine; future FirstMate→ASB evidence bridge only |
| GNHF worktree/spawn/supervise for multi-crew | **Do not grow into crew runtime** | Keep Windows bounded single-agent launcher + unique readiness contracts until FirstMate Windows/WSL crew is certified |
| FirstMate interop harness | **Must proceed / refresh** | ASB-UNIQUE bridge: pin to `b182d0f`, WSL floor, deterministic route, local-only first posture |

## Component dispositions (KEEP / NARROW / HAND-OFF / RETIRE)

| Surface | Disposition | Meaning |
|---|---|---|
| `tooling/harness/child-agent-bus/` | **NARROW** | Keep closed schemas + fail-closed front door as optional interop/policy envelope. Freeze adapter registry expansion that would launch children. Do not grow fan-out/nested runtime here. |
| `tooling/gnhf/` | **NARROW** | Keep Windows-first bounded single-agent/fleet launchers and unique readiness contracts. Forbid using GNHF as the multi-agent crew control plane. Future HAND-OFF of worktree/spawn/supervise only after FirstMate covers that Windows path with proof. |
| Pi child / fusion orchestration | **NARROW** + partial **HAND-OFF** | KEEP Pi system bootstrap lifecycle. NARROW `pi-fusion-orchestration` and private `Invoke-AgentSwitchboardPiChild.ps1` away from ASB crew-platform growth. HAND-OFF live multi-agent child runtime to FirstMate harness adapters. Freeze ASB Pi child-bus adapter work. |
| Nested delegation (ASB bus maxDepth 2) | **RETIRE** (ASB live program) + **POLICY-INPUT** residue | Freeze/retire ASB nested live bus. Do **not** claim FirstMate already implements ASB lineage maxDepth; FirstMate secondmates are flat. Any future nested-lineage guarantee is policy/bridge work, not ASB live supervision. |
| Planned ASB nested-bus / fan-out delivery program (Panels 07–09 as ASB live runtime) | **RETIRE** (as ASB delivery goal) | Retire the September goal of growing child-bus into heterogeneous/nested live orchestration. Do not delete the spine; do not reopen without a superseding ADR. |
| Runtime-event observation ambitions | **NARROW** | KEEP contract + synthetic fixtures. Do not build ASB live crew observers that duplicate `fm-watch`. Future BRIDGE only for evidence correlation into ASB sinks. |
| FirstMate interoperability | **KEEP** / proceed | Treat PR #96 lineage as the interop owner to rebase onto refreshed `main` and FirstMate `b182d0f` (pin refresh is mandatory; old `833a9a25…` pin is stale). Admin Box 1 FirstMate bootstrap remains authorized and separable. |
| Prompt Kit semantic surfaces | **KEEP** (contract bridge defined) | Remain ASB differentiator. Live bridge still waits on interop floor; v1 protocol/UX contracts live in `docs/architecture/fm-asb-promptkit-protocol-v1.md` and `docs/harness/context-rollover-ux.md`. |

## September Panels / ASQ dispositions

| Panel / ASQ | Prior intent | Disposition now |
|---|---|---|
| Panel 01 / ASQ-004 | Coordination floor | **DONE** — remain historical |
| Panel 02 / ASQ-005 | Fresh-TUI LSP runtime | **PROCEED** — independent of crew ownership; Live-floor routing on `main` via PR #163 |
| Panel 03 / ASQ-006 | Pi reversible bootstrap | **PROCEED / reconcile** — lifecycle on `main`, but `adapters.v1.json` still lists only OpenCode; repair registry truth separately without unfreezing child-bus adapters |
| Panel 04 / ASQ-007 | Child-bus spine | **DONE + NARROW** — spine remains; no adapter expansion |
| Panel 05 / ASQ-008 | Pi child-bus adapter | **FREEZE** — do not implement as ASB live launcher |
| Panel 06 / ASQ-009 | OpenCode child-bus adapter | **FREEZE** |
| Panel 07 / ASQ-010 | Heterogeneous fan-out pilot | **FREEZE / REPURPOSE** — any heterogeneous crew pilot routes through FirstMate, not ASB bus adapters |
| Panel 08 / ASQ-011 | Mediated nested delegation | **FREEZE / RETIRE** as ASB live program |
| Panel 09 / ASQ-012 | Nested runtime certification | **FREEZE / RETIRE** as ASB live program |
| Panel 10 / ASQ-013 | PR/path convergence | **PROCEED with narrowed deps** — no longer blocked on ASQ-008…012 live runtime; still waits on ASQ-005 and truthful successor containment |
| ASQ-014 | This architecture decision | **DONE** on `main` via PR #164 |
| ASQ-015 | FirstMate interop refresh | **PROCEED** — rebase/refresh pin, land interop harness, prove WSL floor |
| ASQ-016 | GNHF narrow-owner contract | **PROCEED** — document/enforce NARROW boundary in GNHF docs/validators without deleting launchers |

## Explicit non-goals (this decision)

- Do not delete `tooling/gnhf/` or `tooling/harness/child-agent-bus/`.
- Do not implement Pi/OpenCode child-bus adapters, fan-out, or nested ASB delegation.
- Do not build live Prompt Kit → FirstMate adapters yet; contract-only protocol/UX freeze is authorized separately in `docs/architecture/fm-asb-promptkit-protocol-v1.md`.
- Do not rewrite README / product identity in this change.
- Do not block Admin Box 1 FirstMate bootstrap on unrelated product work.

## Proof ceiling

This ADR proves refreshed provider/architecture ownership analysis and durable plan/ledger synchronization. It does **not** prove live FirstMate crew on Admin Box 1, that FirstMate satisfies every future ASB guarantee without a bridge, that GNHF is redundant, or that PR #96 is merge-ready at the new pin.

## Next executable owners

1. ASQ-015: refresh FirstMate interop to `b182d0f` and current `main`.
2. ASQ-005: continue fresh-TUI LSP certification in parallel.
3. ASQ-016: encode GNHF NARROW contract in docs/validators.
4. Only after ASQ-015 floor: optional narrow child-bus→FirstMate envelope investigation (P07/P95), not adapter runtime expansion.
