"""Cursor CloudAgent execution adapter v1."""

from __future__ import annotations

import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, MutableMapping, Optional

from .cursor_cloud_transport import (
    CursorTaskTransport,
    CursorTransportError,
    read_bridge_readiness,
    resolve_session_paths,
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class CursorCloudAgentAdapter:
    """Common-contract adapter over the adapter-private Cursor Task transport."""

    adapter_kind = "cursor-cloud-agent"
    native_harness_name = "Cursor CloudAgent Task execution"

    def __init__(self, environment: Optional[Mapping[str, str]] = None):
        self._environment = environment if environment is not None else os.environ

    def probe(self) -> MutableMapping[str, Any]:
        observed = _utc_now()
        host_ready = self._environment.get("CURSOR_AGENT") == "1"
        socket_value = self._environment.get("CURSOR_AGENT_SOCKET")
        socket_ready = bool(socket_value and Path(socket_value).exists())

        paths = None
        session_error = None
        try:
            paths = resolve_session_paths(self._environment)
        except CursorTransportError as exc:
            session_error = str(exc)

        dispatch_ready = False
        dispatch_reason = "Task bridge session is not configured"
        if paths is not None:
            dispatch_ready, dispatch_reason = read_bridge_readiness(paths)
        elif session_error:
            dispatch_reason = session_error

        if not host_ready:
            status = "BLOCKED"
            blocker = {
                "code": "BLOCKED_HOST",
                "message": "Cursor CloudAgent host context is unavailable (CURSOR_AGENT != 1).",
                "retryable": True,
            }
        elif not socket_ready:
            status = "BLOCKED"
            blocker = {
                "code": "BLOCKED_API",
                "message": "Cursor agent transport socket is unavailable.",
                "retryable": True,
            }
        elif not dispatch_ready:
            status = "BLOCKED"
            blocker = {
                "code": "BLOCKED_API",
                "message": (
                    "Cursor Task dispatch bridge is not READY: "
                    + dispatch_reason
                ),
                "retryable": True,
            }
        else:
            status = "READY"
            blocker = None

        return {
            "schema": "agentswitchboard.execution-capability-report/v1",
            "probeId": f"probe_cursor_{uuid.uuid4().hex}",
            "adapterKind": self.adapter_kind,
            "status": status,
            "observedAt": _iso(observed),
            "nativeHarness": {
                "name": self.native_harness_name,
                "version": None,
            },
            "readiness": {
                "host": "READY" if host_ready else "BLOCKED",
                "binary": "NOT_APPLICABLE",
                "auth": "NOT_APPLICABLE",
                "transport": "READY" if socket_ready else "BLOCKED",
                "dispatch": "READY" if dispatch_ready else "BLOCKED",
            },
            "capabilities": {
                "mutation": True,
                "structuredOutput": True,
                "executionIdentity": True,
                "remoteExecution": True,
                "timeoutControl": True,
            },
            "blocker": blocker,
            "proofCeiling": "CAPABILITY_PROBE_ONLY",
        }

    def execute(self, request: Mapping[str, Any]) -> MutableMapping[str, Any]:
        started_wall = _utc_now()
        started_mono = time.monotonic()

        if (
            request.get("adapterKind") != self.adapter_kind
            or not isinstance(request.get("input"), Mapping)
            or request["input"].get("kind") != self.adapter_kind
        ):
            return self._terminal_receipt(
                request=request,
                status="BLOCKED",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code="BLOCKED_INPUT",
                blocker_message="Execution request is not a cursor-cloud-agent request.",
                blocker_stage="prepare",
                retryable=False,
            )

        capability = self.probe()
        if capability["status"] != "READY":
            blocker = capability["blocker"] or {}
            return self._terminal_receipt(
                request=request,
                status="BLOCKED",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code=str(blocker.get("code") or "BLOCKED_API"),
                blocker_message=str(
                    blocker.get("message")
                    or "Cursor CloudAgent adapter is not READY."
                ),
                blocker_stage="probe",
                retryable=bool(blocker.get("retryable", True)),
            )

        paths = resolve_session_paths(self._environment)
        if paths is None:
            return self._terminal_receipt(
                request=request,
                status="BLOCKED",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code="BLOCKED_API",
                blocker_message="Cursor Task bridge session is not configured.",
                blocker_stage="prepare",
                retryable=True,
            )

        try:
            raw = CursorTaskTransport(paths).execute_request(
                execution_request=request,
                timeout_seconds=int(request["timeoutSeconds"]),
            )
        except (CursorTransportError, OSError, ValueError) as exc:
            return self._terminal_receipt(
                request=request,
                status="FAILED",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code="EXECUTION_ERROR",
                blocker_message=f"Cursor Task transport failed: {exc}",
                blocker_stage="observe",
                retryable=True,
            )

        provider_status = str(raw.get("status") or "").upper()
        agent_id = raw.get("cloudAgentBcId")
        dashboard_url = raw.get("dashboardUrl")
        execution_identity = None
        if isinstance(agent_id, str) and agent_id:
            execution_identity = {
                "kind": "CURSOR_CLOUD_AGENT",
                "value": agent_id,
            }

        if provider_status == "TIMED_OUT":
            return self._terminal_receipt(
                request=request,
                status="TIMED_OUT",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code="TIMEOUT",
                blocker_message=str(
                    raw.get("error")
                    or "Cursor Task bridge timed out before terminal result."
                ),
                blocker_stage="observe",
                retryable=True,
                execution_identity=execution_identity,
            )

        if provider_status == "FAILED":
            return self._terminal_receipt(
                request=request,
                status="FAILED",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code="EXECUTION_ERROR",
                blocker_message=str(
                    raw.get("error")
                    or "Cursor CloudAgent reported failed terminal state."
                ),
                blocker_stage="observe",
                retryable=True,
                execution_identity=execution_identity,
            )

        if provider_status != "COMPLETED" or execution_identity is None:
            return self._terminal_receipt(
                request=request,
                status="FAILED",
                started_wall=started_wall,
                started_mono=started_mono,
                blocker_code="EXECUTION_ERROR",
                blocker_message=(
                    "Cursor Task result did not provide COMPLETED plus "
                    "a stable cloudAgentBcId."
                ),
                blocker_stage="observe",
                retryable=False,
                execution_identity=execution_identity,
            )

        safe_dashboard_url = (
            dashboard_url
            if isinstance(dashboard_url, str)
            and 0 < len(dashboard_url) <= 4096
            else None
        )
        artifacts = []
        if safe_dashboard_url is not None:
            artifacts.append(
                {
                    "kind": "URL",
                    "locator": safe_dashboard_url,
                    "sha256": None,
                }
            )

        completed_wall = _utc_now()
        return {
            "schema": "agentswitchboard.execution-receipt/v1",
            "requestId": request.get("requestId"),
            "correlationId": request.get("correlationId"),
            "adapterKind": self.adapter_kind,
            "status": "EXECUTED",
            "startedAt": _iso(started_wall),
            "completedAt": _iso(completed_wall),
            "durationMs": max(
                0.0,
                (completed_wall - started_wall).total_seconds() * 1000.0,
            ),
            "executionIdentity": execution_identity,
            "exitCode": None,
            "artifacts": artifacts,
            "output": {
                "stdoutExcerpt": "",
                "stderrExcerpt": "",
                "structuredResult": {
                    "providerStatus": "COMPLETED",
                    "dashboardUrl": (
                        safe_dashboard_url
                    ),
                },
            },
            "blocker": None,
            "proof": {
                "level": "CONTRACT_STATIC",
                "independentValidationRequired": True,
                "validationArtifact": None,
                "notes": [
                    "Adapter-observed terminal result is not EAT-308 proof.",
                    "CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED requires an independent deterministic artifact.",
                ],
            },
        }

    def _terminal_receipt(
        self,
        *,
        request: Mapping[str, Any],
        status: str,
        started_wall: datetime,
        started_mono: float,
        blocker_code: str,
        blocker_message: str,
        blocker_stage: str,
        retryable: bool,
        execution_identity: Optional[Mapping[str, str]] = None,
    ) -> MutableMapping[str, Any]:
        completed = _utc_now()
        return {
            "schema": "agentswitchboard.execution-receipt/v1",
            "requestId": request.get("requestId"),
            "correlationId": request.get("correlationId"),
            "adapterKind": self.adapter_kind,
            "status": status,
            "startedAt": _iso(started_wall),
            "completedAt": _iso(completed),
            "durationMs": max(
                0.0,
                (completed - started_wall).total_seconds() * 1000.0,
            ),
            "executionIdentity": (
                dict(execution_identity)
                if execution_identity is not None
                else None
            ),
            "exitCode": None,
            "artifacts": [],
            "output": {
                "stdoutExcerpt": "",
                "stderrExcerpt": "",
                "structuredResult": None,
            },
            "blocker": {
                "code": blocker_code,
                "message": blocker_message[:4000],
                "stage": blocker_stage,
                "retryable": retryable,
            },
            "proof": {
                "level": "CAPABILITY_PROBE_ONLY",
                "independentValidationRequired": True,
                "validationArtifact": None,
                "notes": [
                    "Cursor adapter failed closed before runtime proof promotion."
                ],
            },
        }
