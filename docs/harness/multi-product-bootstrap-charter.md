# Multi-product bootstrap charter

AgentSwitchboard treats system bootstrap as a **multi-product matrix**, not a single installer. This charter specializes sequencing under the September program `ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS`; it does not replace that plan.

## Decision floor (2026-09-13)

| Product | Now? | Platform / runtime | Windows Admin Box role |
|---|---|---|---|
| OpenCode | yes | Windows native | full Inspect/Apply/Remove lifecycle host |
| Pi | yes | Windows native | Inspect/Apply registered; Remove still a gap |
| FirstMate | yes | WSL/Ubuntu runtime | **bridge only** — no native Windows FirstMate bootstrap |
| Herdr / Herder | deferred | Android/Termux + experimental session backend | out of Windows native bootstrap |

## Canonical surfaces

- Product matrix: `tooling/harness/multi-product-bootstrap/product-matrix.contract.json`
- Lifecycle adapter registry: `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`
- Public plan: `plans/active/ASB-2026-09-multi-product-bootstrap-charter.plan.json`
- Focused static tests: `tests/test_multi_product_bootstrap_charter.py`

## OpenCode

Already on `main` as the lifecycle **reference implementation** (`adapterId: opencode`) with `Bootstrap-OpenCode-SystemWide.cmd` / `Unbootstrap-OpenCode-SystemWide.cmd` and Inspect/Apply/Remove parity.

## Pi

Installer and bootstrap entrypoint already exist on `main`:

- `Bootstrap-Pi-SystemWide.cmd`
- `tooling/pi/Install-AgentSwitchboardPiSystem.ps1` (`ValidateSet('Inspect','Apply')` only)
- `tooling/pi/harness/system-bootstrap.contract.json`

This charter closes the **adapter registration gap** by adding `adapterId: pi` to `adapters.v1.json` with operations `Inspect` and `Apply` only.

Honest remaining gaps (do not invent lying stubs):

- no `Unbootstrap-Pi-SystemWide.cmd`
- no `Remove` mode in the Pi installer
- physical workstation `Apply` is **operator field proof**, not claimed by this charter sprint

## FirstMate

Runtime is **WSL/Ubuntu**. Windows remains a bridge host only. Implementation under `tooling/firstmate/**` is owned by a sibling worker. Charter expectation: land a convergence contract on `main`, then rebase/salvage the stale PR #96 stack onto that contract.

## Herdr

Explicitly deferred. Do not implement Android/Termux Herdr bootstrap in this wave or treat it as a Windows Admin Box native product.

## Extension points (HOOKS)

Future products extend through:

1. a new row in `product-matrix.contract.json` (status, platform, bootstrapOwner, runtime, proofCeiling, nextAction);
2. a lifecycle adapter entry in `adapters.v1.json` only when real Inspect/Apply/Remove surfaces exist.

## Proof ceiling

This charter proves ownership, sequencing, and declared matrix status. It does **not** prove Pi physical Apply, Pi Remove, FirstMate WSL runtime success, or Herdr bootstrap.
