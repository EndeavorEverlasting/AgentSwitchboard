#!/usr/bin/env python3
"""
Cursor cloud-agent dispatch wrapper.

This wrapper does not itself have Task-tool access. It may run dispatch_lanes.py
only after an active parent-agent request monitor has published a fresh readiness
heartbeat for the same request/result paths.
"""

import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

from cursor_agent_client import (
    READINESS_PROTOCOL,
    atomic_write_json,
    detect_orchestration_support,
    get_orchestration_paths,
)


def create_orchestration_instructions() -> Dict[str, Any]:
    """Return the parent-monitor protocol for Cursor Task-tool dispatch."""

    requests_dir, results_dir, readiness_file = get_orchestration_paths()
    return {
        "orchestration_protocol": {
            "version": "v1",
            "description": (
                "Parent cloud agent monitors launch requests and uses the Cursor "
                "Task tool to execute them."
            ),
            "requests_dir": str(requests_dir),
            "results_dir": str(results_dir),
            "readiness_file": str(readiness_file),
            "readiness_protocol": READINESS_PROTOCOL,
            "workflow": [
                "1. Parent agent starts an active request monitor.",
                "2. Monitor writes and refreshes the readiness heartbeat.",
                "3. Dispatcher atomically publishes a request JSON document.",
                "4. Monitor rejects expired requests using expires_at.",
                "5. Monitor uses Task tool to launch the requested subagent.",
                "6. Monitor atomically publishes the result JSON document.",
                "7. Monitor removes the processed request.",
            ],
        },
        "request_schema": {
            "request_id": "string - unique identifier",
            "prompt": "string - task prompt for subagent",
            "description": "string - short description for subagent",
            "timeout_seconds": "integer - max wait time",
            "submitted_at": "string - ISO timestamp",
            "expires_at": "string - absolute ISO deadline; monitor must enforce",
        },
        "result_schema": {
            "request_id": "string - matches request",
            "status": "string - 'completed', 'failed', or 'timeout'",
            "agent_id": "string - required when status is completed",
            "dashboard_url": "string - required when status is completed",
            "error": "string - error message if failed (optional)",
            "duration_seconds": "number - subagent execution time (optional)",
            "completed_at": "string - ISO timestamp",
        },
    }


def main() -> None:
    if len(sys.argv) < 2:
        print(
            "Usage: dispatch_with_orchestration.py "
            "<manifest_path> [output_dir] [cwd]"
        )
        raise SystemExit(1)

    if os.environ.get("CURSOR_AGENT") != "1":
        print(
            "ERROR: This wrapper requires CURSOR_AGENT=1",
            file=sys.stderr,
        )
        raise SystemExit(1)

    _, _, readiness_file = get_orchestration_paths()
    instructions_file = Path(
        os.environ.get("CURSOR_AGENT_ORCHESTRATION_INSTRUCTIONS")
        or (readiness_file.parent / "cursor-agent-orchestration-instructions.json")
    )
    atomic_write_json(instructions_file, create_orchestration_instructions())

    support = detect_orchestration_support()
    if not support["supported"]:
        print(
            "BLOCKED_API: active parent-agent request monitor is not ready: "
            f"{support['reason']}",
            file=sys.stderr,
        )
        print(f"DETAILS: {support['details']}", file=sys.stderr)
        raise SystemExit(2)

    script_dir = Path(__file__).parent
    dispatch_script = script_dir / "dispatch_lanes.py"
    manifest_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else "./dispatch-receipts"
    cwd = sys.argv[3] if len(sys.argv) > 3 else None

    cmd = [sys.executable, str(dispatch_script), manifest_path, output_dir]
    if cwd:
        cmd.append(cwd)

    result = subprocess.run(cmd, check=False)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
