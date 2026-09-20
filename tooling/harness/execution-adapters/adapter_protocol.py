"""Generic execution-adapter protocol for AgentSwitchboard v1."""

from __future__ import annotations

from typing import Any, Mapping, MutableMapping, Protocol, runtime_checkable


CapabilityReport = MutableMapping[str, Any]
ExecutionRequest = Mapping[str, Any]
ExecutionReceipt = MutableMapping[str, Any]


@runtime_checkable
class ExecutionAdapter(Protocol):
    """Provider-neutral adapter boundary: probe() then execute(request)."""

    @property
    def adapter_kind(self) -> str:
        """Stable adapter kind registered with the shared spine."""

    @property
    def native_harness_name(self) -> str:
        """Human-readable native harness name for capability reports."""

    def probe(self) -> CapabilityReport:
        """Read-only readiness probe. Must never start interactive auth."""

    def execute(self, request: ExecutionRequest) -> ExecutionReceipt:
        """Execute one accepted request and return exactly one terminal receipt."""
