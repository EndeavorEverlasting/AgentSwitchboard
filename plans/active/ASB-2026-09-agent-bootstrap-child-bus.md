# September agent bootstrap and child bus program

**Plan:** `ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS` — `EndeavorEverlasting/AgentSwitchboard` — `active` `high` `wave 1 — FirstMate runtime boundary`

## Mission

Replace chat-only coordination with one repository-owned September program. After the accepted architecture decision `ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME`, the program **narrows**: AgentSwitchboard owns reversible system bootstrap, provider/environment readiness, policy, validation, evidence, and public planning; **FirstMate is the canonical live crew runtime**. The child-agent-bus spine remains as a narrowed interop/policy envelope. Pi/OpenCode ASB child-bus adapters, heterogeneous ASB fan-out, and ASB nested delegation are **frozen**. Fresh-TUI LSP certification, Pi bootstrap registry truth, FirstMate interop refresh, GNHF narrowing, and PR/path convergence continue.

## Canonical architecture decision

Durable decision: [`docs/architecture/asb-firstmate-runtime-boundary.md`](../../docs/architecture/asb-firstmate-runtime-boundary.md)

**Accepted thesis:** FirstMate (`kunchenguid/firstmate@b182d0f`) owns live crew execution (decomposition, worktrees, spawn, supervision, interrupt/exit/relaunch, delivery postures). AgentSwitchboard does not expand a second crew control plane.

## Provider floor

- AgentSwitchboard: `main@e76ba4becbb5361afbb0596727d7bb326bd6b689` (Pi lifecycle + child-bus spine marked integrated; adapter registry empty).
- FirstMate upstream: `main@b182d0f908b78d08c7ccb8dce3775bdca8c5d657`.
- FirstMate ASB interop: open PR #96 on stale base/`833a9a25…` pin — must refresh (ASQ-015), not treat as current `main` truth.

## Waves and dependencies (revised)

```
Panel 01 coordination floor — DONE
  ├─ Panel 02 / ASQ-005 fresh-TUI LSP — PROCEED (parallel)
  ├─ Panel 03 / ASQ-006 Pi bootstrap — DONE on main; registry truth reconcile separately
  ├─ Panel 04 / ASQ-007 child-bus spine — DONE + NARROW (no adapter expansion)
  ├─ ARCH ADR / ASQ-014 FirstMate boundary — DONE when this sync lands
  ├─ ASQ-015 FirstMate interop refresh — PROCEED (depends on ADR)
  ├─ ASQ-016 GNHF NARROW contract — PROCEED (depends on ADR)
  └─ Panel 10 / ASQ-013 PR/path cleanup — PROCEED with narrowed deps (no longer waits on 05–09 live bus)
Panels 05–09 / ASQ-008…012 — FREEZE (HAND-OFF crew runtime to FirstMate)
```

## Collision ledger

| Surface | Owner | Disposition |
|---|---|---|
| `docs/architecture/asb-firstmate-runtime-boundary.md` | P95 architecture lane (this sync) | create / keep as ADR owner |
| `tooling/harness/child-agent-bus/**` | NARROW owner; freeze adapter writers | keep spine; no Pi/OpenCode adapter expansion |
| `tooling/gnhf/**` | GNHF NARROW owner (ASQ-016) | keep Windows bounded launchers; no crew-runtime expansion |
| `tooling/harness/system-bootstrap-lifecycle/**` | bootstrap owner | keep; reconcile Pi registry drift without unfreezing child bus |
| `tooling/firstmate/**` + FirstMate skill/docs (PR #96 lineage) | ASQ-015 interop lane | refresh pin to `b182d0f`; rebase onto current main |
| `tooling/harness/operational/opencode-lsp-setup/**` | Panel 02 / ASQ-005 | proceed; no architecture mutation |
| PR #151 / #149 / #115 | Panel 10 / ASQ-013 | converge with narrowed dependency set |
| PR #163 ASQ-005 Live floor | Panel 02 | parallel; avoid conflicting WORK_QUEUE semantics beyond encoding/status sync |

## Safety boundary

No credentials in Git/evidence, no force reset/push, no silent local-path relocation, no direct child merge to `main`, no TUI-success claim from headless evidence, no provider/model fallback without contract authority, no user-local receipt as machine-deletion authority. Do not delete GNHF or child-bus spine under this plan. Do not implement frozen Panels 05–09 as ASB live runtime. `service` and `runtime` remain `constrained/unverified` until corresponding runtime panels/floors prove them.

## Tasks — owners and gates

*   **COORD-01** `completed` — September coordination floor established.
*   **LSP-02** `pending` — fresh-TUI vs headless LSP runtime certification — **PROCEED**. Canonical Live-floor routing repaired on main via PR #163; live TUI observation remains UNPROVEN on Admin Box 1.
*   **PI-BOOT-03** `completed` — Pi reversible bootstrap on main; follow-up registry truth only.
*   **BUS-04** `completed` — child-bus spine on main; subsequent work is **NARROW** only.
*   **ARCH-FM-01** `completed` — accepted FirstMate crew-runtime boundary ADR + plan/ledger sync.
*   **FM-INTEROP-02** `ready` — refresh/rebase FirstMate interop (PR #96 lineage) to current main + FirstMate `b182d0f`.
*   **GNHF-NARROW-03** `ready` — encode GNHF KEEP/NARROW boundary in docs/validators; no launcher deletion.
*   **PI-ADAPTER-05** `skipped` — **FREEZE**; Pi live child runtime hands off to FirstMate harnesses.
*   **OC-ADAPTER-06** `skipped` — **FREEZE**.
*   **PILOT-07** `skipped` — **FREEZE / REPURPOSE** through FirstMate crew, not ASB bus adapters.
*   **NESTED-08** `skipped` — **RETIRE** as ASB live nested bus (FirstMate secondmates are flat; lineage schemas stay POLICY-INPUT only).
*   **NESTED-RT-09** `skipped` — **RETIRE** as ASB live nested certification.
*   **CLEANUP-10** `pending` — PR/path authority cleanup with narrowed dependencies (no longer blocked on 05–09).

## Validation

`JSON parse/schema` → `Test-PublicPlanContracts.ps1` → `Test-RepositoryWorkLedgerContract.ps1` → `Test-AgentDocumentationContract.ps1` if routing/docs map changed → `git diff --check` → clean checkout.

## Proof ceiling

Proves current ownership/dependency/collision state and the accepted FirstMate boundary ADR only. Does not prove Pi/OpenCode installation, LSP activation, FirstMate live crew dispatch, GNHF redundancy, child-agent execution, or provider delivery.

## Handoff

Next: run ASQ-015 FirstMate interop refresh and ASQ-005 LSP certification in parallel after this ADR sync integrates. Keep Admin Box 1 FirstMate bootstrap separable. See `handoff.nextCommand` in `.plan.json`.
