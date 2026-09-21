#!/usr/bin/env python3
"""
Dispatcher orchestration wrapper for Cursor cloud agents.

This script is designed to be called by a Cursor cloud agent that has Task tool access.
It runs dispatch_lanes.py as a subprocess and orchestrates any cloud agent launches
that dispatch_lanes.py requests via the cursor_agent_client.

The orchestration happens at this layer (with Task tool access) rather than within
dispatch_lanes.py (which runs as a subprocess without Task tool access).

Usage:
    python3 dispatch_with_orchestration.py <manifest_path> [output_dir] [cwd]

This wrapper should be called by cloud agents. It will:
1. Start monitoring for subagent launch requests
2. Run dispatch_lanes.py as a subprocess
3. When dispatch_lanes.py requests a subagent launch, handle it with Task tool
4. Write results back for dispatch_lanes.py to consume
5. Exit when dispatch_lanes.py completes
"""

import json
import os
import sys
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any, List


# This is a marker script that documents the orchestration interface.
# Actual Task tool invocation happens at the agent level (not directly from Python).
# A cloud agent running this script should:
# 1. Monitor /tmp/cursor-agent-requests/ for *.json request files
# 2. For each request, use the Task tool to launch a subagent
# 3. Write results to /tmp/cursor-agent-results/<request_id>.json


def create_orchestration_instructions() -> Dict[str, Any]:
    """
    Create instructions for the cloud agent orchestrator.

    Returns:
        Orchestration instructions and metadata
    """
    return {
        "orchestration_protocol": {
            "version": "v1",
            "description": "Protocol for cloud agent orchestration of subagent launches",
            "requests_dir": "/tmp/cursor-agent-requests",
            "results_dir": "/tmp/cursor-agent-results",
            "workflow": [
                "1. Cloud agent monitors requests_dir for *.json files",
                "2. Each file is a SubagentLaunchRequest (see request_schema)",
                "3. Cloud agent uses Task tool to launch subagent with request.prompt and request.description",
                "4. Cloud agent waits for subagent completion (bounded by request.timeout_seconds)",
                "5. Cloud agent writes SubagentLaunchResult to results_dir/<request_id>.json",
                "6. Cloud agent deletes the request file after processing"
            ]
        },
        "request_schema": {
            "request_id": "string - unique identifier",
            "prompt": "string - task prompt for subagent",
            "description": "string - short description for subagent",
            "timeout_seconds": "integer - max wait time",
            "submitted_at": "string - ISO timestamp"
        },
        "result_schema": {
            "request_id": "string - matches request",
            "status": "string - 'completed', 'failed', or 'timeout'",
            "agent_id": "string - cloudAgentBcId (optional)",
            "dashboard_url": "string - agent dashboard URL (optional)",
            "error": "string - error message if failed (optional)",
            "duration_seconds": "number - subagent execution time (optional)",
            "completed_at": "string - ISO timestamp"
        },
        "task_tool_parameters": {
            "subagent_type": "generalPurpose",
            "description": "<from request.description>",
            "prompt": "<from request.prompt>",
            "run_in_background": False,
            "note": "Wait for completion to get cloudAgentBcId and status"
        },
        "example_task_tool_usage": {
            "explanation": "Cloud agent should use Task tool like this",
            "pseudo_code": [
                "request = read_json(request_file)",
                "result = Task(",
                "    subagent_type='generalPurpose',",
                "    description=request['description'],",
                "    prompt=request['prompt'],",
                "    run_in_background=False",
                ")",
                "write_json(result_file, {",
                "    'request_id': request['request_id'],",
                "    'status': 'completed' if result.success else 'failed',",
                "    'agent_id': result.agent_id,",
                "    'dashboard_url': f'https://cursor.com/agents/{result.agent_id}',",
                "    'error': result.error if not result.success else None,",
                "    'duration_seconds': result.duration",
                "})"
            ]
        }
    }


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: dispatch_with_orchestration.py <manifest_path> [output_dir] [cwd]")
        sys.exit(1)

    # Check if we're in a cloud agent
    in_cloud_agent = os.environ.get("CURSOR_AGENT") == "1"

    if not in_cloud_agent:
        print("ERROR: This wrapper requires CURSOR_AGENT=1", file=sys.stderr)
        print("Run this script from within a Cursor cloud agent that has Task tool access", file=sys.stderr)
        sys.exit(1)

    # Write orchestration instructions
    instructions = create_orchestration_instructions()
    instructions_file = Path("/tmp/cursor-agent-orchestration-instructions.json")
    with open(instructions_file, 'w') as f:
        json.dump(instructions, f, indent=2)

    print("=" * 80)
    print("CLOUD AGENT ORCHESTRATION WRAPPER")
    print("=" * 80)
    print()
    print("This wrapper runs dispatch_lanes.py and orchestrates subagent launches.")
    print()
    print(f"Orchestration instructions written to: {instructions_file}")
    print()
    print("The cloud agent running this wrapper should:")
    print("  1. Monitor /tmp/cursor-agent-requests/ for subagent launch requests")
    print("  2. Use the Task tool to launch subagents as requested")
    print("  3. Write results to /tmp/cursor-agent-results/")
    print()
    print("dispatch_lanes.py will handle the orchestration client side automatically.")
    print()
    print("=" * 80)
    print()

    # Run dispatch_lanes.py
    script_dir = Path(__file__).parent
    dispatch_script = script_dir / "dispatch_lanes.py"

    manifest_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "./dispatch-receipts"
    cwd = sys.argv[3] if len(sys.argv) > 3 else None

    cmd = ["python3", str(dispatch_script), manifest_path, output_dir]
    if cwd:
        cmd.append(cwd)

    print(f"Running: {' '.join(cmd)}")
    print()

    result = subprocess.run(cmd)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
