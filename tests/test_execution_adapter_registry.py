"""Focused tests for EAT-005 generic adapter registry and runner."""

from __future__ import annotations

import copy
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parents[1]
ADAPTERS_DIR = ROOT / "tooling" / "harness" / "execution-adapters"
FIXTURE_DIR = ADAPTERS_DIR / "fixtures"
SCHEMA_DIR = ADAPTERS_DIR / "schemas"


def _load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# Load as a package so relative imports in spine modules resolve.
_pkg = ModuleType("execution_adapters_pkg")
_pkg.__path__ = [str(ADAPTERS_DIR)]  # type: ignore[attr-defined]
sys.modules["execution_adapters_pkg"] = _pkg

adapter_protocol = _load_module(
    "execution_adapters_pkg.adapter_protocol",
    ADAPTERS_DIR / "adapter_protocol.py",
)
registry_mod = _load_module(
    "execution_adapters_pkg.registry",
    ADAPTERS_DIR / "registry.py",
)
runner_mod = _load_module(
    "execution_adapters_pkg.runner",
    ADAPTERS_DIR / "runner.py",
)

AdapterRegistry = registry_mod.AdapterRegistry
DuplicateAdapterError = registry_mod.DuplicateAdapterError
UnknownAdapterError = registry_mod.UnknownAdapterError
ExecutionAdapterRunner = runner_mod.ExecutionAdapterRunner

# Reuse the contract validator's schema checks.
contract_tests = _load_module(
    "test_execution_adapter_contract_for_registry",
    ROOT / "tests" / "test_execution_adapter_contract.py",
)


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class StubReadyAdapter:
    adapter_kind = "local-argv"
    native_harness_name = "stub-local-argv"

    def __init__(self) -> None:
        self.execute_calls = 0

    def probe(self):
        return {
            "schema": "agentswitchboard.execution-capability-report/v1",
            "probeId": "probe_stub_ready_001",
            "adapterKind": self.adapter_kind,
            "status": "READY",
            "observedAt": _iso_now(),
            "nativeHarness": {"name": self.native_harness_name, "version": "stub"},
            "readiness": {
                "host": "READY",
                "binary": "READY",
                "auth": "NOT_APPLICABLE",
                "transport": "NOT_APPLICABLE",
                "dispatch": "READY",
            },
            "capabilities": {
                "mutation": False,
                "structuredOutput": False,
                "executionIdentity": True,
                "remoteExecution": False,
                "timeoutControl": True,
            },
            "blocker": None,
            "proofCeiling": "CAPABILITY_PROBE_ONLY",
        }

    def execute(self, request):
        self.execute_calls += 1
        started = _iso_now()
        return {
            "schema": "agentswitchboard.execution-receipt/v1",
            "requestId": request["requestId"],
            "correlationId": request["correlationId"],
            "adapterKind": self.adapter_kind,
            "status": "EXECUTED",
            "startedAt": started,
            "completedAt": started,
            "durationMs": 1,
            "executionIdentity": {"kind": "PROCESS", "value": "stub-pid-1"},
            "exitCode": 0,
            "artifacts": [],
            "output": {
                "stdoutExcerpt": "STUB_OK",
                "stderrExcerpt": "",
                "structuredResult": None,
            },
            "blocker": None,
            "proof": {
                "level": "CONTRACT_STATIC",
                "independentValidationRequired": True,
                "validationArtifact": "stub-only",
                "notes": ["Stub adapter; not live runtime proof."],
            },
        }


class StubBlockedAdapter:
    adapter_kind = "claude-code"
    native_harness_name = "Claude Code CLI"

    def probe(self):
        return load_json(FIXTURE_DIR / "capability-report.blocked-auth.valid.json")

    def execute(self, request):  # pragma: no cover - must not be called
        raise AssertionError("blocked adapter must not execute")


def test_registry_rejects_duplicate_kinds():
    registry = AdapterRegistry()
    registry.register(StubReadyAdapter())
    try:
        registry.register(StubReadyAdapter())
        raise AssertionError("expected DuplicateAdapterError")
    except DuplicateAdapterError:
        pass


def test_registry_resolve_unknown_raises():
    registry = AdapterRegistry()
    try:
        registry.resolve("does-not-exist")
        raise AssertionError("expected UnknownAdapterError")
    except UnknownAdapterError:
        pass


def test_runner_unknown_adapter_fail_closed_receipt():
    registry = AdapterRegistry()
    runner = ExecutionAdapterRunner(registry)
    request = load_json(FIXTURE_DIR / "execution-request.local-argv.valid.json")
    request = copy.deepcopy(request)
    request["adapterKind"] = "opencode-missing"
    request["input"] = {
        "kind": "local-argv",
        "argv": ["python", "-c", "print('x')"],
        "environment": {},
        "inheritEnvironment": True,
    }
    # Keep request schema-shaped for kind string; adapterKind drives resolve.
    receipt = runner.execute(request)
    assert receipt["status"] == "BLOCKED"
    assert receipt["blocker"]["code"] == "BLOCKED_UNSUPPORTED"
    assert receipt["blocker"]["stage"] == "prepare"
    assert receipt["executionIdentity"] is None
    assert receipt["proof"]["level"] == "CAPABILITY_PROBE_ONLY"
    contract_tests.validate_json_schema(
        receipt,
        load_json(SCHEMA_DIR / "execution-receipt.v1.schema.json"),
    )


def test_runner_unready_adapter_blocks_without_execute():
    registry = AdapterRegistry()
    registry.register(StubBlockedAdapter())
    runner = ExecutionAdapterRunner(registry)
    request = load_json(FIXTURE_DIR / "execution-request.claude-code.valid.json")
    receipt = runner.execute(request)
    assert receipt["status"] == "BLOCKED"
    assert receipt["blocker"]["code"] == "BLOCKED_AUTH"
    assert receipt["blocker"]["stage"] == "probe"
    contract_tests.validate_json_schema(
        receipt,
        load_json(SCHEMA_DIR / "execution-receipt.v1.schema.json"),
    )


def test_runner_ready_adapter_executes_via_registry():
    ready = StubReadyAdapter()
    registry = AdapterRegistry()
    registry.register(ready)
    runner = ExecutionAdapterRunner(registry)
    request = load_json(FIXTURE_DIR / "execution-request.local-argv.valid.json")
    receipt = runner.execute(request)
    assert ready.execute_calls == 1
    assert receipt["status"] == "EXECUTED"
    assert receipt["exitCode"] == 0
    assert receipt["output"]["stdoutExcerpt"] == "STUB_OK"
    contract_tests.validate_json_schema(
        receipt,
        load_json(SCHEMA_DIR / "execution-receipt.v1.schema.json"),
    )


def test_runner_does_not_branch_on_native_harness_names():
    """Resolution is by adapterKind only; native harness is adapter-private."""
    registry = AdapterRegistry()
    registry.register(StubReadyAdapter())
    runner = ExecutionAdapterRunner(registry)
    assert "local-argv" in registry
    assert runner.registry.resolve("local-argv").native_harness_name == "stub-local-argv"


def main() -> None:
    test_registry_rejects_duplicate_kinds()
    test_registry_resolve_unknown_raises()
    test_runner_unknown_adapter_fail_closed_receipt()
    test_runner_unready_adapter_blocks_without_execute()
    test_runner_ready_adapter_executes_via_registry()
    test_runner_does_not_branch_on_native_harness_names()
    print("PASS: execution adapter registry/runner v1")


if __name__ == "__main__":
    main()
