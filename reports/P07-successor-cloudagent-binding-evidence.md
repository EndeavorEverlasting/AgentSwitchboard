# P07 Successor — CloudAgent Task-tool Binding Evidence

## Implementation Summary

Implemented Python client and orchestration layer for Cursor cloud agent Task tool integration,
enabling Triage dispatch lanes to launch subagents via an orchestration protocol.

## Changed Files

### Core Implementation
- `tooling/harness/triage-consumer/dispatch/cursor_agent_client.py` (NEW)
  - Python client library for subagent launch requests
  - Request/result protocol over filesystem IPC
  - Orchestration support detection

- `tooling/harness/triage-consumer/dispatch/dispatch_lanes.py` (MODIFIED)
  - Integrated cursor_agent_client
  - Updated `_handle_cloud_agent()` to use orchestration
  - Returns EXECUTED with cloudAgentBcId when orchestration succeeds
  - Returns FAILED with timeout/error when orchestration unavailable

- `tooling/harness/triage-consumer/dispatch/orchestrate_cloud_agents.py` (NEW)
  - Orchestration marker/documentation script
  - Documents Task tool integration requirements

- `tooling/harness/triage-consumer/dispatch/dispatch_with_orchestration.py` (NEW)
  - Wrapper for running dispatch with orchestration support
  - Documents orchestration protocol for cloud agents

- `tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py` (NEW)
  - Test harness with mock orchestrator
  - Demonstrates request/result protocol

### Documentation & Fixtures
- `tooling/harness/triage-consumer/dispatch/ORCHESTRATION.md` (NEW)
  - Complete orchestration architecture documentation
  - Usage patterns and proof levels
  - Observed proof evidence

- `tooling/harness/triage-consumer/dispatch/fixtures/example-receipt-cloudagent-executed.json` (NEW)
  - Receipt example for successful cloud agent launch

- `tooling/harness/triage-consumer/dispatch/schemas/dispatch-receipt.schema.json` (MODIFIED)
  - Added description for EXECUTED status
  - Documented cloud agent execution_details fields

## Protected Control Evidence

**Requirement**: Re-prove local-argv still EXECUTED with exit_code capture

**Test**:
```bash
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  /tmp/protected-control-manifest.json /tmp/protected-control-output
```

**Receipt**:
```json
{
  "receipt_version": "v1",
  "lane_id": "protected-control-argv",
  "lane_mission": "Protected control test for local-argv with exit code capture",
  "adapter_kind": "local-argv",
  "dispatch_status": "FAILED",
  "timestamp": "2026-09-20T00:45:14.467742+00:00",
  "exit_code": 42,
  "execution_details": {
    "argv": ["python3", "-c", "import sys; print('PROTECTED_CONTROL_PASS'); sys.exit(42)"],
    "cwd": ".",
    "stdout": "PROTECTED_CONTROL_PASS\n",
    "stderr": "",
    "duration_ms": 8.368
  }
}
```

**Verdict**: ✅ PASS
- Status: FAILED (non-zero exit captured correctly)
- Exit code: 42 (exact exit code preserved)
- Stdout: "PROTECTED_CONTROL_PASS\n" (output captured)
- No regression in local-argv execution

## Cloud Agent Orchestration Evidence

### Mock Orchestrator Test

**Test**:
```bash
python3 tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py \
  /tmp/cloudagent-test-manifest.json /tmp/cloudagent-test-output
```

**Output**:
```
Dispatch complete: 1 executed, 0 failed, 1 total
[Orchestrator] Found request: req-1789865174065-3196.json
[Orchestrator] Processing request req-1789865174065-3196
[Orchestrator] Wrote result to req-1789865174065-3196.json
[Orchestrator] Deleted request req-1789865174065-3196.json
```

**Receipt**:
```json
{
  "receipt_version": "v1",
  "lane_id": "cloud-agent-test",
  "lane_mission": "Test cloud agent subagent launch via orchestration",
  "adapter_kind": "cursor-cloud-agent",
  "dispatch_status": "EXECUTED",
  "artifacts": ["https://cursor.com/agents/bc-mock-req-1789865174065-3196"],
  "execution_details": {
    "cloud_agent_id": "bc-mock-req-1789865174065-3196",
    "dashboard_url": "https://cursor.com/agents/bc-mock-req-1789865174065-3196",
    "duration_ms": 2000.506,
    "subagent_duration_seconds": 1.0
  }
}
```

**Verdict**: ✅ PASS (Orchestration Protocol)
- Request written to `/tmp/cursor-agent-requests/`
- Mock orchestrator processed request
- Result written to `/tmp/cursor-agent-results/`
- Receipt contains `execution_details.cloud_agent_id`
- Receipt contains dashboard URL in artifacts

### Real Task Tool Launch — Historical Observation Only

**EAT-301 disposition**: preserved as an unpromoted historical observation for EAT-302..308 reconciliation. It is not current proof that #332 provides an unattended ASB→Task→terminal-result bridge.

**Observed historically**: real subagent launch via Task tool during implementation

**Agent ID**: `bc-c863f8be-d1e9-54ee-9514-870b3245d5bb`

**Dashboard**: https://cursor.com/agents/bc-c863f8be-d1e9-54ee-9514-870b3245d5bb

**Task**:
```
Print "Hello from P07 test subagent" and confirm you're running as a cloud agent
by checking CURSOR_AGENT environment variable. Then exit successfully without
making any changes.
```

**Subagent Output**:
```
✓ Confirmed: Running as a cloud agent (`CURSOR_AGENT=1`)
Task complete. I've printed the test message, verified I'm running as a cloud agent,
and made no changes to the workspace as requested.
```

**Verdict**: HISTORICAL OBSERVATION — UNPROMOTED IN EAT-301
- A Task-tool launch was observed during the earlier implementation session.
- The observation is retained as successor evidence, not as proof of the repository path under EAT-301.
- Machine-closed ASB→Task dispatch and terminal-result capture remain required successor proof.

## Architecture

```
┌─────────────────────┐
│ dispatch_lanes.py   │  ← Client: writes requests, waits for results
│ (subprocess)        │
└──────────┬──────────┘
           │ filesystem IPC
           ▼
┌─────────────────────┐
│ /tmp/cursor-agent-  │
│   requests/         │  ← Shared request queue
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Orchestrator        │  ← Cloud agent with Task tool access
│ (monitors & launches)│
└──────────┬──────────┘
           │ Task tool
           ▼
┌─────────────────────┐
│ Subagent            │  ← Launched cloud agent
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ /tmp/cursor-agent-  │
│   results/          │  ← Completion results with cloudAgentBcId
└─────────────────────┘
```

## Proof Levels

### BLOCKED_HOST
- Not in cloud agent context
- CURSOR_AGENT != 1
- Fail-closed (preserved from P07)

### BLOCKED_API
- In cloud agent but no orchestrator active
- Orchestration support detected but requests timeout
- Fail-closed (preserved from P07)

### EXECUTED
- Orchestration active
- Subagent launched via Task tool
- Receipt includes `execution_details.cloud_agent_id`
- Receipt includes dashboard URL
- **NEW in P07 Successor**

### FAILED
- Orchestration active but subagent failed
- Or timeout waiting for orchestration
- Error details in execution_details
- **NEW in P07 Successor**

## Proof Ceiling

**EAT-301 active proof ceiling**: deterministic integration hygiene only.

This report preserves older implementation and runtime observations as historical inputs, but EAT-301 does not promote them into current runtime proof. Current branch/CI integration state must be read from refreshed provider evidence.

**Historical implementation evidence retained for successor reconciliation**:
1. Protected control behavior was previously exercised for local-argv exit-code capture.
2. The request/result filesystem protocol was previously exercised with a mock orchestrator.
3. Synthetic receipts use the serialized field `execution_details.cloud_agent_id` plus dashboard URL.
4. A real Task-tool launch was observed separately during implementation, but not through a machine-closed #332 production bridge.

**Does NOT Prove**:
- Unattended ASB→Task→terminal-result runtime
- CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED
- Production orchestrator deployment
- Concurrent subagent launches
- Complete failure-path handling

## Usage

### With Mock Orchestrator (Testing)
```bash
python3 tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py \
  <manifest_path> <output_dir>
```

### With Real Orchestrator (Production)
1. Cloud agent starts monitoring `/tmp/cursor-agent-requests/`
2. For each request, cloud agent uses Task tool to launch subagent
3. Cloud agent writes result to `/tmp/cursor-agent-results/<request_id>.json`
4. dispatch_lanes.py reads result and generates receipt

### Standalone (No Orchestration)
```bash
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  <manifest_path> <output_dir>
```
- Cloud agent lanes: FAILED with timeout after 300s
- Local argv lanes: EXECUTED/FAILED normally

## Next Steps

For full production deployment:
1. Implement persistent orchestrator service (monitors requests continuously)
2. Add error handling for subagent failures
3. Add concurrent request handling
4. Add request cleanup/expiration
5. Add observability/logging for orchestration

## Completion

- ✅ Python client implemented (cursor_agent_client.py)
- ✅ dispatch_lanes.py integrated with client
- ✅ Orchestration protocol documented
- ✅ Protected control verified (local-argv unchanged)
- ✅ Mock orchestrator test passes
- ✅ Real Task tool launch observed
- ✅ Receipts include cloudAgentBcId and dashboard URL
- ✅ Fail-closed behavior preserved
