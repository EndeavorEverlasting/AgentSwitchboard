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
    observed_prompts,
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
                    observed_prompts.append(request["prompt"])
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


def cloud_lane(
    lane_id,
    mission,
    *,
    dependencies=None,
    status="PLANNED",
    owned=None,
    forbidden=None,
    artifacts=None,
    validation=None,
    convergence_owner="triage-coordinator",
):
    return {
        "lane_id": lane_id,
        "mission": mission,
        "dependencies": dependencies or [],
        "owned_mutation_surfaces": owned or [],
        "forbidden_surfaces": forbidden or [],
        "adapter": {"kind": "cursor-cloud-agent"},
        "launch": {
            "mode": "runtime_tool",
            "tool": "cursor-cloud-agent",
        },
        "expected_artifacts": artifacts or [],
        "validation": validation or [],
        "convergence_owner": convergence_owner,
        "status": status,
    }


def write_synthetic_manifest(path):
    manifest = {
        "schema_version": "1.0",
        "run_id": "cloud-agent-orchestration-contract",
        "graph_width": 3,
        "parallel_disposition": "safe",
        "autonomy_gap": None,
        "lanes": [
            cloud_lane(
                "lane-cloud-agent-executed",
                "Prove bounded active-monitor cloud-agent execution",
                owned=["src/ready.py"],
                forbidden=["secrets/"],
                artifacts=["reports/ready.json"],
                validation=["python validate_ready.py"],
            ),
            cloud_lane(
                "lane-cloud-agent-dependency-blocked",
                "Must not launch before prerequisite completion",
                dependencies=["lane-prerequisite"],
                owned=["src/dependency-blocked.py"],
            ),
            cloud_lane(
                "lane-cloud-agent-status-blocked",
                "Must not relaunch a non-PLANNED lane",
                status="COMPLETE",
                owned=["src/status-blocked.py"],
            ),
        ],
    }
    atomic_write_json(path, manifest)


def load_receipt(output_dir, lane_id):
    path = Path(output_dir) / f"receipt-{lane_id}.json"
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def assert_executed_receipt(receipt):
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


def assert_synthetic_regressions(output_dir, observed_prompts):
    ready = load_receipt(output_dir, "lane-cloud-agent-executed")
    assert_executed_receipt(ready)

    for lane_id in (
        "lane-cloud-agent-dependency-blocked",
        "lane-cloud-agent-status-blocked",
    ):
        receipt = load_receipt(output_dir, lane_id)
        if receipt.get("dispatch_status") != "BLOCKED_POLICY_VIOLATION":
            raise AssertionError(
                f"{lane_id} unexpectedly dispatched: "
                f"{receipt.get('dispatch_status')}"
            )

    if len(observed_prompts) != 1:
        raise AssertionError(
            "only the dependency-ready PLANNED lane may reach the monitor; "
            f"observed {len(observed_prompts)} requests"
        )

    prompt = observed_prompts[0]
    required_fragments = (
        '"owned_mutation_surfaces"',
        '"src/ready.py"',
        '"forbidden_surfaces"',
        '"secrets/"',
        '"expected_artifacts"',
        '"reports/ready.json"',
        '"validation"',
        '"python validate_ready.py"',
        '"dependencies"',
        '"convergence_owner"',
        '"triage-coordinator"',
        '"launch"',
    )
    missing = [fragment for fragment in required_fragments if fragment not in prompt]
    if missing:
        raise AssertionError(
            "bounded cloud-agent prompt omitted contract fields: "
            + ", ".join(missing)
        )


def assert_supplied_manifest_has_executed_cloud_receipt(output_dir):
    receipts = []
    for path in Path(output_dir).glob("receipt-*.json"):
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        if payload.get("adapter_kind") == "cursor-cloud-agent":
            receipts.append(payload)

    if not receipts:
        raise AssertionError("no cursor-cloud-agent receipt was generated")
    executed = [
        receipt for receipt in receipts
        if receipt.get("dispatch_status") == "EXECUTED"
    ]
    if not executed:
        raise AssertionError("no cursor-cloud-agent lane executed")
    for receipt in executed:
        assert_executed_receipt(receipt)


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
        supplied_manifest = len(sys.argv) > 1
        manifest_path = (
            Path(sys.argv[1]) if supplied_manifest else root / "manifest.json"
        )
        output_dir = (
            Path(sys.argv[2]) if len(sys.argv) > 2 else root / "receipts"
        )

        requests_dir.mkdir(parents=True, exist_ok=True)
        results_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        socket_file.touch()

        if not supplied_manifest:
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
            observed_prompts = []
            monitor = threading.Thread(
                target=monitor_and_respond_to_requests,
                args=(
                    requests_dir,
                    results_dir,
                    readiness_file,
                    stop_event,
                    observed_prompts,
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

            if supplied_manifest:
                assert_supplied_manifest_has_executed_cloud_receipt(output_dir)
            else:
                assert_synthetic_regressions(
                    output_dir,
                    observed_prompts,
                )

    print("PASS cloud-agent orchestration contract")


if __name__ == "__main__":
    main()
