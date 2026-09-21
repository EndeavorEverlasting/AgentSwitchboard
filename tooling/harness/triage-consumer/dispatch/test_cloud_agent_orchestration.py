#!/usr/bin/env python3
"""Deterministic contract test for Cursor cloud-agent orchestration."""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from cursor_agent_client import (
    CursorAgentClient,
    atomic_write_json,
    detect_orchestration_support,
    write_orchestrator_readiness,
)


@contextmanager
def temporary_environment(values):
    previous = {key: os.environ.get(key) for key in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def parse_deadline(value):
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("expires_at must include timezone")
    return parsed.astimezone(timezone.utc)


def monitor_and_respond_to_requests(
    requests_dir,
    results_dir,
    readiness_file,
    stop_event,
):
    """Act as an active mock parent monitor with the production readiness contract."""

    monitor_id = f"mock-monitor-{os.getpid()}"
    try:
        while not stop_event.is_set():
            write_orchestrator_readiness(
                readiness_file,
                requests_dir,
                results_dir,
                monitor_id,
            )

            for request_file in list(requests_dir.glob("*.json")):
                try:
                    with open(request_file, "r", encoding="utf-8") as handle:
                        request = json.load(handle)

                    if datetime.now(timezone.utc) >= parse_deadline(
                        request["expires_at"]
                    ):
                        request_file.unlink(missing_ok=True)
                        continue

                    request_id = request["request_id"]
                    result_file = results_dir / f"{request_id}.json"
                    atomic_write_json(
                        result_file,
                        {
                            "request_id": request_id,
                            "status": "completed",
                            "agent_id": f"bc-mock-{request_id}",
                            "dashboard_url": (
                                "https://cursor.com/agents/"
                                f"bc-mock-{request_id}"
                            ),
                            "error": None,
                            "duration_seconds": 0.01,
                            "completed_at": (
                                datetime.now(timezone.utc).isoformat()
                            ),
                        },
                    )
                    request_file.unlink(missing_ok=True)
                except FileNotFoundError:
                    continue

            stop_event.wait(0.02)
    finally:
        readiness_file.unlink(missing_ok=True)


def write_synthetic_manifest(path):
    manifest = {
        "schema_version": "1.0",
        "run_id": "cloud-agent-orchestration-contract",
        "graph_width": 1,
        "parallel_disposition": "safe",
        "autonomy_gap": None,
        "lanes": [
            {
                "lane_id": "lane-cloud-agent-executed",
                "mission": "Prove active-monitor cloud-agent execution receipt",
                "dependencies": [],
                "owned_mutation_surfaces": ["synthetic-test"],
                "forbidden_surfaces": [],
                "adapter": {"kind": "cursor-cloud-agent"},
                "launch": {
                    "mode": "runtime_tool",
                    "tool": "cursor-cloud-agent",
                },
                "expected_artifacts": [],
                "validation": [],
                "convergence_owner": "test",
                "status": "PLANNED",
            }
        ],
    }
    atomic_write_json(path, manifest)


def assert_cloud_receipt(output_dir):
    receipts = []
    for path in Path(output_dir).glob("*.json"):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, json.JSONDecodeError):
            continue
        if payload.get("adapter_kind") == "cursor-cloud-agent":
            receipts.append(payload)

    if not receipts:
        raise AssertionError("no cursor-cloud-agent receipt was generated")

    for receipt in receipts:
        if receipt.get("dispatch_status") != "EXECUTED":
            raise AssertionError(
                "cloud-agent receipt was not EXECUTED: "
                f"{receipt.get('dispatch_status')}"
            )
        details = receipt.get("execution_details") or {}
        if not details.get("cloud_agent_id"):
            raise AssertionError("EXECUTED receipt missing cloud_agent_id")
        if not details.get("dashboard_url"):
            raise AssertionError("EXECUTED receipt missing dashboard_url")


def main():
    script_dir = Path(__file__).parent
    dispatch_script = script_dir / "dispatch_lanes.py"

    with tempfile.TemporaryDirectory(
        prefix="agentswitchboard-cloud-agent-contract-"
    ) as temp_root:
        root = Path(temp_root)
        requests_dir = root / "requests"
        results_dir = root / "results"
        readiness_file = root / "orchestrator-ready.json"
        socket_file = root / "agent.sock"
        manifest_path = (
            Path(sys.argv[1]) if len(sys.argv) > 1 else root / "manifest.json"
        )
        output_dir = (
            Path(sys.argv[2]) if len(sys.argv) > 2 else root / "receipts"
        )

        requests_dir.mkdir(parents=True, exist_ok=True)
        results_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        socket_file.touch()

        if len(sys.argv) <= 1:
            write_synthetic_manifest(manifest_path)

        env_values = {
            "CURSOR_AGENT": "1",
            "CURSOR_AGENT_SOCKET": str(socket_file),
            "CURSOR_AGENT_REQUESTS_DIR": str(requests_dir),
            "CURSOR_AGENT_RESULTS_DIR": str(results_dir),
            "CURSOR_AGENT_ORCHESTRATOR_READY": str(readiness_file),
            "CURSOR_AGENT_ORCHESTRATOR_READY_MAX_AGE_SECONDS": "2",
        }

        with temporary_environment(env_values):
            unsupported = detect_orchestration_support()
            if unsupported["supported"]:
                raise AssertionError(
                    "orchestration incorrectly supported without readiness"
                )

            timed = CursorAgentClient(
                requests_dir=requests_dir,
                results_dir=results_dir,
            ).launch_subagent(
                prompt="timeout-control",
                description="timeout control",
                timeout_seconds=0.05,
                poll_interval=0.01,
            )
            if timed.status != "timeout":
                raise AssertionError(
                    f"timeout control returned {timed.status!r}"
                )
            if list(requests_dir.glob("*.json")):
                raise AssertionError("timed-out request remained launchable")

            stop_event = threading.Event()
            monitor = threading.Thread(
                target=monitor_and_respond_to_requests,
                args=(
                    requests_dir,
                    results_dir,
                    readiness_file,
                    stop_event,
                ),
                daemon=True,
            )
            monitor.start()

            deadline = time.monotonic() + 2
            while not readiness_file.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            if not readiness_file.exists():
                raise AssertionError("mock monitor did not publish readiness")

            support = detect_orchestration_support()
            if not support["supported"]:
                raise AssertionError(
                    f"active monitor not detected: {support['reason']}"
                )

            result = subprocess.run(
                [
                    sys.executable,
                    str(dispatch_script),
                    str(manifest_path),
                    str(output_dir),
                ],
                env=os.environ.copy(),
                check=False,
            )

            stop_event.set()
            monitor.join(timeout=2)

            if result.returncode != 0:
                raise AssertionError(
                    f"dispatch exited with code {result.returncode}"
                )

            assert_cloud_receipt(output_dir)

    print("PASS cloud-agent orchestration contract")


if __name__ == "__main__":
    main()
