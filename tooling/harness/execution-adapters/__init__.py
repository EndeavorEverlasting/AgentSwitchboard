"""AgentSwitchboard execution-adapter v1 shared spine."""

from .adapter_protocol import ExecutionAdapter
from .registry import AdapterRegistry, DuplicateAdapterError, UnknownAdapterError
from .runner import ExecutionAdapterRunner

__all__ = [
    "AdapterRegistry",
    "DuplicateAdapterError",
    "ExecutionAdapter",
    "ExecutionAdapterRunner",
    "UnknownAdapterError",
]
