"""Deterministic execution-adapter registry."""

from __future__ import annotations

from typing import Dict, Iterable, List

from .adapter_protocol import ExecutionAdapter


class DuplicateAdapterError(ValueError):
    """Raised when registering an adapter kind that already exists."""


class UnknownAdapterError(KeyError):
    """Raised when resolving an adapter kind that is not registered."""


class AdapterRegistry:
    """Maps adapterKind -> ExecutionAdapter. Duplicate kinds fail closed."""

    def __init__(self) -> None:
        self._adapters: Dict[str, ExecutionAdapter] = {}

    def register(self, adapter: ExecutionAdapter) -> None:
        kind = getattr(adapter, "adapter_kind", None)
        if not isinstance(kind, str) or not kind:
            raise ValueError("adapter.adapter_kind must be a non-empty string")
        if kind in self._adapters:
            raise DuplicateAdapterError(
                f"adapter kind already registered: {kind}"
            )
        self._adapters[kind] = adapter

    def resolve(self, adapter_kind: str) -> ExecutionAdapter:
        try:
            return self._adapters[adapter_kind]
        except KeyError as exc:
            raise UnknownAdapterError(adapter_kind) from exc

    def registered_kinds(self) -> List[str]:
        return sorted(self._adapters.keys())

    def __contains__(self, adapter_kind: object) -> bool:
        return isinstance(adapter_kind, str) and adapter_kind in self._adapters

    def __len__(self) -> int:
        return len(self._adapters)

    def values(self) -> Iterable[ExecutionAdapter]:
        return self._adapters.values()
