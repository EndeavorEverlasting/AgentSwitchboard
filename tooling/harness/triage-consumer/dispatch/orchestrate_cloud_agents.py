#!/usr/bin/env python3
"""
Cloud agent orchestrator for processing subagent launch requests.

This orchestrator runs in a Cursor cloud agent context with Task tool access.
It monitors a requests directory for subagent launch requests written by
dispatch_lanes.py, launches the subagents, and writes results back.

Usage:
    python3 orchestrate_cloud_agents.py [requests_dir] [results_dir]

The orchestrator is designed to be called by a parent cloud agent that will
use the Task tool (not available directly to Python). The actual implementation
delegates to a shell script that the cloud agent can invoke.
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any\n\nfrom cursor_agent_client import atomic_write_json, get_orchestration_paths


class OrchestrationError(Exception):
    """Error during orchestration."""
    pass


def get_agent_metadata(key: str) -> Optional[str]:
    """
    Get metadata from the Cursor agent socket API.

    Args:
        key: Metadata key path (e.g., 'agent/id')

    Returns:
        Metadata value or None if unavailable
    """
    import socket

    socket_path = os.environ.get("CURSOR_AGENT_SOCKET")
    if not socket_path or not Path(socket_path).exists():
        return None

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect(socket_path)

        request = f"GET /v1/meta-data/{key} HTTP/1.1\r\nHost: cursor-agent\r\nConnection: close\r\n\r\n".encode()
        sock.send(request)

        response = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk

        sock.close()

        # Parse HTTP response body
        response_str = response.decode(errors='replace')
        parts = response_str.split('\r\n\r\n', 1)
        if len(parts) == 2:
            return parts[1].strip()

        return None
    except Exception:
        return None


def create_orchestration_marker(requests_dir: Path, results_dir: Path) -> Dict[str, Any]:
    """
    Create a marker file indicating orchestrator is needed.

    This is used when the orchestrator script is run but cannot actually
    perform orchestration (e.g., because Task tool isn't accessible from Python).
    The marker signals to a parent cloud agent that it should handle orchestration.

    Args:
        requests_dir: Directory to monitor for requests
        results_dir: Directory to write results

    Returns:
        Marker data
    """
    agent_id = get_agent_metadata("agent/id") or "unknown"

    marker = {
        "orchestrator_needed": True,
        "reason": "Python script cannot directly access Task tool; parent cloud agent must orchestrate",
        "requests_dir": str(requests_dir),
        "results_dir": str(results_dir),
        "agent_context": {
            "CURSOR_AGENT": os.environ.get("CURSOR_AGENT"),
            "CURSOR_AGENT_SOCKET": os.environ.get("CURSOR_AGENT_SOCKET"),
            "agent_id": agent_id
        },
        "instructions": {
            "parent_agent_action": "Monitor requests_dir for *.json files, use Task tool to launch subagents, write results to results_dir",
            "request_format": {
                "request_id": "string",
                "prompt": "string - task for subagent",
                "description": "string - short description",
                "timeout_seconds": "number"
            },
            "result_format": {
                "request_id": "string - must match request",
                "status": "string - 'completed', 'failed', or 'timeout'",
                "agent_id": "string - cloudAgentBcId (if successful)",
                "dashboard_url": "string - agent dashboard URL",
                "error": "string - error message (if failed)",
                "duration_seconds": "number"
            }
        },
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    marker_file = requests_dir.parent / "orchestration-required.json"
    with open(marker_file, 'w') as f:
        json.dump(marker, f, indent=2)

    return marker


def main():
    """Main orchestrator entry point."""
    requests_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/cursor-agent-requests")
    results_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/cursor-agent-results")

    requests_dir.mkdir(parents=True, exist_ok=True)
    results_dir.mkdir(parents=True, exist_ok=True)

    # Check if we're in a cloud agent context
    in_cloud_agent = os.environ.get("CURSOR_AGENT") == "1"
    agent_socket = os.environ.get("CURSOR_AGENT_SOCKET")

    if not in_cloud_agent or not agent_socket:
        print("ERROR: Orchestrator must run in Cursor cloud agent context", file=sys.stderr)
        print(f"CURSOR_AGENT={os.environ.get('CURSOR_AGENT')}", file=sys.stderr)
        print(f"CURSOR_AGENT_SOCKET={agent_socket}", file=sys.stderr)
        sys.exit(1)

    # Since Python cannot directly access the Task tool (it's a Cursor-native capability),
    # we create a marker file indicating orchestration is needed and exit.
    # The parent cloud agent will see this marker and handle orchestration.
    marker = create_orchestration_marker(requests_dir, results_dir)

    print("Orchestration marker created:")
    print(json.dumps(marker, indent=2))
    print()
    print("A parent Cursor cloud agent with Task tool access must:")
    print(f"1. Monitor: {requests_dir}")
    print(f"2. For each request: launch subagent using Task tool")
    print(f"3. Write results to: {results_dir}")

    sys.exit(0)


if __name__ == "__main__":
    main()
