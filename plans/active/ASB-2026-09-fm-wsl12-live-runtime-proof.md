# FM-WSL-12 live runtime proof phase map

Canonical coordination index: `plans/active/ASB-2026-09-multi-product-bootstrap-charter.plan.json` task `FM-WSL-12` and ledger `ASQ-017`.

## Completed floor

- PR #177: bounded FM-WSL-12 apt repair authority (`git`/`gh`/`tmux`/`python3`) without extra permission round-trip; GitHub auth remains operator-owned.
- PR #178: durable continuation owner `Invoke-FirstMatePhysicalFloorContinuation.ps1` / harness `-Mode physical-floor-continue`.
- Cloud LIVE_ATTEMPT (2026-09-14): contract PASS; physical-floor and physical-floor-continue fail closed without `wsl.exe`; no self-hosted workers; live PASS not claimed.
- PR #179 merged (`627e31d`): durable `STATUS=BLOCKED_WINDOWS_WSL_REQUIRED` / exit 46 encoding + ASQ-017 ledger row.
- PR #181 merged (`1ada034`): Admin Box one-shot `Invoke-FmWsl12AdminBoxLiveProof.ps1`.
- PR #182 merged (`f108725`): ASQ-017 cites the one-shot; live PASS still UNPROVEN.
- PR #183 merged (`3babc65`): durable `Invoke-Asq017AdminBoxLiveFloor.ps1` on main; live PASS still UNPROVEN.

## Successor phases

1. **Admin Box live observation (current).** After #183 merges, refresh main; paste the OCD-safe ASQ-017 next action (checkout-root guard, capture `CHILD_EXIT_CODE`, `throw` instead of interactive `exit`) running durable `Invoke-Asq017AdminBoxLiveFloor.ps1` (ff-only main refresh → `Invoke-FmWsl12AdminBoxLiveProof.ps1`: contract → physical-floor-continue → protected physical-floor). Pre-stage Ubuntu FirstMate @ `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` + one primary harness + Ubuntu `gh` auth. Expected: PASS markers + local receipt/evidence root, or `BLOCKED_GITHUB_AUTH` / real non-package blocker with preserved evidence.
2. **Credential gate (conditional).** Only if `BLOCKED_GITHUB_AUTH`: operator `gh auth login` then rerun continuation. No token capture in evidence.
3. **FM-CREW-13 handoff.** Only after physical-floor PASS. Local-only crew pilot; out of this phase's mutation scope.

## Owned / forbidden

- Owned: Admin Box FM-WSL-12 observation; honest fail-closed encoding for non-Windows hosts.
- Forbidden: fake live PASS; credential automation; allowlist expansion; crew-dispatch claims; committing machine-local receipts.

## Proof ceiling

Hosted/contract + structured cloud fail-closed (`WINDOWS_WSL_REQUIRED` / exit 46) are below physical PASS. Physical PASS requires Admin Box observation of the behavior chain, not command ACK alone.
