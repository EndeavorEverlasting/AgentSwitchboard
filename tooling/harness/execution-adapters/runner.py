"""Generic execution-adapter runner: resolve -> probe -> execute or BLOCKED."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Mapping, MutableMapping, Optional

from .adapter_protocol import ExecutionAdapter, ExecutionReceipt, ExecutionRequest
from .registry import AdapterRegistry, UnknownAdapterError


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(ts: datetime) -> str:
    return ts.isoformat().replace("+00:00", "Z")


def build_blocked_receipt(
    *,
    request: Mapping[str, Any],
    adapter_kind: str,
    blocker_code: str,
    message: str,
    stage: str,
    retryable: bool,
    started_at: Optional[datetime] = None,
    completed_at: Optional[datetime] = None,
) -> MutableMapping[str, Any]:
    """Normalized fail-closed receipt for unknown/unready adapters."""
    start = started_at or _utc_now()
    end = completed_at or start
    duration_ms = max(0.0, (end - start).total_seconds() * 1000.0)
    return {
        "schema": "agentswitchboard.execution-receipt/v1",
        "requestId": request.get("requestId"),
        "correlationId": request.get("correlationId"),
        "adapterKind": adapter_kind,
        "status": "BLOCKED",
        "startedAt": _iso(start),
        "completedAt": _iso(end),
        "durationMs": duration_ms,
        "executionIdentity": None,
        "exitCode": None,
        "artifacts": [],
        "output": {
            "stdoutExcerpt": "",
            "stderrExcerpt": "",
            "structuredResult": None,
        },
        "blocker": {
            "code": blocker_code,
            "message": message,
            "stage": stage,
            "retryable": retryable,
        },
        "proof": {
            "level": "CAPABILITY_PROBE_ONLY",
            "independentValidationRequired": True,
            "validationArtifact": "generic-runner-fail-closed",
            "notes": [
                "Runner blocked before native execute; no runtime proof claimed."
            ],
        },
    }


class ExecutionAdapterRunner:
    """Resolve adapters through the registry; never branch on native harness."""

    def __init__(self, registry: AdapterRegistry) -> None:
        self.registry = registry

    def probe(self, adapter_kind: str) -> MutableMapping[str, Any]:
        adapter = self.registry.resolve(adapter_kind)
        return dict(adapter.probe())

    def execute(self, request: ExecutionRequest) -> ExecutionReceipt:
        if not isinstance(request, Mapping):
            raise TypeError("request must be a mapping")
        adapter_kind = request.get("adapterKind")
        if not isinstance(adapter_kind, str) or not adapter_kind:
            raise ValueError("request.adapterKind must be a non-empty string")

        started = _utc_now()
        try:
            adapter: ExecutionAdapter = self.registry.resolve(adapter_kind)
        except UnknownAdapterError:
            return build_blocked_receipt(
                request=request,
                adapter_kind=adapter_kind,
                blocker_code="BLOCKED_UNSUPPORTED",
                message=f"No adapter registered for kind: {adapter_kind}",
                stage="prepare",
                retryable=False,
                started_at=started,
                completed_at=_utc_now(),
            )

        capability = adapter.probe()
        status = capability.get("status")
        if status != "READY":
            blocker = capability.get("blocker") or {}
            code = blocker.get("code") or (
                "BLOCKED_UNSUPPORTED" if status == "UNSUPPORTED" else "BLOCKED_HOST"
            )
            message = blocker.get("message") or (
                f"Adapter {adapter_kind} is not READY (status={status!r})"
            )
            retryable = bool(blocker.get("retryable", status == "BLOCKED"))
            return build_blocked_receipt(
                request=request,
                adapter_kind=adapter_kind,
                blocker_code=str(code),
                message=str(message),
                stage="probe",
                retryable=retryable,
                started_at=started,
                completed_at=_utc_now(),
            )

        receipt = adapter.execute(request)
        if not isinstance(receipt, MutableMapping):
            raise TypeError("adapter.execute must return a mutable mapping receipt")
        return receipt
