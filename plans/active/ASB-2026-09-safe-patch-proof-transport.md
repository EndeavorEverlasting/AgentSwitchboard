# Safe patch/proof transport (OWNER STRENGTHENING)

Canonical machine-readable plan: `plans/active/ASB-2026-09-safe-patch-proof-transport.plan.json`.

## Problem evidence

FM-WSL-12 / ASQ-017 continuation repeatedly needed temporary self-mutating GitHub Actions workflows to apply or prove branch repairs. Observed failure modes:

- bot-originated pushes produced unusable PR check events that required close/reopen;
- one ephemeral proof workflow persisted broader-than-needed GitHub write credentials for its run lifetime before self-deleting (not present in the merged tree; no misuse observed here).

Desired durable contract:

1. non-persistent checkout credentials (`persist-credentials: false`);
2. write auth minted only for the final push step, then discarded;
3. automatic transport cleanup (no leftover workflow/file owner);
4. deterministic exact-head PR-check re-arm without close/reopen.

## Inventory floor (2026-09-16 Admin Box read-only)

| Candidate | Path | Write transport? | Reuse as pattern donor? |
|---|---|---|---|
| Operational merge authority | `.github/workflows/operational-merge-authority.yml`, `tooling/harness/operational/Get-OperationalHarnessStatus.py` | No (`contents: read`) | Exact-head merge pin (`--match-head-commit`) |
| Automated test floor | `.github/workflows/automated-test-floor.yml`, `scripts/Test-AutomatedTestFloor.ps1` | No | PR-head ancestor receipting |
| Stale-checkout exact-head bootstrap | `scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1`, `.ai/skills/stale-checkout-exact-head-bootstrap/` | No | Temp-runner auto-cleanup |
| Technician pull-and-run | `.github/workflows/technician-pull-and-run.yml` | No | Operator acquire only |
| Operator command delivery | `.ai/skills/operator-command-delivery/` | No | Command transport ≠ Git write transport |
| Workflow corpus (42) | `.github/workflows/*.yml` | **0** `contents: write`; **0** `persist-credentials: true` | Default read-only hygiene |

**Verdict:** no tracked owner applies patches, pushes repairs, creates temporary self-mutating CI, or deterministically re-triggers exact-head PR checks after a bot push. A new owner is required; compose from the pattern donors above.

## Discriminating design question (P95)

Should the durable owner be:

- a reusable `workflow_dispatch` / callable workflow that never persists write credentials across checkout (mint push token only at the final step), **or**
- a non-committed one-shot Actions job (API-submitted) that never lands a temp workflow file;

and which exact GitHub event (`push` from App vs `workflow_run` vs Checks API) is allowed to re-arm required PR checks without close/reopen?

## Route

1. **P95** — architecture/design: name owner path, permission matrix, cleanup contract, exact-head check re-arm, proof ceiling.
2. **P07** — bounded implementation after design names the canonical owner.

## Forbidden

- Reusing the temporary self-mutating workflow pattern unchanged.
- Expanding write credentials across checkout lifetime.
- Claiming this inventory as implementation of the transport.

## Proof ceiling

This plan proves inventory and routing only. It does not prove a working patch/proof transport.
