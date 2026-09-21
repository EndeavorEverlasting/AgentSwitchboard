#!/usr/bin/env python3
"""
Cursor cloud-agent client for dispatch workflows.

The client publishes launch requests for an active parent-agent request monitor.
Support is fail-closed: cloud-agent/socket presence is necessary but not sufficient;
a fresh readiness heartbeat from the active monitor is also required.
"""

import json
import os
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Optional, Tuple


READINESS_PROTOCOL = "cursor-agent-orchestrator-ready/v1"
DEFAULT_READINESS_MAX_AGE_SECONDS = 15.0


@dataclass
class SubagentLaunchRequest:
    """Request to launch a cloud-agent subagent."""

    request_id: str
    prompt: str
    description: str
    timeout_seconds: int = 300


@dataclass
class SubagentLaunchResult:
    """Result from a subagent launch."""

    request_id: str
    status: str  # "completed", "failed", "timeout"
    agent_id: Optional[str] = None
    dashboard_url: Optional[str] = None
    error: Optional[str] = None
    duration_seconds: Optional[float] = None


def _private_default_root() -> Path:
    identity = re.sub(r"[^A-Za-z0-9_.-]", "_", getpass.getuser()) or "user"
    return Path(tempfile.gettempdir()) / f"agentswitchboard-cursor-{identity}"


def _ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        # Windows and some mounted filesystems do not expose POSIX mode semantics.
        pass


def get_orchestration_paths() -> Tuple[Path, Path, Path]:
    """Resolve request/result/readiness paths from environment or private temp root."""

    configured_root = os.environ.get("CURSOR_AGENT_ORCHESTRATION_ROOT")
    root = Path(configured_root) if configured_root else _private_default_root()
    if not configured_root:
        _ensure_private_dir(root)

    requests_dir = Path(
        os.environ.get("CURSOR_AGENT_REQUESTS_DIR")
        or (root / "cursor-agent-requests")
    )
    results_dir = Path(
        os.environ.get("CURSOR_AGENT_RESULTS_DIR")
        or (root / "cursor-agent-results")
    )
    readiness_file = Path(
        os.environ.get("CURSOR_AGENT_ORCHESTRATOR_READY")
        or (root / "cursor-agent-orchestrator-ready.json")
    )
    return requests_dir, results_dir, readiness_file


def atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    """Publish private JSON atomically so readers never observe a partial document."""

    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp_path = path.with_name(
        f".{path.name}.{os.getpid()}.{time.time_ns()}.tmp"
    )
    descriptor = None
    try:
        descriptor = os.open(
            temp_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            json.dump(payload, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
        try:
            path.chmod(0o600)
        except OSError:
            pass
    finally:
        if descriptor is not None:
            os.close(descriptor)
        temp_path.unlink(missing_ok=True)


def write_orchestrator_readiness(
    readiness_file: Path,
    requests_dir: Path,
    results_dir: Path,
    monitor_id: str,
) -> None:
    """Write one fresh readiness heartbeat from an actually active request monitor."""

    atomic_write_json(
        readiness_file,
        {
            "protocol": READINESS_PROTOCOL,
            "ready": True,
            "monitor_id": monitor_id,
            "requests_dir": str(requests_dir.resolve()),
            "results_dir": str(results_dir.resolve()),
            "heartbeat_at": datetime.now(timezone.utc).isoformat(),
        },
    )


class CursorAgentClient:
    """Client for launching Cursor cloud-agent subagents via a parent monitor."""

    def __init__(
        self,
        requests_dir: Optional[Path] = None,
        results_dir: Optional[Path] = None,
    ):
        default_requests, default_results, _ = get_orchestration_paths()
        self.requests_dir = requests_dir or default_requests
        self.results_dir = results_dir or default_results
        _ensure_private_dir(self.requests_dir)
        _ensure_private_dir(self.results_dir)

    def launch_subagent(
        self,
        prompt: str,
        description: str,
        timeout_seconds: int = 300,
        poll_interval: float = 2.0,
    ) -> SubagentLaunchResult:
        """Publish a launch request and wait for the matching result."""

        request_id = f"req-{time.time_ns()}-{os.getpid()}"
        submitted_at = datetime.now(timezone.utc)
        expires_at = submitted_at + timedelta(seconds=timeout_seconds)
        request = SubagentLaunchRequest(
            request_id=request_id,
            prompt=prompt,
            description=description,
            timeout_seconds=timeout_seconds,
        )

        request_file = self.requests_dir / f"{request_id}.json"
        atomic_write_json(
            request_file,
            {
                "request_id": request.request_id,
                "prompt": request.prompt,
                "description": request.description,
                "timeout_seconds": request.timeout_seconds,
                "submitted_at": submitted_at.isoformat(),
                "expires_at": expires_at.isoformat(),
            },
        )

        result_file = self.results_dir / f"{request_id}.json"
        start_time = time.monotonic()

        while True:
            elapsed = time.monotonic() - start_time

            if elapsed > timeout_seconds:
                request_file.unlink(missing_ok=True)
                return SubagentLaunchResult(
                    request_id=request_id,
                    status="timeout",
                    error=(
                        "Orchestrator did not provide result within "
                        f"{timeout_seconds}s"
                    ),
                    duration_seconds=elapsed,
                )

            if result_file.exists():
                with open(result_file, "r", encoding="utf-8") as handle:
                    result_data = json.load(handle)

                request_file.unlink(missing_ok=True)

                if result_data.get("request_id") != request_id:
                    return SubagentLaunchResult(
                        request_id=request_id,
                        status="failed",
                        error="Orchestrator result request_id did not match request",
                        duration_seconds=elapsed,
                    )

                return SubagentLaunchResult(
                    request_id=request_id,
                    status=result_data.get("status", "failed"),
                    agent_id=result_data.get("agent_id"),
                    dashboard_url=result_data.get("dashboard_url"),
                    error=result_data.get("error"),
                    duration_seconds=result_data.get("duration_seconds"),
                )

            time.sleep(poll_interval)


def _unsupported(reason: str, details: Dict[str, Any]) -> Dict[str, Any]:
    return {"supported": False, "reason": reason, "details": details}


def detect_orchestration_support() -> Dict[str, Any]:
    """Require cloud-agent context plus a fresh active-monitor readiness heartbeat."""

    in_cloud_agent = os.environ.get("CURSOR_AGENT") == "1"
    agent_socket = os.environ.get("CURSOR_AGENT_SOCKET")
    requests_dir, results_dir, readiness_file = get_orchestration_paths()

    if not in_cloud_agent:
        return _unsupported(
            "Not running in Cursor cloud agent context",
            {
                "CURSOR_AGENT": os.environ.get("CURSOR_AGENT"),
                "required": "CURSOR_AGENT=1",
            },
        )

    if not agent_socket or not Path(agent_socket).exists():
        return _unsupported(
            "Agent socket unavailable",
            {
                "CURSOR_AGENT_SOCKET": agent_socket,
                "socket_exists": bool(agent_socket and Path(agent_socket).exists()),
            },
        )

    if not readiness_file.exists():
        return _unsupported(
            "Active orchestrator readiness signal unavailable",
            {"readiness_file": str(readiness_file)},
        )

    try:
        with open(readiness_file, "r", encoding="utf-8") as handle:
            readiness = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        return _unsupported(
            "Orchestrator readiness signal is unreadable",
            {"readiness_file": str(readiness_file), "error": str(exc)},
        )

    if (
        readiness.get("protocol") != READINESS_PROTOCOL
        or readiness.get("ready") is not True
        or not readiness.get("monitor_id")
    ):
        return _unsupported(
            "Orchestrator readiness signal is invalid",
            {"readiness_file": str(readiness_file), "readiness": readiness},
        )

    expected_requests = str(requests_dir.resolve())
    expected_results = str(results_dir.resolve())
    if (
        readiness.get("requests_dir") != expected_requests
        or readiness.get("results_dir") != expected_results
    ):
        return _unsupported(
            "Orchestrator readiness paths do not match dispatcher paths",
            {
                "readiness_file": str(readiness_file),
                "expected_requests_dir": expected_requests,
                "expected_results_dir": expected_results,
                "observed_requests_dir": readiness.get("requests_dir"),
                "observed_results_dir": readiness.get("results_dir"),
            },
        )

    try:
        heartbeat = datetime.fromisoformat(
            str(readiness["heartbeat_at"]).replace("Z", "+00:00")
        )
        if heartbeat.tzinfo is None:
            raise ValueError("heartbeat_at must include timezone")
        heartbeat = heartbeat.astimezone(timezone.utc)
    except (KeyError, TypeError, ValueError) as exc:
        return _unsupported(
            "Orchestrator readiness heartbeat is invalid",
            {"readiness_file": str(readiness_file), "error": str(exc)},
        )

    try:
        max_age = float(
            os.environ.get(
                "CURSOR_AGENT_ORCHESTRATOR_READY_MAX_AGE_SECONDS",
                str(DEFAULT_READINESS_MAX_AGE_SECONDS),
            )
        )
    except ValueError:
        max_age = DEFAULT_READINESS_MAX_AGE_SECONDS

    age_seconds = (datetime.now(timezone.utc) - heartbeat).total_seconds()
    if age_seconds < -5 or age_seconds > max_age:
        return _unsupported(
            "Orchestrator readiness heartbeat is stale",
            {
                "readiness_file": str(readiness_file),
                "heartbeat_age_seconds": age_seconds,
                "max_age_seconds": max_age,
            },
        )

    return {
        "supported": True,
        "reason": "Fresh readiness heartbeat from active parent-agent request monitor",
        "details": {
            "CURSOR_AGENT": "1",
            "CURSOR_AGENT_SOCKET": agent_socket,
            "socket_exists": True,
            "readiness_file": str(readiness_file),
            "monitor_id": readiness["monitor_id"],
            "heartbeat_age_seconds": age_seconds,
            "requests_dir": expected_requests,
            "results_dir": expected_results,
        },
    }
