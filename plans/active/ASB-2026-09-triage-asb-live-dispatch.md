# P07: Triage→ASB Live Lane Dispatch Adapter

**Plan ID**: ASB-2026-09-TRIAGE-ASB-LIVE-DISPATCH
**Status**: Active
**Priority**: High
**Created**: 2026-09-19

## Mission

Implement machine-executable dispatch adapter for Triage lanes with receipt contracts. Close remaining AUTONOMY_GAP by executing ready lanes from ingested manifests and emitting structured receipts.

## Background

This builds on PR #320 (Triage→ASB consumer floor) by adding the live dispatch adapter that machine-executes lanes. The consumer floor provided structural mapping; this adds execution and receipt generation.

## Slices

### Slice A: Triage Pin Documentation (Completed)

Record read-only upstream pin in `consumer.policy.json`:
- Repository: EndeavorEverlasting/web-excel-repair-triage
- Pin SHA: 24b70c07
- Preserve `human_scheduler_allowed:false` and `panel_ingest_required:true`

**Evidence**: Commit ed8f8bf

### Slice B: Live Dispatch Adapter (Completed)

Implement bounded dispatch adapter for machine-executing Triage lanes:

**Owned Scope**:
- `tooling/harness/triage-consumer/dispatch/` directory
- `dispatch.policy.json` - Policy with fail-closed enforcement
- `dispatch-receipt.schema.json` - Receipt contract
- `dispatch_lanes.py` - Durable Python runner
- Test fixtures and `Test-TriageAsbConsumerDispatch.ps1`
- Public plan and plan-registry update

**Forbidden Scope**:
- `tooling/evals/p67-opencode-adapter/**`
- Claiming live CloudAgent PASS without observed execution
- Deleting panels or requiring human paste/proceed
- Triage mutation

## Implementation

### Dispatch Policy

`tooling/harness/triage-consumer/dispatch/dispatch.policy.json` defines:
- `fail_closed_on_policy_violation: true`
- `require_panel_ingest: true` (preserves consumer policy)
- `human_scheduler_forbidden: true` (preserves consumer policy)
- `emit_receipt_per_lane: true`
- `preserve_panels: true`

Adapter execution policy:
- **local_argv**: Enabled - executes when argv present
- **cursor_cloud_agent**: Disabled - emits BLOCKED_UNSUPPORTED descriptor
- **runtime_tool**: Disabled - emits BLOCKED_UNSUPPORTED descriptor
- **public_plan**: Informational only

### Receipt Schema

`dispatch-receipt.schema.json` defines machine-readable receipt structure:
- Required: receipt_version, lane_id, adapter_kind, dispatch_status, timestamp
- Status enum: DISPATCHED, EXECUTED, BLOCKED_UNSUPPORTED, BLOCKED_MISSING_ADAPTER, BLOCKED_POLICY_VIOLATION, FAILED
- Optional: exit_code, artifacts, autonomy_gap, blocking_reason, execution_details, descriptor

### Dispatch Runner

`dispatch_lanes.py` implements:
1. Load consumer policy + dispatch policy with validation
2. Ingest Triage manifest via `TriageConsumer`
3. Map lanes via `TriageConsumer.map_lane_to_asb_descriptor`
4. Execute adapters:
   - **local-argv**: subprocess.run with timeout, capture exit code, stdout, stderr
   - **cursor-cloud-agent**: emit BLOCKED_UNSUPPORTED with descriptor
   - **runtime-tool**: emit BLOCKED_UNSUPPORTED with descriptor
   - **public-plan**: emit DISPATCHED with plan ID
5. Write receipt JSON per lane
6. Write dispatch summary JSON
7. Exit with failure if any lane failed

**Usage**:
```bash
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  <manifest_path> [output_dir] [cwd]
```

### Validation

`scripts/Test-TriageAsbConsumerDispatch.ps1` validates:
- Dispatch infrastructure exists
- Policy enforces fail-closed and preserves consumer constraints
- Receipt schema defines required fields and status enums
- Fixtures parse and validate
- Dispatcher executes and generates receipts
- Consumer policy consistency preserved

## Deliverables

✓ Slice A: Upstream pin recorded in consumer policy
✓ Slice B: Dispatch infrastructure implemented
- Dispatch policy and receipt schema
- Durable dispatch runner
- Test fixtures and validator
- Public plan and registry entry

## Acceptance Criteria

- [x] Dispatch policy enforces fail_closed_on_policy_violation
- [x] Receipt schema validates against fixtures
- [x] Local argv lanes execute with exit codes
- [x] CloudAgent lanes emit fail-closed observed probe (BLOCKED_API) with precise blocker documentation
- [x] CloudAgent adapter detects execution environment and socket availability
- [x] No fake CloudAgent success - fail-closed until Python API implemented
- [x] Runtime tool lanes emit BLOCKED_UNSUPPORTED without faking success
- [x] Receipts are machine-readable JSON
- [x] Dispatcher smoke test passes
- [x] Consumer policy constraints preserved
- [ ] CI gates pass
- [ ] PR created and pushed

## Proof Ceiling

**Achieved**: Local argv dispatch + fail-closed CloudAgent probe with precise blocker

- Local argv lanes execute via subprocess with captured exit codes
- CloudAgent adapter detects Cursor cloud agent environment (CURSOR_AGENT=1, /run/cursor/api.sock)
- CloudAgent lanes emit BLOCKED_API (not BLOCKED_UNSUPPORTED) with diagnostic descriptor
- Descriptor documents exact blocker: Python API for Task tool not yet implemented
- Descriptor provides successor implementation path: Python binding to agent socket or orchestration-layer dispatch
- Receipt JSON validates against extended schema (added BLOCKED_HOST, BLOCKED_API statuses)
- Policy enforcement prevents execution of unsafe lanes

**Ceiling**: CloudAgent path may be descriptor+BLOCKED_UNSUPPORTED until later phase

Does NOT prove:
- Live Cursor CloudAgent dispatch and completion
- Runtime tool integration
- Live-target or provider execution

## Remaining Gap

**CloudAgent API Integration**: Successor phase to implement Python binding for Task tool:
- Python client for /run/cursor/api.sock to invoke Task tool from dispatch_lanes.py
- OR orchestration-layer dispatcher that executes via cloud agent with direct Task access
- Bounded wait with timeout for subagent completion
- Observed completion status (EXECUTED/FAILED) with artifacts and execution details
- Receipt generation with cloudAgentBcId and dashboard URL

**Current Proof Level**: Fail-closed observed probe with BLOCKED_API status when CloudAgent lane encountered. 
- Environment detection: Detects CURSOR_AGENT=1 and validates socket availability
- Precise blocker documentation: Returns BLOCKED_API (not BLOCKED_UNSUPPORTED) with exact required implementation
- Protected control maintained: local-argv lanes still execute with observed exit codes
- No fake success: Does not claim EXECUTED without observed completion evidence

## Validation Commands

```bash
# Test dispatch implementation
pwsh -NoLogo -NoProfile -File scripts/Test-TriageAsbConsumerDispatch.ps1

# Test consumer contract still valid
pwsh -NoLogo -NoProfile -File scripts/Test-TriageAsbConsumerContract.ps1

# Manual smoke test
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  tooling/harness/triage-consumer/dispatch/fixtures/test-dispatch-manifest.json \
  /tmp/test-dispatch-output
```

## Next Steps

1. Create PR for cursor/triage-dispatch-p07-d27e
2. Verify CI gates pass
3. Merge when gates permit
4. Report merge SHA and remaining gap status
