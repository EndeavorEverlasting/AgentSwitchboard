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

## Actions-quota workaround (local proof)

When GitHub Actions minutes are exhausted or provider runs are unavailable, use the local same-entrypoint proof packet. It does not consume Actions minutes, does not mutate production gates for canary proof, and does not commit generated receipts:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Prove-AutomatedTestFloorLocal.ps1
```

That command runs:

1. meta contracts (`python -m unittest tests.test_automated_test_floor`);
2. the canonical floor runner;
3. an isolated negative canary against `.ai/harness/fixtures/automated-test-floor/canary_fail.py` (expect FAIL).

Generated receipts and the local proof packet stay under the chosen `OutputRoot` (temp by default). They are ephemeral generated artifacts, not competing source truth.

Provider workflow `.github/workflows/automated-test-floor.yml` remains a thin delegate to the same runner. Feature-branch `push` triggers are intentionally limited to `main` plus `pull_request` / `workflow_dispatch` to reduce double-spend when quota is tight.

## Surfaces

| Surface | Role |
|---|---|
| `.ai/harness/automated-test-floor.manifest.json` | Required gate list and runner types (canonical input) |
| `scripts/Test-AutomatedTestFloor.ps1` | Canonical generator/runner + provenance receipt |
| `scripts/Prove-AutomatedTestFloorLocal.ps1` | Actions-quota local proof packet (CLI trigger) |
| `tests/test_automated_test_floor.py` | Meta contracts, including negative canary |
| `.github/workflows/automated-test-floor.yml` | AFK `pull_request` / `main` push / `workflow_dispatch` proof |
| `.ai/harness/fixtures/automated-test-floor/` | Fail-closed fixtures (not production behavior) |

## Source / generated boundary

| Kind | Path / artifact | Owner |
|---|---|---|
| Canonical input | `.ai/harness/automated-test-floor.manifest.json` | humans/agents edit this |
| Generator | `scripts/Test-AutomatedTestFloor.ps1` | humans/agents repair this, then re-run |
| Generated (ephemeral) | `automated-test-floor-receipt.json/.md` | never commit; regenerate |
| Generated (ephemeral) | `local-proof-packet.json/.md` | never commit; regenerate |
| Forbidden | patching production gates for temporary canary proof | use fixture canary instead |
| Forbidden | secrets/private evidence in receipts | floor is static/offline only |

Same accepted manifest plus pinned runner must produce the same gate PASS/FAIL classification. Receipt timestamps and temp paths differ by design; an immediate unchanged-input repeat must not create a tracked Git diff because outputs stay outside the checkout.

## Runner types

- `python-script` — execute `python <path>` and require exit 0 plus expected stdout tokens
- `python-unittest` — execute `python -m unittest <modules>` and **fail closed** when `NO TESTS RAN` or `testsRan < minTests`
- `pwsh-file` — execute `pwsh -File <path>` and require exit 0

## Determinism controls

- `PYTHONHASHSEED=0`
- `TZ=UTC`
- no network and no mutation authority in the floor contract
- receipts written outside the checkout by default (`RUNNER_TEMP` / temp)
- receipt provenance records manifest SHA-256, generator SHA-256, and trigger (`local-cli` or `github-actions`)

## Proof boundary

- **Proof level:** static-test
- **PASS** means required floor gates passed on the observed candidate SHA
- **SKIP** is allowed only for platform mismatch and never counts as required PASS
- **FAIL** is required when a gate is broken, missing, or contributes zero unittest cases
- **Local proof PASS** substitutes for provider Actions when quota is exhausted; it does not invent merge authority

## CI

`.github/workflows/automated-test-floor.yml` runs the canonical command on Windows and Ubuntu for `pull_request`, `push` to `main`, and `workflow_dispatch`. No schedule/cron is configured for this bootstrap floor.

## Successor owners

- Risk-ranked growth of this floor: P113
- Repair of an already-red established lane: P32
- Exact local command lookup only: P51
- Automated merge/release/deploy after a green floor: P105
