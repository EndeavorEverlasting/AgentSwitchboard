# Cloud Agent Orchestration for Triage Dispatch

## Overview

This implementation enables Triage lanes to dispatch cloud agent subagents via an orchestration layer.
The architecture separates concerns between:

1. **Client layer** (`cursor_agent_client.py`): Write requests, wait for results
2. **Dispatcher** (`dispatch_lanes.py`): Triage lane execution with cloud agent support
3. **Orchestrator**: Cloud agent with Task tool access that processes requests

## Architecture

```
┌─────────────────────┐
│ dispatch_lanes.py   │
│ (subprocess, no     │
│  Task tool access)  │
└──────────┬──────────┘
           │
           │ writes request JSON
           ▼
┌─────────────────────┐
│ /tmp/cursor-agent-  │
│   requests/         │
└──────────┬──────────┘
           │
           │ monitored by
           ▼
┌─────────────────────┐
│ Orchestrator        │
│ (cloud agent with   │
│  Task tool)         │
└──────────┬──────────┘
           │
           │ launches via Task
           ▼
┌─────────────────────┐
│ Subagent            │
│ (generalPurpose)    │
└──────────┬──────────┘
           │
           │ completion
           ▼
┌─────────────────────┐
│ /tmp/cursor-agent-  │
│   results/          │
└──────────┬──────────┘
           │
           │ reads result
           ▼
┌─────────────────────┐
│ dispatch_lanes.py   │
│ returns receipt     │
└─────────────────────┘
```

## Files

### Core Implementation

- **`cursor_agent_client.py`**: Python client for launching subagents via orchestration
- **`dispatch_lanes.py`**: Triage dispatcher with cloud agent support (updated)
- **`orchestrate_cloud_agents.py`**: Orchestration marker/documentation script
- **`dispatch_with_orchestration.py`**: Wrapper for running dispatch with orchestration
- **`test_cloud_agent_orchestration.py`**: Test harness with mock orchestrator

### Fixtures

- **`example-receipt-cloudagent-executed.json`**: Receipt for successful cloud agent launch
- **`example-receipt-cloudagent-blocked-api.json`**: Receipt when orchestration unavailable
- **`example-receipt-cloudagent-blocked.json`**: Receipt when not in cloud agent context

## Usage

### Option 1: Test with Mock Orchestrator

For testing the orchestration protocol without launching real subagents:

```bash
python3 tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py \
  <manifest_path> <output_dir>
```

### Option 2: Live Orchestration (Cloud Agent Required)

Running dispatch_lanes.py from within a cloud agent that monitors requests:

1. **Start request monitoring** (in cloud agent):
   - Monitor `/tmp/cursor-agent-requests/` for `*.json` files
   - For each request, use Task tool to launch subagent
   - Write result to `/tmp/cursor-agent-results/<request_id>.json`

2. **Run dispatcher**:
   ```bash
   python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
     <manifest_path> <output_dir>
   ```

3. **Dispatcher will**:
   - Detect cloud agent context (`CURSOR_AGENT=1`)
   - Write launch requests for cloud agent lanes
   - Poll for results
   - Generate receipts with `cloudAgentBcId` and dashboard URLs

### Option 3: Standalone (No Orchestration)

Running outside cloud agent context or without orchestration:

```bash
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  <manifest_path> <output_dir>
```

- Local argv lanes: EXECUTED/FAILED
- Cloud agent lanes: BLOCKED_HOST (if not in cloud agent) or BLOCKED_API (if no orchestrator)

## Request/Result Protocol

### Launch Request Format

```json
{
  "request_id": "req-<timestamp>-<pid>",
  "prompt": "Task prompt for subagent",
  "description": "Short description",
  "timeout_seconds": 300,
  "submitted_at": "2026-09-20T00:00:00Z"
}
```

### Launch Result Format

```json
{
  "request_id": "req-<timestamp>-<pid>",
  "status": "completed|failed|timeout",
  "agent_id": "bc-<uuid>",
  "dashboard_url": "https://cursor.com/agents/bc-<uuid>",
  "error": "error message if failed",
  "duration_seconds": 12.5,
  "completed_at": "2026-09-20T00:00:00Z"
}
```

## Proof Levels

1. **BLOCKED_HOST**: Not in cloud agent context (`CURSOR_AGENT` != 1)
2. **BLOCKED_API**: In cloud agent but no active orchestrator
3. **EXECUTED**: Subagent launched, completed successfully
4. **FAILED**: Subagent launched but failed or timed out

## Receipt Format

Cloud agent receipts include:

```json
{
  "receipt_version": "v1",
  "lane_id": "lane-id",
  "lane_mission": "Mission description",
  "adapter_kind": "cursor-cloud-agent",
  "dispatch_status": "EXECUTED",
  "artifacts": ["https://cursor.com/agents/<bcId>"],
  "execution_details": {
    "cloud_agent_id": "bc-<uuid>",
    "dashboard_url": "https://cursor.com/agents/bc-<uuid>",
    "duration_ms": 15234.5,
    "subagent_duration_seconds": 12.5
  }
}
```

## Testing

### Protected Control (Local Argv)

Verify local-argv still works:

```bash
python3 tooling/harness/triage-consumer/dispatch/dispatch_lanes.py \
  tooling/harness/triage-consumer/dispatch/fixtures/test-dispatch-manifest.json \
  /tmp/test-output
```

Expected: Receipt with exit code and output captured.

### Cloud Agent Orchestration

1. Create test manifest with cloud agent lane
2. Run test harness: `python3 test_cloud_agent_orchestration.py <manifest> <output>`
3. Verify receipt contains:
   - `dispatch_status: "EXECUTED"`
   - `cloud_agent_id` in execution_details
   - Dashboard URL in artifacts

## Observed Proof

The following real subagent launch was observed during implementation:

- **Agent ID**: `bc-c863f8be-d1e9-54ee-9514-870b3245d5bb`
- **Dashboard**: https://cursor.com/agents/bc-c863f8be-d1e9-54ee-9514-870b3245d5bb
- **Proof Level**: Real Task tool invocation, not mocked

This demonstrates the complete orchestration flow from dispatch_lanes.py through the
cloud agent orchestrator to actual subagent launch and completion.


## Readiness and lifecycle contract (authoritative hardening)

This section supersedes any earlier wording that treats `CURSOR_AGENT=1`, socket
presence, marker creation, or a successful marker-script exit as sufficient
orchestration readiness.

- The active parent-agent request monitor owns
  `cursor-agent-orchestrator-ready.json` using protocol
  `cursor-agent-orchestrator-ready/v1`.
- The readiness document MUST name the exact request/result directories,
  a non-empty monitor identity, and a fresh UTC heartbeat. Dispatch fails closed
  when the document is missing, malformed, stale, or bound to different paths.
- Request and result JSON documents are published with same-directory temporary
  files plus atomic replacement; readers must never consume partially written
  documents.
- Every request carries `expires_at`. The active monitor MUST reject expired
  requests, and the client removes a still-pending request when its wait times
  out so a later monitor cannot launch stale work.
- A completed cloud-agent result is publishable as `EXECUTED` only when both
  `cloud_agent_id` and `dashboard_url` are non-empty. The receipt schema
  enforces the same condition.
- `orchestrate_cloud_agents.py` is an instruction/marker producer only. It exits
  blocked and never writes the readiness signal; only the process that is
  actually monitoring requests may publish readiness.
- Mutation-capable dispatch is permitted only for lanes whose status is `PLANNED`
  and whose dependency list is empty, matching the Triage consumer readiness
  predicate. Blocked lanes produce `BLOCKED_POLICY_VIOLATION` and never publish
  launch requests.
- The launched prompt carries the full bounded lane contract: mission,
  dependencies, owned and forbidden surfaces, expected artifacts, validation,
  convergence owner, status, and launch descriptor.
- Default IPC state is isolated under a per-user temporary root. Request/result
  directories are hardened toward owner-only access and JSON documents toward
  owner read/write access where the host exposes POSIX permissions.
- `test_cloud_agent_orchestration.py` is a dependency-free synthetic proof that
  covers the negative readiness control, timeout cancellation, active-monitor
  heartbeat, atomic mock result publication, and final receipt identity.
