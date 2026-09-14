# FM-WSL-12 live runtime proof phase map

Canonical coordination index: `plans/active/ASB-2026-09-multi-product-bootstrap-charter.plan.json` task `FM-WSL-12` and ledger `ASQ-017`.

## Completed floor

- PR #177: bounded FM-WSL-12 apt repair authority (`git`/`gh`/`tmux`/`python3`) without extra permission round-trip; GitHub auth remains operator-owned.
- PR #178: durable continuation owner `Invoke-FirstMatePhysicalFloorContinuation.ps1` / harness `-Mode physical-floor-continue`.
- Cloud LIVE_ATTEMPT (2026-09-14): contract PASS; physical-floor and physical-floor-continue fail closed without `wsl.exe`; no self-hosted workers; live PASS not claimed.
- PR #179 merged (`627e31d`): durable `STATUS=BLOCKED_WINDOWS_WSL_REQUIRED` / exit 46 encoding + ASQ-017 ledger row.
- PR #181 merged (`1ada034`): Admin Box one-shot `Invoke-FmWsl12AdminBoxLiveProof.ps1`.
- PR #182 merged (`f108725`): ASQ-017 cites the one-shot; live PASS still UNPROVEN.
- PR #187 merged (`2cb373f`): bounded FirstMate pin bootstrap + `-FirstMatePath` on durable ASQ-017 entrypoint; live PASS still UNPROVEN.
- PR #183 merged (`3babc65`): durable `Invoke-Asq017AdminBoxLiveFloor.ps1` on main; live PASS still UNPROVEN.
- PR #196 merged (`c8556dd`): FirstMate dirty/pin early preflight exits 49/50; live PASS still UNPROVEN.
- PR #198 merged (`7eb9745`): `-FirstMatePath` physical-floor dirty/pin override via `WSLENV`/`ASB_FIRSTMATE_PATH` (skips dirty `$HOME/firstmate`); cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #200 merged (`1bda8e1`): skip dirty/off-pin FirstMate auto-discovery so bounded `$HOME/firstmate` bootstrap can run; child `NEXT=` preferred over hardcoded `$HOME/firstmate` fallbacks; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #202 merged (`83b26e9`): alternate FirstMate auto-discovery now requires the audited pin plus the configured required upstream paths before selection, preventing clean but incomplete alternates from blocking bounded bootstrap; live PASS still UNPROVEN.
- PR #203 merged (`e6b252b`): required paths must exist in the exact audited Git tree as well as the worktree, and the canonical Linux harness executes a synthetic ignored-file discovery regression; post-merge #202 review findings resolved; live PASS still UNPROVEN.
- PR #206 merged (`2dd1040`): authoritative exact-pin checkouts missing a required audited path preserve the ASQ-017 structured blocker API (`STATUS=BLOCKED_FIRSTMATE_PIN`, `NEXT=...`, exit 50); the behavioral fixture proves the structured result; post-merge #203 review finding resolved; live PASS still UNPROVEN.
- PR #207 merged (`0b13f9a`): Asq017/continuation/Admin Box paste surface exit 44 `BLOCKED_MISSING_TOOLS` after exhausted or failed bounded apt repair with structured STATUS/NEXT; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #211 merged (`8b958af`): bridge bootstrap/contract emit structured `BLOCKED_WSL_BOOTSTRAP`/`BLOCKED_HARNESS_CONTRACT` exits 51/52; late interop harness/gh map to 48/45; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #213 merged (`c0512e3`): PhysicalFloor loads FirstMate pin from `tooling/firstmate/harness/upstream-pin.json` instead of a hardcoded SHA in the preflight here-string; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.

## Successor phases

1. **Admin Box live observation (current).** Refresh main @ `c0512e3`+; run the durable `Invoke-Asq017AdminBoxLiveFloor.ps1` entrypoint (ff-only main refresh → `Invoke-FmWsl12AdminBoxLiveProof.ps1`: contract → physical-floor-continue → protected physical-floor). Pre-stage Ubuntu FirstMate @ `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` + one primary harness + Ubuntu `gh` auth. Optional: pass `-FirstMatePath` to a clean audited checkout when `$HOME/firstmate` is dirty/off-pin. Alternate auto-discovery ignores dirty, off-pin, or incomplete checkouts unless their required paths are present in the audited Git tree and worktree; authoritative required-path defects return the structured pin blocker instead of generic failure. Expected: PASS markers + local receipt/evidence root, or `BLOCKED_GITHUB_AUTH` / real non-package blocker with preserved evidence.
2. **Credential gate (conditional).** Only if `BLOCKED_GITHUB_AUTH`: operator `gh auth login` then rerun continuation. No token capture in evidence.
3. **FM-CREW-13 handoff.** Only after physical-floor PASS. Local-only crew pilot; out of this phase's mutation scope.

## Owned / forbidden

- Owned: Admin Box FM-WSL-12 observation; honest fail-closed encoding for non-Windows hosts; bounded repository repairs that remove false prerequisite/discovery blockers without promoting proof.
- Forbidden: fake live PASS; credential automation; allowlist expansion; crew-dispatch claims; committing machine-local receipts.

## Proof ceiling

Hosted/contract + structured cloud fail-closed (`WINDOWS_WSL_REQUIRED` / exit 46) are below physical PASS. Repository discovery hardening through PR #206 and exit-44 Admin Box surface through PR #207, structured bridge exits through PR #211, and PhysicalFloor pin-from-JSON through PR #213 prove selection/path integrity and deterministic blocker routing only. Physical PASS still requires Admin Box observation of the behavior chain, not command ACK alone.
