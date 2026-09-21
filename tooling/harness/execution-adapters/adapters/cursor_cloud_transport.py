"""Adapter-private transport for Cursor CloudAgent Task dispatch."""

from __future__ import annotations

import json
import os
import re
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping, MutableMapping, Optional, Tuple


READY_PROTOCOL = "agentswitchboard.cursor-task-bridge-ready/v1"
REQUEST_PROTOCOL = "agentswitchboard.cursor-task-request/v1"
RESULT_PROTOCOL = "agentswitchboard.cursor-task-result/v1"
SESSION_ENV = "ASB_CURSOR_TASK_SESSION_DIR"
DEFAULT_READY_MAX_AGE_SECONDS = 15.0
_REQUEST_ID_RE = re.compile(r"^req_[A-Za-z0-9._-]{8,128}$")


class CursorTransportError(RuntimeError):
    """Fail-closed transport error."""


@dataclass(frozen=True)
class CursorTransportPaths:
    session_root: Path
    requests_dir: Path
    results_dir: Path
    readiness_file: Path


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def resolve_session_paths(
    environment: Optional[Mapping[str, str]] = None,
) -> Optional[CursorTransportPaths]:
    """Resolve the explicit private bridge session; never guess a shared /tmp root."""

    env = environment if environment is not None else os.environ
    raw = env.get(SESSION_ENV)
    if not raw:
        return None

    root = Path(raw)
    if not root.is_absolute():
        raise CursorTransportError(f"{SESSION_ENV} must be an absolute path")

    return CursorTransportPaths(
        session_root=root,
        requests_dir=root / "requests",
        results_dir=root / "results",
        readiness_file=root / "bridge-ready.json",
    )


def _ensure_private_directory(path: Path) -> None:
    if path.exists() and path.is_symlink():
        raise CursorTransportError(f"refusing symlinked transport directory: {path}")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        # Windows and some mounted filesystems do not expose POSIX mode semantics.
        pass


def ensure_private_session(paths: CursorTransportPaths) -> None:
    _ensure_private_directory(paths.session_root)
    _ensure_private_directory(paths.requests_dir)
    _ensure_private_directory(paths.results_dir)


def atomic_write_json(path: Path, payload: Mapping[str, Any]) -> None:
    """Publish one private JSON document atomically within its destination directory."""

    _ensure_private_directory(path.parent)
    temp_path = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    descriptor: Optional[int] = None
    try:
        descriptor = os.open(
            temp_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = None
            json.dump(payload, handle, indent=2, sort_keys=True)
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


def load_json(path: Path) -> MutableMapping[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise CursorTransportError(f"invalid transport document {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise CursorTransportError(f"transport document must be an object: {path}")
    return payload


def write_bridge_readiness(
    paths: CursorTransportPaths,
    monitor_id: str,
    heartbeat_at: Optional[datetime] = None,
) -> None:
    """Producer helper for the future machine-closed Task bridge and synthetic tests."""

    ensure_private_session(paths)
    atomic_write_json(
        paths.readiness_file,
        {
            "protocol": READY_PROTOCOL,
            "ready": True,
            "monitorId": monitor_id,
            "sessionRoot": str(paths.session_root.resolve()),
            "requestsDir": str(paths.requests_dir.resolve()),
            "resultsDir": str(paths.results_dir.resolve()),
            "heartbeatAt": _iso(heartbeat_at or _utc_now()),
        },
    )


def read_bridge_readiness(
    paths: CursorTransportPaths,
    max_age_seconds: float = DEFAULT_READY_MAX_AGE_SECONDS,
) -> Tuple[bool, str]:
    """Validate a fresh readiness heartbeat bound to this exact private session."""

    if not paths.readiness_file.exists():
        return False, "active Task bridge readiness document is missing"

    try:
        payload = load_json(paths.readiness_file)
        if payload.get("protocol") != READY_PROTOCOL:
            return False, "Task bridge readiness protocol mismatch"
        if payload.get("ready") is not True or not payload.get("monitorId"):
            return False, "Task bridge readiness document is not active"
        expected = {
            "sessionRoot": str(paths.session_root.resolve()),
            "requestsDir": str(paths.requests_dir.resolve()),
            "resultsDir": str(paths.results_dir.resolve()),
        }
        for key, value in expected.items():
            if payload.get(key) != value:
                return False, f"Task bridge readiness {key} does not match session"

        heartbeat = datetime.fromisoformat(
            str(payload["heartbeatAt"]).replace("Z", "+00:00")
        )
        if heartbeat.tzinfo is None:
            return False, "Task bridge heartbeat lacks timezone"
        age = (_utc_now() - heartbeat.astimezone(timezone.utc)).total_seconds()
        if age < -5 or age > max_age_seconds:
            return False, "Task bridge readiness heartbeat is stale"
    except (CursorTransportError, KeyError, TypeError, ValueError) as exc:
        return False, f"Task bridge readiness is invalid: {exc}"

    return True, "active Task bridge readiness heartbeat is fresh"


def _validate_request_id(request_id: str) -> None:
    if not _REQUEST_ID_RE.fullmatch(request_id):
        raise CursorTransportError(f"invalid execution requestId: {request_id!r}")


class CursorTaskTransport:
    """Private request/result transport behind the common execution-adapter contract."""

    def __init__(self, paths: CursorTransportPaths):
        self.paths = paths
        ensure_private_session(paths)

    def publish_request(
        self,
        execution_request: Mapping[str, Any],
        timeout_seconds: int,
    ) -> Path:
        request_id = str(execution_request.get("requestId") or "")
        _validate_request_id(request_id)
        request_path = self.paths.requests_dir / f"{request_id}.json"
        result_path = self.paths.results_dir / f"{request_id}.json"
        claim_path = self.paths.requests_dir / f".{request_id}.claim"

        claim_descriptor: Optional[int] = None
        try:
            claim_descriptor = os.open(
                claim_path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            os.close(claim_descriptor)
            claim_descriptor = None
        except FileExistsError as exc:
            raise CursorTransportError(
                f"requestId is already claimed: {request_id}"
            ) from exc
        finally:
            if claim_descriptor is not None:
                os.close(claim_descriptor)

        try:
            if request_path.exists() or result_path.exists():
                raise CursorTransportError(
                    f"requestId already has transport state: {request_id}"
                )

            submitted = _utc_now()
            expires = submitted + timedelta(seconds=timeout_seconds)
            atomic_write_json(
                request_path,
                {
                    "protocol": REQUEST_PROTOCOL,
                    "requestId": request_id,
                    "submittedAt": _iso(submitted),
                    "expiresAt": _iso(expires),
                    "executionRequest": dict(execution_request),
                },
            )
        except Exception:
            claim_path.unlink(missing_ok=True)
            raise

        return request_path

    def wait_for_result(
        self,
        request_id: str,
        timeout_seconds: float,
        poll_interval: float = 0.05,
    ) -> MutableMapping[str, Any]:
        _validate_request_id(request_id)
        request_path = self.paths.requests_dir / f"{request_id}.json"
        result_path = self.paths.results_dir / f"{request_id}.json"
        claim_path = self.paths.requests_dir / f".{request_id}.claim"
        deadline = time.monotonic() + timeout_seconds

        def cleanup() -> None:
            request_path.unlink(missing_ok=True)
            result_path.unlink(missing_ok=True)
            claim_path.unlink(missing_ok=True)

        while time.monotonic() <= deadline:
            if result_path.exists():
                try:
                    payload = load_json(result_path)
                    if payload.get("protocol") != RESULT_PROTOCOL:
                        raise CursorTransportError(
                            "Task bridge result protocol mismatch"
                        )
                    if payload.get("requestId") != request_id:
                        raise CursorTransportError(
                            "Task bridge result requestId does not match request"
                        )
                except CursorTransportError:
                    cleanup()
                    raise

                cleanup()
                return payload
            time.sleep(poll_interval)

        cleanup()
        return {
            "protocol": RESULT_PROTOCOL,
            "requestId": request_id,
            "status": "TIMED_OUT",
            "error": f"Task bridge did not return a terminal result within {timeout_seconds}s",
            "completedAt": _iso(_utc_now()),
        }

    def execute_request(
        self,
        execution_request: Mapping[str, Any],
        timeout_seconds: int,
        poll_interval: float = 0.05,
    ) -> MutableMapping[str, Any]:
        request_id = str(execution_request.get("requestId") or "")
        self.publish_request(execution_request, timeout_seconds)
        return self.wait_for_result(
            request_id,
            timeout_seconds=timeout_seconds,
            poll_interval=poll_interval,
        )
