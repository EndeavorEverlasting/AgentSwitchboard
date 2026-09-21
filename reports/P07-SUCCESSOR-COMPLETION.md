# P07 SUCCESSOR COMPLETION SUMMARY

## Task
EXECUTE P07 SUCCESSOR — CloudAgent Task-tool binding for Triage→ASB dispatch

## Mission
Implement the smallest durable Python (or PowerShell) client that can invoke Cursor cloud-agent Task launches via the observed agent surface, wire it into `tooling/harness/triage-consumer/dispatch/dispatch_lanes.py` `_handle_cloud_agent()`, and produce receipts with observed EXECUTED/FAILED plus cloud_agent_id/dashboard URL when a launch completes.

## Status
EAT-301 hygiene candidate. Historical successor implementation is preserved, but this report does not prove current merge, production readiness, or CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED.

## Merge Information
- **Branch**: `cursor/p07-successor-cloudagent-binding-1db0`
- **Historical implementation SHA**: `3d4bd22`
- **PR**: #332 (provider state is authoritative for current head/merge status)
- **Base**: `main`

## Implementation

### Core Components Created

1. **`cursor_agent_client.py`** (NEW - 211 lines)
   - `CursorAgentClient` class for launching subagents
   - `SubagentLaunchRequest` and `SubagentLaunchResult` dataclasses
   - `detect_orchestration_support()` function
   - Request/result protocol over filesystem IPC

2. **`dispatch_lanes.py`** (MODIFIED)
   - Integrated `cursor_agent_client` import
   - Updated `_handle_cloud_agent()` to use orchestration
   - Returns EXECUTED with cloud_agent_id when successful
   - Returns FAILED with error details when unsuccessful
   - Preserves fail-closed: BLOCKED_HOST/BLOCKED_API when unavailable

3. **`orchestrate_cloud_agents.py`** (NEW - 152 lines)
   - Orchestration marker script
   - Documents Task tool requirements
   - Metadata extraction from agent socket

4. **`dispatch_with_orchestration.py`** (NEW - 176 lines)
   - Wrapper for orchestrated dispatch
   - Documents orchestration protocol
   - Creates instructions file

5. **`test_cloud_agent_orchestration.py`** (NEW - 137 lines)
   - Test harness with mock orchestrator
   - Background thread monitors requests
   - Writes mock results with cloud_agent_id

### Documentation Created

6. **`ORCHESTRATION.md`** (NEW - 221 lines)
   - Complete architecture documentation
   - Request/result protocol specifications
   - Usage patterns (mock, live, standalone)
   - Proof levels explanation

7. **`P07-successor-cloudagent-binding-evidence.md`** (NEW - 324 lines)
   - Implementation summary
   - Protected control evidence
   - Mock orchestrator evidence
   - Real Task tool launch evidence
   - Architecture diagram
   - Proof ceiling analysis

### Fixtures & Schema

8. **`example-receipt-cloudagent-executed.json`** (NEW)
   - Receipt example with cloud_agent_id
   - Dashboard URL in artifacts
   - execution_details with subagent metadata

9. **`dispatch-receipt.schema.json`** (MODIFIED)
   - Added description for EXECUTED status
   - Documented cloud agent execution_details fields
   - Added cloud_agent_id, dashboard_url, subagent_duration_seconds

## Protected Control Evidence

✅ **Local-argv still EXECUTED with exit_code capture**

Test:
```bash
python3 dispatch_lanes.py /tmp/protected-control-manifest.json /tmp/protected-control-output
```

Receipt:
- Status: `FAILED` (non-zero exit)
- Exit code: `42` (captured correctly)
- Stdout: `PROTECTED_CONTROL_PASS\n` (captured)
- Duration: `8.368ms`

**Verdict**: ✅ PASS - No regression

## Cloud Agent Orchestration Evidence

### Mock Orchestrator Test

✅ **Protocol validated end-to-end**

Test:
```bash
python3 test_cloud_agent_orchestration.py /tmp/cloudagent-test-manifest.json /tmp/cloudagent-test-output
```

Output:
```
Dispatch complete: 1 executed, 0 failed, 1 total
[Orchestrator] Found request: req-1789865174065-3196.json
[Orchestrator] Processing request req-1789865174065-3196
[Orchestrator] Wrote result to req-1789865174065-3196.json
```

Receipt:
- Status: `EXECUTED`
- cloud_agent_id: `bc-mock-req-1789865174065-3196`
- Dashboard URL: `https://cursor.com/agents/bc-mock-req-1789865174065-3196`
- Duration: `2000.5ms`

**Verdict**: ✅ PASS - Orchestration protocol works

### Real Task Tool Launch — Historical Observation Only

**EAT-301 disposition**: preserved for EAT-302..308 reconciliation; not promoted as current #332 runtime proof.

**Observed historically**: subagent launch via Task tool

During implementation, launched real subagent to validate Task tool integration:

- **Agent ID**: `bc-c863f8be-d1e9-54ee-9514-870b3245d5bb`
- **Dashboard**: https://cursor.com/agents/bc-c863f8be-d1e9-54ee-9514-870b3245d5bb
- **Task**: Print test message and verify CURSOR_AGENT=1
- **Result**: Subagent executed successfully, confirmed cloud agent context

**Verdict**: HISTORICAL OBSERVATION — UNPROMOTED IN EAT-301

## Architecture

```
┌─────────────────────┐
│ dispatch_lanes.py   │  ← Client: writes launch requests
│ (subprocess)        │     polls for results
└──────────┬──────────┘
           │
           │ filesystem IPC
           ▼
┌─────────────────────┐
│ /tmp/cursor-agent-  │  ← Request queue
│   requests/         │     JSON files
└──────────┬──────────┘
           │
           │ monitored by
           ▼
┌─────────────────────┐
│ Orchestrator        │  ← Cloud agent with Task tool access
│ (cloud agent)       │     launches subagents
└──────────┬──────────┘
           │
           │ Task tool invocation
           ▼
┌─────────────────────┐
│ Subagent            │  ← Launched cloud agent
│ (generalPurpose)    │     executes prompt
└──────────┬──────────┘
           │
           │ completion
           ▼
┌─────────────────────┐
│ /tmp/cursor-agent-  │  ← Result queue
│   results/          │     JSON with cloud_agent_id
└──────────┬──────────┘
           │
           │ read by
           ▼
┌─────────────────────┐
│ dispatch_lanes.py   │  ← Generates receipt with:
│ returns receipt     │     - EXECUTED status
└─────────────────────┘     - cloud_agent_id
                            - dashboard URL
```

## Proof Levels

### BLOCKED_HOST
- Not in cloud agent context (`CURSOR_AGENT` != 1)
- Returns immediately with diagnostic
- Preserved from P07

### BLOCKED_API
- In cloud agent but orchestration support not detected
- Returns immediately with diagnostic
- Preserved from P07

### EXECUTED (NEW)
- Orchestration active
- Subagent launched successfully
- Receipt includes:
  - `cloud_agent_id` (e.g., `bc-c863f8be-d1e9-54ee-9514-870b3245d5bb`)
  - `dashboard_url` in artifacts
  - `duration_ms` and `subagent_duration_seconds`

### FAILED (NEW)
- Orchestration active but:
  - Subagent failed, OR
  - Timeout waiting for result (300s), OR
  - Error during launch
- Receipt includes error details

## Receipt Format

### EXECUTED Receipt
```json
{
  "receipt_version": "v1",
  "lane_id": "cloud-agent-test",
  "lane_mission": "Test cloud agent subagent launch",
  "adapter_kind": "cursor-cloud-agent",
  "dispatch_status": "EXECUTED",
  "timestamp": "2026-09-20T00:46:16.066242+00:00",
  "artifacts": ["https://cursor.com/agents/bc-mock-req-1789865174065-3196"],
  "execution_details": {
    "cloud_agent_id": "bc-mock-req-1789865174065-3196",
    "dashboard_url": "https://cursor.com/agents/bc-mock-req-1789865174065-3196",
    "duration_ms": 2000.506,
    "subagent_duration_seconds": 1.0
  }
}
```

## Usage

### With Mock Orchestrator (Testing)
```bash
python3 tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py \
  <manifest_path> <output_dir>
```

### With Real Orchestrator (Production)
1. Cloud agent monitors `/tmp/cursor-agent-requests/` for `*.json` files
2. For each request, uses Task tool to launch subagent
3. Writes result to `/tmp/cursor-agent-results/<request_id>.json`
4. dispatch_lanes.py reads result and generates receipt

### Standalone (No Orchestration)
```bash
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  <manifest_path> <output_dir>
```
- Cloud agent lanes: FAILED with timeout (300s) or BLOCKED if not in agent context
- Local argv lanes: EXECUTED/FAILED normally

## Proof Ceiling

**EAT-301 active proof ceiling**: deterministic integration hygiene only.

The implementation notes below retain historical observations for successor work, but they are not promoted to current runtime proof by this report. Current branch/check/merge state is provider truth.

**Historical evidence retained for EAT-302..308**:
1. local-argv protected-control behavior was previously observed.
2. request/result filesystem IPC was previously exercised with a mock orchestrator.
3. synthetic receipt generation uses `execution_details.cloud_agent_id` plus dashboard URL.
4. a real Task-tool launch was separately observed during implementation.
5. the Cursor socket metadata API was inspected.

**Does NOT Prove**:
- unattended ASB→Task→terminal-result execution
- CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED
- production orchestrator deployment
- concurrent subagent launches
- complete failed-subagent handling

## Files Changed

```
M  tooling/harness/triage-consumer/dispatch/dispatch_lanes.py
M  tooling/harness/triage-consumer/dispatch/schemas/dispatch-receipt.schema.json
A  tooling/harness/triage-consumer/dispatch/cursor_agent_client.py
A  tooling/harness/triage-consumer/dispatch/orchestrate_cloud_agents.py
A  tooling/harness/triage-consumer/dispatch/dispatch_with_orchestration.py
A  tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py
A  tooling/harness/triage-consumer/dispatch/ORCHESTRATION.md
A  tooling/harness/triage-consumer/dispatch/fixtures/example-receipt-cloudagent-executed.json
A  reports/P07-successor-cloudagent-binding-evidence.md
```

**Total**: 9 files changed, 1251 insertions(+), 31 deletions(-)

## API Discovery

During implementation, discovered the agent socket API:

**Socket**: `/run/cursor/api.sock` (UNIX domain socket, HTTP/1.1)

**Endpoints**:
- `GET /` → Returns `"v1/"`
- `GET /v1/meta-data/` → Lists available metadata paths
- `GET /v1/meta-data/agent/id` → Agent ID (e.g., `bc-c869879b-...`)
- `GET /v1/meta-data/agent/name` → Agent name
- `GET /v1/meta-data/turn/id` → Turn ID
- `GET /v1/meta-data/workspace/repo-url` → Repository URL

**Note**: The socket provides metadata only, not Task launching capability.
Task tool access is agent-native (available at the cloud agent layer, not via socket).

## Completion Checklist

- ✅ Python client implemented (cursor_agent_client.py)
- ✅ dispatch_lanes.py integrated with client
- ✅ Orchestration protocol documented (ORCHESTRATION.md)
- ✅ Protected control verified (local-argv exit code capture)
- ✅ Mock orchestrator test passes
- ✅ Real Task tool launch observed (bc-c863f8be-...)
- ✅ Receipts include cloud_agent_id
- ✅ Receipts include dashboard URL in artifacts
- ✅ Fail-closed behavior preserved (BLOCKED_HOST/BLOCKED_API)
- ✅ Schema updated with cloud agent fields
- ✅ Fixtures created for EXECUTED receipt
- ✅ Evidence document created
- ✅ Changes committed to branch
- ✅ Branch pushed to remote
- ✅ PR created (#332)

## Continuation

EAT-301 closes only after the refreshed PR head passes its exact-head hygiene/integration gates and is integrated according to repository policy. EAT-302 then reconciles the useful #332 transport/evidence behind execution-adapter v1.

**For production deployment**, implement persistent orchestrator service that:
1. Monitors `/tmp/cursor-agent-requests/` continuously
2. Uses Task tool for each request
3. Handles errors and timeouts
4. Supports concurrent requests
5. Cleans up expired requests

---

**Completed**: 2026-09-20T00:54:00+00:00
**Agent**: bc-c869879b-be8f-548f-9b89-c0611c691db0
**Proof Level**: EAT-301 deterministic integration hygiene; historical Task-tool observation retained but unpromoted
