# September agent bootstrap and child bus program

**Plan:** `ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS` — `EndeavorEverlasting/AgentSwitchboard` — `active` `high` `wave 0 — coordination floor`

## Mission

Replace chat-only coordination with one repository-owned program for reversible system bootstrap lifecycle (`Inspect / Apply / Remove`), provider-neutral child execution, fresh-TUI LSP runtime certification, heterogeneous/nested delegation, and stale-owner convergence. Public coordination must not carry workstation-specific paths or runtime evidence.

## Current provider floor

The original coordination floor was integrated at `38fd434ed7496413a33e1143d9cbb381849d81de`. This reconciliation refreshed provider truth through `main@d5a1bb4ee46135060e4fbfed467665d2c84f5412`.

Important movement since the original floor:

- reversible system-bootstrap lifecycle remains beneath current `main` via `81461e7`;
- PR #149 path authority is now merged via `3b47a9129730bc8fc3c988f8cbc6ec2fbfa515d8`;
- PR #151 Pi bootstrap/private child seam is now merged via `1f20499d5771456c9ce88da67eced345899928fa`;
- PR #115 remains open and stale pending containment proof;
- current lifecycle adapter registry still contains only OpenCode, so Pi `Inspect/Apply/Remove` parity remains work;
- no provider-neutral `tooling/harness/child-agent-bus/` owner exists yet, so the shared bus remains work;
- OpenCode Python LSP still requires the fresh-TUI runtime observation; headless failure is not promoted to a harness failure.

## Waves and dependencies

```text
Panel 01 coordination floor / reconciliation
  └─ parallel Panel 02 (TUI LSP runtime) + Panel 03 (Pi lifecycle parity) + Panel 04 (shared child bus spine)
       ├─ Panel 05 Pi adapter (needs 03+04)
       └─ Panel 06 OpenCode adapter (needs 04; Pi remains the preferred first conformance reference)
            └─ Panel 07 heterogeneous read-only pilot (needs 05+06 + physical runtime)
                 └─ Panel 08 mediated nested delegation v1
                      └─ Panel 09 nested runtime certification
                           └─ Panel 10 final convergence
```

## Collision ledger

| Surface | Owner | Current disposition |
|---|---|---|
| `tooling/harness/system-bootstrap-lifecycle/**` | shared lifecycle owner; Panel 03 may add Pi adapter but must not redefine lifecycle semantics | keep |
| `tooling/harness/child-agent-bus/**` + root capability/trigger/skill discovery | Panel 04 sole shared-spine writer, then serialized adapter additions | create |
| `Pull-And-Run-AgentSwitchboard.cmd` / technician setup | Panel 03 only when Pi lifecycle parity genuinely requires dispatcher changes | serialize |
| OpenCode LSP harness/docs | Panel 02 runtime evidence; no tracked edits without a reproducible defect | read-only/runtime |
| merged PR #151 | current main now contains Pi bootstrap plus Pi-private child seam | refactor bootstrap into lifecycle parity at 03; migrate private child seam behind shared bus at 05 |
| merged PR #149 | canonical Windows checkout/path authority is now active on main | preserve history; reconcile operator workflow only with evidence at 10 |
| open PR #115 | stale OpenCode LSP owner candidate | compare with current main and close only after supersession proof at 10 |

## Safety boundary

No credentials in Git/evidence, no force reset/push, no private absolute workstation paths in public plan/ledger artifacts, no direct child merge to `main`, no TUI-success claim from headless evidence, no provider/model fallback without contract authority, and no user-local receipt as machine-deletion authority.

## Tasks (10)

- **COORD-01** `completed` — durable coordination floor + current-state/privacy reconciliation.
- **LSP-02** `pending` — fresh-TUI vs headless runtime proof.
- **PI-BOOT-03** `pending` — refactor merged Pi bootstrap into shared reversible lifecycle parity and add unbootstrap.
- **BUS-04** `pending` — provider-neutral child request/result/error contracts, registry, fixtures, validator and dispatcher.
- **PI-ADAPTER-05** `pending` — migrate the merged Pi-private child seam to the shared bus.
- **OC-ADAPTER-06** `pending` — OpenCode adapter parity.
- **PILOT-07** `pending` — Pi + OpenCode read-only heterogeneous pilot.
- **NESTED-08** `pending` — mediated nested delegation with bounded authority inheritance.
- **NESTED-RT-09** `pending` — one depth-2 heterogeneous runtime chain.
- **CLEANUP-10** `pending` — reconcile merged #151/#149 behavior, supersede #115 when proven, then close the September plan/ledger.

## Validation

`public coordination privacy scan` → `Test-PublicPlanContracts.ps1` → `Test-RepositoryWorkLedgerContract.ps1` → `Get-RepositoryWorkLedgerFrontier.ps1 -Json` → `git diff --check` → clean checkout.

## Proof ceiling

This coordination layer proves ownership, dependencies, current PR disposition and public-artifact hygiene only. It does not prove Pi lifecycle parity, OpenCode TUI LSP activation, shared child-bus conformance, provider delivery, heterogeneous fan-out, or nested delegation.

## Handoff

After this reconciliation is integrated, the actionable frontier remains the independent Group A lanes: **Panel 02 + Panel 03 + Panel 04**. Resolve the current canonical checkout through repository/machine-profile authority rather than embedding a machine-specific path in tracked coordination data.
