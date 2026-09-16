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
- PR #215 merged (`c473b26`): Asq017/oneshot exit-50 NEXT fallbacks load FirstMate pin from `tooling/firstmate/harness/upstream-pin.json` instead of a hardcoded SHA; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #217 merged (`b6d8365`): Asq017 reloads FirstMate pin from `upstream-pin.json` after ff-only git refresh so exit-50 NEXT matches tip; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #219 merged (`0a57a41`): Asq017 prefers child NEXT= (keeps -FirstMatePath guidance) and ASQ-017 paste loads exit-50 pin from upstream-pin.json; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #221 merged (`1b1c65c`): physical-floor runbook exit-50 paste/table load pin from `tooling/firstmate/harness/upstream-pin.json`; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #223 merged (`da41789`): behavioral gate proves Asq017 prefers last child NEXT= and loads pin from upstream-pin.json via pwsh; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #225 merged (`e3b449e`): PhysicalFloor emits structured STATUS/NEXT for prerequisite timeout (exit 124) and exact-head mismatch instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #227 merged (`d4ff09c`): bridge Exact-head mismatch and missing wsl.exe emit structured STATUS/NEXT (exit 1 / 46) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #229 merged (`0884d6f`): oneshot Exact-head mismatch and harness timeout emit structured STATUS/NEXT (exit 1 / 124) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #231 merged (`c8bde63`): Asq017 ff-only git-refresh and HEAD-resolve failures emit structured STATUS/NEXT (exit 1) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #233 merged (`c6e332c`): oneshot WSL-distribution mismatch, HEAD/ExpectedHead resolve defects, and harness-start failures emit structured STATUS/NEXT (exit 1) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #235 merged (`23893d5`): PhysicalFloor WSL-distribution mismatch, HEAD resolve defects, and invalid upstream-pin commit emit structured STATUS/NEXT (exit 1 / 50) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #237 merged (`f1d197c`): bridge WSL-distribution mismatch, wsl.exe Start failure, and non-worktree SourceRepositoryPath emit structured STATUS/NEXT (exit 1 / 46) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #239 merged (`a404b5d`): continuation WSL-distribution mismatch, process Start failure, and HEAD resolve/mismatch emit structured STATUS/NEXT (exit 1) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #241 merged (`a1482b2`): PhysicalFloor process Start failure emits structured STATUS/NEXT (exit 1) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #243 merged (`c48a49c`): continuation missing/non-allowlisted NEXT_ACTION emits structured STATUS/NEXT (exit 44) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #245 merged (`86a62db`): bridge git HEAD/common-dir/worktree/exact-commit Assert-LastExit failures emit structured STATUS/NEXT (exit 1) instead of throw→exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #247 merged (`4ac4f47`): bridge WSL workspace-cleanup failures emit structured STATUS/NEXT (exit 1) instead of throw→exit 1; unused Assert-LastExit removed; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #248 merged (`df32d5c`): ledger/plan cite for #247; tip ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #249 merged (`5b6cc7f`): tip-cite for #248 ContractOnly+exit46; live PASS still UNPROVEN.
- PR #250 merged (`c04abd4`): Asq017/oneshot harness-start + invalid FirstMate pin and bridge/PhysicalFloor WSL prerequisite timeouts emit structured STATUS/NEXT (exit 1/50/124) instead of throw→exit 1 or remapping hangs to exit 46; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #251 merged (`1e6010f`): ledger/plan cite for #250; tip ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #252 merged (`0fd198a`): Asq017 Write-Asq017Blocker emits parent STATUS= before ASQ017_RESULT=; oneshot surfaces STATUS= on harness-contract/continue/protected-control failures; continuation sudo-probe and bounded apt-repair timeouts keep STATUS=BLOCKED_PREREQUISITE_TIMEOUT / exit 124 (not remapped to 47/44); cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #253 merged (`0c11566`): ledger/plan cite for #252; tip ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #254 merged (`4834ee2`): Asq017 durable owner + WORK_QUEUE/runbook pastes map child exit 124 to STATUS=BLOCKED_PREREQUISITE_TIMEOUT (not generic FAILED); cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #255 merged (`4a581a5`): ledger/plan cite for #254; tip ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- Tip prove on `4a581a5`: cloud ContractOnly PASS + live exit 46 after #254/#255; live PASS still UNPROVEN.
- PR #257 merged (`1410e77`): Asq017 -ContractOnly failure emits STATUS=CONTRACT_FAIL (+ CHILD_EXIT_CODE/NEXT) instead of throw→unstructured exit 1; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #259 merged (`0c59070`): oneshot contract/continue child exit 124 maps to STATUS=BLOCKED_PREREQUISITE_TIMEOUT (not BLOCKED_HARNESS_CONTRACT / generic continue-fail); cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #260 merged (`2cb70a3`): ledger/plan cite for #259; tip ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #262 merged (`40c2c6c`): oneshot protected-control child exit 124 maps to STATUS=BLOCKED_PREREQUISITE_TIMEOUT (not BLOCKED_PROTECTED_CONTROL); cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #264 merged (`be44bc1`): continuation recovers STATUS from exits 46–52/124 when STATUS= is truncated; loop fallthrough emits STATUS=BLOCKED_CONTINUATION_EXHAUSTED; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- PR #266 merged (`28414c7`): oneshot/Asq017 preserve child STATUS=BLOCKED_* (incl. CONTINUATION_EXHAUSTED) instead of generic continue-fail/FAILED; cloud ContractOnly PASS + live exit 46 retained; live PASS still UNPROVEN.
- Tip prove on `2a11014`: cloud ContractOnly PASS + live exit 46 after #266/#267; Admin Box paste/runbook exit-1 STATUS guidance added; live PASS still UNPROVEN.
- Tip prove on `4e884b1`: cloud ContractOnly PASS + live exit 46 after #268; paste/runbook exit-1 STATUS guidance on main; live PASS still UNPROVEN.
- Tip prove on `c70607b`: cloud ContractOnly PASS + live exit 46 after #270; live PASS still UNPROVEN.
- Tip prove on `4258ac2`: cloud ContractOnly PASS + live exit 46 after #269/#270; live PASS still UNPROVEN.
- Tip prove on `4b26814`: cloud ContractOnly PASS + live exit 46 after #271; live PASS still UNPROVEN.
- Tip prove on `2a72020`: cloud ContractOnly PASS + live exit 46 after #272; live PASS still UNPROVEN.
- Tip prove on `2cb70a3`: cloud ContractOnly PASS + live exit 46 after #259/#260; live PASS still UNPROVEN.
- Tip prove on `2562b92`: cloud ContractOnly PASS + live exit 46 after #274/#275/#276; live PASS still UNPROVEN.
- Encode: raise `PrerequisiteTimeoutSeconds` default 60→180 across Asq017/oneshot/harness/PhysicalFloor/continuation + ASQ-017 paste/runbook so Admin Box cold WSL probes (39-67s+) do not race the post-#278 honored timeout; live PASS still UNPROVEN.
- Admin Box host `LPW003ASI173` LIVE_ATTEMPT on refreshed `main@9ad46447…` (OneDrive spaced checkout): first entrypoint launch failed with unstructured pwsh usage exit 64 because `Start-Process -ArgumentList` split the spaced path; repaired on `fix/asq017-oneshot-spaced-path-launch-20260915` via `ProcessStartInfo.ArgumentList`. Post-repair observation reached contract PASS + physical-floor-continue `STATUS=BLOCKED_GITHUB_AUTH` exit 45 with local receipt under `%TEMP%\AgentSwitchboard\fm-wsl12-admin-box-live\9ad46447-20260915-212256-731c554f\`; Ubuntu `gh` present but not logged in. Live PASS still UNPROVEN.

## Successor phases

1. **Credential gate (current).** Operator completes Ubuntu `gh auth login` (no token capture in evidence), then reruns `Invoke-Asq017AdminBoxLiveFloor.ps1` from refreshed tip that contains the spaced-path launch fix.
2. **Admin Box live observation (resume).** After auth, expect PASS markers + local receipt/evidence root, or the next real non-package blocker with preserved evidence. Optional: `-FirstMatePath` when `$HOME/firstmate` is dirty/off-pin.
3. **FM-CREW-13 handoff.** Only after physical-floor PASS. Local-only crew pilot; out of this phase's mutation scope.

## Owned / forbidden

- Owned: Admin Box FM-WSL-12 observation; honest fail-closed encoding for non-Windows hosts; bounded repository repairs that remove false prerequisite/discovery blockers without promoting proof.
- Forbidden: fake live PASS; credential automation; allowlist expansion; crew-dispatch claims; committing machine-local receipts.

## Proof ceiling

Hosted/contract + structured cloud fail-closed (`WINDOWS_WSL_REQUIRED` / exit 46) are below physical PASS. Repository discovery hardening through PR #206 and exit-44 Admin Box surface through PR #207, structured bridge exits through PR #211, PhysicalFloor pin-from-JSON through PR #213, Asq017/oneshot exit-50 pin-from-JSON through PR #215, Asq017 post-refresh pin reload through PR #217, and Asq017 child-NEXT preference + paste pin-from-JSON through PR #219, and runbook pin-from-JSON through PR #221, and Asq017 helper behavioral proof through PR #223, and PhysicalFloor structured timeout/head-mismatch exits through PR #225, and bridge Exact-head/WSL-unavailable structured exits through PR #227, and oneshot Exact-head/harness-timeout structured exits through PR #229, and Asq017 git-refresh/HEAD-resolve structured exits through PR #231, and oneshot WSL-distribution/HEAD/harness-start structured exits through PR #233, and PhysicalFloor WSL-distribution/HEAD/FirstMate-pin structured exits through PR #235, and bridge WSL-distribution/start/source-tree structured exits through PR #237, and continuation WSL-distribution/start/HEAD structured exits through PR #239, and PhysicalFloor process-start structured exits through PR #241, and continuation missing/non-allowlisted NEXT_ACTION structured exits through PR #243, and bridge git Assert-LastExit structured exits through PR #245, and bridge WSL workspace-cleanup structured exits through PR #247, Asq017/oneshot harness-start/pin and bridge/PhysicalFloor prerequisite-timeout structured exits through PR #250, and Asq017 parent STATUS= + oneshot fail STATUS + continuation hang-exit 124 through PR #252 prove selection/path integrity and deterministic blocker routing only. Asq017/parent exit-124 STATUS surface through PR #254, and Asq017 ContractOnly structured fail through PR #257, and oneshot contract/continue exit-124 STATUS=BLOCKED_PREREQUISITE_TIMEOUT through PR #259, and oneshot protected-control exit-124 STATUS=BLOCKED_PREREQUISITE_TIMEOUT through PR #262, and continuation exit→STATUS recovery + BLOCKED_CONTINUATION_EXHAUSTED fallthrough through PR #264, and oneshot/Asq017 preserve child STATUS=BLOCKED_* through PR #266 prove selection/path integrity and deterministic blocker routing only. Physical PASS still requires Admin Box observation of the behavior chain, not command ACK alone.
