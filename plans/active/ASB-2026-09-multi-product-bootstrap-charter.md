# Multi-product bootstrap charter

**Plan:** `ASB-2026-09-MULTI-PRODUCT-BOOTSTRAP-CHARTER` — `EndeavorEverlasting/AgentSwitchboard` — `active` `high` — depends on `ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS`

## Mission

Specialize the September agent-bootstrap program into an explicit multi-product matrix: **OpenCode + Pi now (Windows native)**, **FirstMate now (WSL/Ubuntu; Windows bridge only)**, **Herdr deferred**. This plan coordinates sequencing and closes the Pi adapter registration gap honestly; it does **not** replace the September child-bus program.

## Decision floor

| Product | Status | Platform / runtime | Next |
|---|---|---|---|
| OpenCode | lifecycle-complete-on-main | windows-native | remain lifecycle reference |
| Pi | inspect-apply-registered-remove-gap | windows-native | register adapter; Remove/Unbootstrap + physical Apply still open |
| FirstMate | convergence-pending-wsl | WSL/Ubuntu (Windows bridge only) | sibling lands convergence contract; rebase PR #96 |
| Herdr | deferred | Android/Termux + experimental session backend | stay out of Windows Admin Box native bootstrap |

## Owned artifacts

- `tooling/harness/multi-product-bootstrap/product-matrix.contract.json`
- `docs/harness/multi-product-bootstrap-charter.md`
- this plan pair + registry append
- `tests/test_multi_product_bootstrap_charter.py`
- Pi row in `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`

## Explicit non-claims

- Pi physical `Apply` is **not** proven by this sprint (operator field proof).
- Pi `Remove` / `Unbootstrap-Pi-SystemWide.cmd` are **missing** — listed as gaps, not invented.
- FirstMate is **not** a native Windows bootstrap product.
- Herdr is **not** in scope for implementation here.

## Tasks

* **CHARTER-01** — publish product matrix + charter docs/plan.
* **PI-02** — register Pi adapter (`Inspect`/`Apply` only); keep Apply as field proof.
* **FM-03** — FirstMate convergence on main + PR #96 rebase path (sibling owns `tooling/firstmate/**`).
* **HERDR-04** — explicit deferral.
* **HOOKS-05** — extension points via product-matrix + lifecycle adapters; static tests.

## Validation

`python -m unittest tests.test_multi_product_bootstrap_charter` → `Test-PublicPlanContracts.ps1` → `Test-SystemBootstrapLifecycleContracts.ps1` → `git diff --check`.

## Proof ceiling

Contract/charter/static proof only. No Pi physical Apply/Remove, FirstMate WSL runtime, or Herdr bootstrap claim.
