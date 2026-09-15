# Automated test floor

## Purpose

This floor is the repository-owned, always-on static safety net for unattended development. It turns the project's actual dependency-free contract behavior into one canonical command that developers and GitHub Actions run the same way.

It does **not** prove runtime launchers, live technician boxes, provider delivery, merge, release, or deployment. Those remain separate proof layers.

## Why this exists

AgentSwitchboard already has many path-filtered domain workflows. That is good for deep owners, but it leaves a gap: a change can miss every path filter and land without exercising the shared static contracts.

A second gap is false-green risk. Several `tests/*.py` files are **script-style** entrypoints (`python tests/foo.py`) rather than `unittest` modules. Commands such as `python -m unittest discover` can look green while contributing zero cases from those scripts. This floor forbids that class of false-green by declaring each gate's runner explicitly.

## Canonical command

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AutomatedTestFloor.ps1
```

Optional:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AutomatedTestFloor.ps1 -OutputRoot $env:TEMP\asb-floor
pwsh -NoLogo -NoProfile -File .\scripts\Test-AutomatedTestFloor.ps1 -ListOnly
```

## Surfaces

| Surface | Role |
|---|---|
| `.ai/harness/automated-test-floor.manifest.json` | Required gate list and runner types |
| `scripts/Test-AutomatedTestFloor.ps1` | Canonical cross-platform runner + receipt |
| `tests/test_automated_test_floor.py` | Meta contracts, including negative canary |
| `.github/workflows/automated-test-floor.yml` | AFK `push` / `pull_request` / `workflow_dispatch` proof |
| `.ai/harness/fixtures/automated-test-floor/` | Fail-closed fixtures (not production behavior) |

## Runner types

- `python-script` — execute `python <path>` and require exit 0 plus expected stdout tokens
- `python-unittest` — execute `python -m unittest <modules>` and **fail closed** when `NO TESTS RAN` or `testsRan < minTests`
- `pwsh-file` — execute `pwsh -File <path>` and require exit 0

## Determinism controls

- `PYTHONHASHSEED=0`
- `TZ=UTC`
- no network and no mutation authority in the floor contract
- receipts written outside the checkout by default (`RUNNER_TEMP` / temp)

## Proof boundary

- **Proof level:** static-test
- **PASS** means required floor gates passed on the observed candidate SHA
- **SKIP** is allowed only for platform mismatch and never counts as required PASS
- **FAIL** is required when a gate is broken, missing, or contributes zero unittest cases

## CI

`.github/workflows/automated-test-floor.yml` runs the canonical command on Windows and Ubuntu for `push`, `pull_request`, and `workflow_dispatch`. No schedule/cron is configured for this bootstrap floor.

## Successor owners

- Risk-ranked growth of this floor: P113
- Repair of an already-red established lane: P32
- Exact local command lookup only: P51
- Automated merge/release/deploy after a green floor: P105
