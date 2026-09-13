# September agent bootstrap and child bus program

**Plan:** `ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS` — `EndeavorEverlasting/AgentSwitchboard` — `active` `high` `wave 0 — coordination floor`

## Mission

Replace chat-only coordination with one current repository-owned program for the September center of gravity: reversible system bootstrap lifecycle (`Inspect / Apply / Remove`), provider-neutral child execution (Pi and OpenCode adapters via a shared bus), fresh-TUI LSP runtime certification, heterogeneous and nested delegation, and stale PR/path convergence.

## Provider floor

`main@54cce3b824a982e26595efa8ed5060e555411693` — parent `2f69049` (LSP runtime-smoke contract). Reversible system-bootstrap lifecycle (`Inspect/Apply/Remove`, write-ahead, drift detection, resumable rollback) is already beneath `main` via `81461e7`. `pyright 1.1.414` prerequisite is observed; headless `opencode` still `No results` until fresh TUI.

## Waves and dependencies

```
Panel 01 (this plan) — coordination floor — alone first
  └─ parallel Panel 02 (TUI LSP runtime) + Panel 03 (Pi reversible bootstrap) + Panel 04 (shared child bus spine)
       └─ Panel 05 Pi adapter (needs 03+04)
            └─ Panel 06 OpenCode adapter (needs 04, prefers 05 as reference) — 1 writer on shared adapter registry
                 └─ Panel 07 heterogeneous read-only pilot (needs 05+06 + physical runtime)
                      └─ Panel 08 mediated nested delegation v1 (maxDepth 2, maxChildren 3, one writer)
                           └─ Panel 09 nested runtime certification (depth-2 heterogeneous chain)
                                └─ Panel 10 PR/path authority cleanup and final convergence (last)
```

## Collision ledger

| Surface | Owner | Disposition |
|---|---|---|
| `tooling/harness/system-bootstrap-lifecycle/**` | shared lifecycle owner; Panel 03 may add Pi adapter but must not redesign contract | keep |
| `tooling/harness/child-agent-bus/**` + root `CAPABILITIES.md`/`TRIGGERS.md`/`SKILLS.md`/`CODEBASE_MAP.md` + `.ai/harness/manifest.json` | Panel 04 sole writer, then serialized adapter additions 05/06 | create |
| `Pull-And-Run-AgentSwitchboard.cmd` `tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1` | Panel 03 only if Pi bootstrap genuinely needs it | otherwise PR #149 waits |
| `tooling/harness/operational/opencode-lsp-setup/**` + `docs/harness/opencode-lsp-workstation-setup.md` | Panel 02 read-only / runtime evidence | no other panel edits without proven defect |
| PR #151 `feat(pi): add system bootstrap and child-agent seam` `8d40604e` | mixed bootstrap + private child contract; stale base predates lifecycle | salvage: bootstrap to 03, child contract to 04/05; not whole-PR merge |
| PR #149 `fix(workstation): enforce canonical Windows checkout path roles` `3138e0b` `CONFLICTING` | proposes blanket OneDrive/Desktop rejection; collides with explicit operator path rule and bootstrap | wait until Panel 10; extract only still-valid explicit-path precedence if proven missing |
| PR #115 `feat(harness): add OpenCode LSP workstation setup harness` `39fd59df` `CONFLICTING` | stale LSP owner candidate | compare with current `main` LSP proof at 10; close as superseded if contained |

## Safety boundary

No credentials in Git/evidence, no force reset/push, no silent local-path relocation, no direct child merge to `main`, no TUI-success claim from headless evidence, no provider/model fallback without contract authority, no user-local receipt as machine-deletion authority. `service` and `runtime` remain `constrained/unverified` until corresponding runtime panels.

## Tasks (10) — owners and gates

*   **COORD-01** `in-progress` — establish this floor (this file) — proves refreshed `54cce3b`, plan/ledger encode program, private paths excluded.
*   **LSP-02** `in-progress` — ASQ-005 fresh-TUI vs headless `20260912T194619Z-e3f423df`. Ledger/routing floor repaired in PR #163 (`d616acc`); **live TUI observation still UNPROVEN** and owned only by Admin Box 1 on `%USERPROFILE%\dev\AgentSwitchBoard-Live`.
*   **PI-BOOT-03** `pending` — `Bootstrap-Pi-SystemWide.cmd` + `Unbootstrap-Pi-SystemWide.cmd` + `tooling/pi/Install-AgentSwitchboardPiSystem.ps1` behind shared lifecycle.
*   **BUS-04** `pending` — `tooling/harness/child-agent-bus/` `child-agent-request/result/error.v1` + registry + dispatcher + fixtures + validator (generic, no adapter impl).
*   **PI-ADAPTER-05** `pending` — Pi as first conforming `child-agent-bus` adapter (needs 03+04).
*   **OC-ADAPTER-06** `pending` — OpenCode parity (needs 04, prefers 05).
*   **PILOT-07** `pending` — Pi + OpenCode fan-out read-only pilot.
*   **NESTED-08** `pending` — mediated nested delegation `maxDepth2`.
*   **NESTED-RT-09** `pending` — depth-2 heterogeneous runtime chain.
*   **CLEANUP-10** `pending` — reconcile/close `151/115/149` + plan/ledger terminal states.

## Validation

`JSON parse/schema` → `Test-PublicPlanContracts.ps1` → `Test-RepositoryWorkLedgerContract.ps1` → `Test-AgentDocumentationContract.ps1` if routing changed → `git diff --check` → clean checkout.

## Proof ceiling

Proves current ownership/dependency/collision state only. Does not prove Pi/OpenCode installation, LSP activation, child-agent execution or provider delivery.

## Handoff

Next: Parallel Group A `Panels 02–04` together only after this floor is integrated. Keep contiguous. See `handoff.nextCommand` in `.plan.json`.
