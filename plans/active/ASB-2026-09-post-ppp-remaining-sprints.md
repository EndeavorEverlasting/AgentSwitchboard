# Post-product-pass remaining sprints plan

**Plan ID:** `ASB-2026-09-POST-PPP-REMAINING-SPRINTS`
**Repo:** EndeavorEverlasting/AgentSwitchboard
**Floor:** `main@770c855` (product-pass wave #302-#306 complete)
**Status:** active
**Updated:** 2026-09-17T20:57:00Z

## Mission

Complete remaining September coordination work after product-pass posture wave: refresh FirstMate interop floor to b182d0f, prove Admin Box FM-WSL-12 physical floor, and triage stale open PRs. Encode parallelism constraints, proof ceilings, and dependency order for safe autonomous execution.

## Tasks

### REG-01 — Registry hygiene: PRODUCT-PASS-POSTURE status=completed

**Status:** ready
**Owner:** registry hygiene lane

Fix `plans/plan-registry.json` PRODUCT-PASS-POSTURE status from stale `proposed` to `completed` to match the plan JSON state after wave #302-#306.

**Acceptance:**
- Registry status matches plan JSON (completed)
- Test-PublicPlanContracts.ps1 PASS
- git diff --check clean

### ASQ-015 — Refresh FirstMate interop floor to b182d0f

**Status:** ready
**Owner:** FirstMate interop lane
**Dependencies:** REG-01

Rebase/refresh AgentSwitchboard FirstMate interop harness (PR #96 lineage) onto current main@770c855. Update upstream pin from 833a9a25… to FirstMate main@b182d0f908b78d08c7ccb8dce3775bdca8c5d657. Preserve Windows→WSL bridge ContractOnly mode. Keep first_safe_sprint local-only and yolo_enabled=false.

**Owned scope:**
- tooling/firstmate/harness/upstream-pin.json
- FirstMate interop harness contract surfaces
- Windows bridge preservation

**Forbidden:**
- FirstMate upstream mutation
- enabling +yolo
- claiming live crew dispatch without runtime floor
- native-Windows FirstMate compatibility claim
- deleting GNHF
- unfreezing ASQ-008..012

**Acceptance:**
- FirstMate contract tests green
- Windows bridge -ContractOnly preserved
- Proof ceiling remains below live crew unless physical floor passes
- Test-AgentSwitchboard-FirstMate-Harness.ps1 PASS or BLOCKED_* structured exit
- git diff --check clean

### ASQ-017 — Admin Box FM-WSL-12 physical-floor-continue live proof

**Status:** ready
**Owner:** Windows Admin Box operator / runtime-proof lane
**Dependencies:** ASQ-015

Prove FM-WSL-12 physical WSL/Ubuntu floor through harness `-Mode physical-floor-continue` on authorized Windows Admin Box with explicit Ubuntu. Stop at structured BLOCKED_* exits with preserved evidence and NEXT_ACTION guidance. Cloud/Linux hosts emit STATUS=BLOCKED_WINDOWS_WSL_REQUIRED exit 46.

**Owned scope (host-isolated):**
- Admin Box live floor observation
- Local untracked evidence (not committed)
- Structured exit status propagation

**Forbidden:**
- claiming LIVE PASS from cloud/Linux/contract/CI
- automating GitHub credential entry
- ASQ-008/009 unfreeze
- FirstMate crew dispatch claims (FM-CREW-13)
- committing local receipts/tokens/machine paths

**Acceptance:**
- Admin Box run reaches physical-floor PASS with exact-head readback
- OR stops at structured BLOCKED_* (BLOCKED_MISSING_TOOLS after repair, BLOCKED_GITHUB_AUTH, BLOCKED_SUDO, BLOCKED_PRIMARY_HARNESS, BLOCKED_FIRSTMATE_DIRTY, BLOCKED_FIRSTMATE_PIN, BLOCKED_WSL_BOOTSTRAP, BLOCKED_HARNESS_CONTRACT, BLOCKED_PREREQUISITE_TIMEOUT)
- Cloud/Linux agents emit exit 46 BLOCKED_WINDOWS_WSL_REQUIRED
- No local evidence committed

**Next action:**
```powershell
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath .\Invoke-Asq017AdminBoxLiveFloor.ps1)) {
  throw 'Run from AgentSwitchboard checkout root (Invoke-Asq017AdminBoxLiveFloor.ps1 missing).'
}
pwsh -NoLogo -NoProfile -File .\Invoke-Asq017AdminBoxLiveFloor.ps1 -PrerequisiteTimeoutSeconds 180
# (structured exit handling omitted for brevity — see ASQ-017 ledger entry)
```

### LSP-01 — OpenCode LSP fresh-TUI / ASQ-005 runtime observation (Windows-only)

**Status:** blocked
**Owner:** OpenCode LSP runtime lane
**Dependencies:** ASQ-017

Fresh-TUI LSP hover/goToDefinition/findReferences runtime observation on authorized Windows host. ASQ-005 already DONE on main with Configure-only proof. This task requires live TUI runtime on Admin Box or equivalent Windows host.

**Forbidden:**
- claiming runtime PASS from cloud/Linux/CI
- claiming runtime from Configure-only proof
- committing local receipts

**Acceptance:**
- Fresh TUI opened once; LSP operations observed; nonLspSemanticFallbackUsed=No
- OR explicit BLOCKED_HOST on Linux/cloud

### TRIAGE-01 — Stale open PR triage plan (list keep/close/rebase candidates)

**Status:** ready
**Owner:** PR triage lane
**Dependencies:** ASQ-015

Enumerate stale open PRs #92-#159 era (not auto-merge enabled). Create triage plan listing keep/close/rebase/superseded candidates with containment proof requirements. Explicitly NOT mass-merge.

**Forbidden:**
- mass-closing without triage plan
- auto-merge enabling without operator approval
- force-merge

**Acceptance:**
- Triage plan enumerates candidates with disposition
- Superseded PRs require containment proof before close
- No mass-merge
- Plan artifact persisted

### TUT-WAVE — Tutorial path ranking deferred

**Status:** blocked
**Owner:** user-tutorial-ranking lane
**Dependencies:** ASQ-015, ASQ-017

Tutorial path ranking remains deferred until FirstMate physical/interop floor evidence exists. ASQ-019 already published ranked launch order. TUT-01 first P18 writing sprint queued.

**Acceptance:**
- Explicitly deferred (not skipped)
- Unblock condition: ASQ-015 + ASQ-017 complete with physical floor evidence

## Parallelism constraints

- **Width 2** when Admin Box available: ASQ-015 (repo writer) || ASQ-017 (host-isolated, no AGENTS.md/WORK_QUEUE/plans/* shared writes)
- **Width 1** for shared writers (AGENTS.md / WORK_QUEUE / plans/*)
- **If Admin Box unavailable:** ASQ-017 BLOCKED; run ASQ-015 serially after REG-01

## Floor facts

- Repo: EndeavorEverlasting/AgentSwitchboard
- main@770c855 product-pass wave DONE (#302-#306)
- Canonical prove: `pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1`
- Foreign `scripts/prompt_parallel_dispatch.py` and `harness/contracts/prompt-parallel-dispatch.v1.json` are **ABSENT** — do NOT invent them. Encode dispatch as plan-embedded lanes + Cursor CloudAgent/Task / local agent adapters.
- Ledger READY: ASQ-015 (FirstMate pin refresh), ASQ-017 (Admin Box physical floor)
- ASQ-008..013 **FROZEN** by FirstMate crew ADR
- Many stale open PRs (#92-#159 era) are NOT auto-merge; triage separately

## Proof ceiling

Coordination planning only. Does not prove FirstMate interop refresh, Admin Box physical floor, live OpenCode LSP runtime, PR triage implementation, tutorial authoring, GitHub mergeability, provider delivery, merge, release, or deployment.

## Validation

```bash
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-RepositoryWorkLedgerContract.ps1
git diff --check origin/main...HEAD
```
