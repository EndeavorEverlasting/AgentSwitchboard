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
- [x] CloudAgent lanes emit BLOCKED_UNSUPPORTED without faking success
- [x] Runtime tool lanes emit BLOCKED_UNSUPPORTED without faking success
- [x] Receipts are machine-readable JSON
- [x] Dispatcher smoke test passes
- [x] Consumer policy constraints preserved
- [ ] CI gates pass
- [ ] PR created and pushed

## Proof Ceiling

**Achieved**: Local argv dispatch + receipt contracts

- Local argv lanes execute via subprocess with captured exit codes
- CloudAgent/runtime-tool adapters emit structured BLOCKED_UNSUPPORTED receipts
- Receipt JSON validates against schema
- Policy enforcement prevents execution of unsafe lanes

**Ceiling**: CloudAgent path may be descriptor+BLOCKED_UNSUPPORTED until later phase

Does NOT prove:
- Live Cursor CloudAgent dispatch and completion
- Runtime tool integration
- Live-target or provider execution

## Remaining Gap

**Live CloudAgent Adapter**: Future phase to integrate live Cursor CloudAgent dispatch by:
- Implementing CloudAgent API/runtime_tool integration
- Launching agents and waiting for completion
- Capturing agent artifacts and outcomes
- Emitting EXECUTED/FAILED receipts with evidence

Until then, CloudAgent lanes emit BLOCKED_UNSUPPORTED with descriptors ready for future integration.

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
