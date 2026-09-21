"""Focused EAT-302..304 Cursor CloudAgent adapter tests."""

from __future__ import annotations

import copy
import importlib.util
import json
import os
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parents[1]
ADAPTERS_ROOT = ROOT / "tooling" / "harness" / "execution-adapters"
PROVIDER_DIR = ADAPTERS_ROOT / "adapters"
FIXTURE_DIR = ADAPTERS_ROOT / "fixtures"
SCHEMA_DIR = ADAPTERS_ROOT / "schemas"
REUSE_MAP = PROVIDER_DIR / "cursor_cloud_agent_reuse.v1.json"


def _load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_pkg = ModuleType("execution_adapters_pkg")
_pkg.__path__ = [str(ADAPTERS_ROOT)]  # type: ignore[attr-defined]
sys.modules["execution_adapters_pkg"] = _pkg

_provider_pkg = ModuleType("execution_adapters_pkg.adapters")
_provider_pkg.__path__ = [str(PROVIDER_DIR)]  # type: ignore[attr-defined]
sys.modules["execution_adapters_pkg.adapters"] = _provider_pkg

adapter_protocol = _load_module(
    "execution_adapters_pkg.adapter_protocol",
    ADAPTERS_ROOT / "adapter_protocol.py",
)
registry_mod = _load_module(
    "execution_adapters_pkg.registry",
    ADAPTERS_ROOT / "registry.py",
)
runner_mod = _load_module(
    "execution_adapters_pkg.runner",
    ADAPTERS_ROOT / "runner.py",
)
transport_mod = _load_module(
    "execution_adapters_pkg.adapters.cursor_cloud_transport",
    PROVIDER_DIR / "cursor_cloud_transport.py",
)
adapter_mod = _load_module(
    "execution_adapters_pkg.adapters.cursor_cloud_agent",
    PROVIDER_DIR / "cursor_cloud_agent.py",
)
contract_tests = _load_module(
    "test_execution_adapter_contract_for_cursor",
    ROOT / "tests" / "test_execution_adapter_contract.py",
)

AdapterRegistry = registry_mod.AdapterRegistry
ExecutionAdapterRunner = runner_mod.ExecutionAdapterRunner
CursorCloudAgentAdapter = adapter_mod.CursorCloudAgentAdapter


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _cursor_request():
    return copy.deepcopy(
        load_json(FIXTURE_DIR / "execution-request.cursor-cloud-agent.valid.json")
    )


def _env(socket_path: Path, session_root: Path | None = None):
    values = {
        "CURSOR_AGENT": "1",
        "CURSOR_AGENT_SOCKET": str(socket_path),
    }
    if session_root is not None:
        values[transport_mod.SESSION_ENV] = str(session_root)
    return values


def _validate_capability(report):
    contract_tests.validate_json_schema(
        report,
        load_json(SCHEMA_DIR / "capability-report.v1.schema.json"),
    )
    contract_tests.validate_capability_semantics(report)


def _validate_receipt(receipt, request=None):
    contract_tests.validate_json_schema(
        receipt,
        load_json(SCHEMA_DIR / "execution-receipt.v1.schema.json"),
    )
    contract_tests.validate_receipt_semantics(receipt, request)


def test_reuse_map_preserves_common_ownership_and_pr332_lineage():
    data = load_json(REUSE_MAP)
    assert data["source"]["pullRequest"] == 332
    assert data["source"]["mergeSha"].startswith("bcf32b8")
    assert data["commonOwners"]["runner"].endswith("runner.py")
    dispositions = {item["disposition"] for item in data["dispositions"]}
    assert "REIMPLEMENT_PRIVATE_TRANSPORT" in dispositions
    assert "SUPERSEDE_WITH_EAT_305_MACHINE_BRIDGE" in dispositions


def test_probe_wrong_host_blocks_host_dimension():
    adapter = CursorCloudAgentAdapter(environment={})
    report = adapter.probe()
    assert report["status"] == "BLOCKED"
    assert report["readiness"]["host"] == "BLOCKED"
    assert report["readiness"]["dispatch"] == "BLOCKED"
    assert report["blocker"]["code"] == "BLOCKED_HOST"
    _validate_capability(report)


def test_probe_socket_presence_does_not_imply_dispatch_ready():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-probe-") as root:
        socket_path = Path(root) / "agent.sock"
        socket_path.touch()
        adapter = CursorCloudAgentAdapter(environment=_env(socket_path))
        report = adapter.probe()
        assert report["status"] == "BLOCKED"
        assert report["readiness"]["host"] == "READY"
        assert report["readiness"]["transport"] == "READY"
        assert report["readiness"]["dispatch"] == "BLOCKED"
        assert report["blocker"]["code"] == "BLOCKED_API"
        _validate_capability(report)


def test_fresh_private_bridge_readiness_is_ready():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-ready-") as root:
        root_path = Path(root)
        socket_path = root_path / "agent.sock"
        socket_path.touch()
        session = root_path / "session"
        environment = _env(socket_path, session)
        paths = transport_mod.resolve_session_paths(environment)
        assert paths is not None
        transport_mod.write_bridge_readiness(paths, "synthetic-monitor")
        report = CursorCloudAgentAdapter(environment=environment).probe()
        assert report["status"] == "READY"
        assert report["readiness"]["transport"] == "READY"
        assert report["readiness"]["dispatch"] == "READY"
        assert report["blocker"] is None
        _validate_capability(report)


def test_stale_bridge_readiness_fails_closed():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-stale-") as root:
        root_path = Path(root)
        socket_path = root_path / "agent.sock"
        socket_path.touch()
        session = root_path / "session"
        environment = _env(socket_path, session)
        paths = transport_mod.resolve_session_paths(environment)
        assert paths is not None
        transport_mod.write_bridge_readiness(
            paths,
            "synthetic-monitor",
            datetime.now(timezone.utc) - timedelta(seconds=60),
        )
        report = CursorCloudAgentAdapter(environment=environment).probe()
        assert report["status"] == "BLOCKED"
        assert report["readiness"]["transport"] == "READY"
        assert report["readiness"]["dispatch"] == "BLOCKED"
        assert report["blocker"]["code"] == "BLOCKED_API"
        _validate_capability(report)


def test_relative_session_path_fails_closed():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-relative-") as root:
        socket_path = Path(root) / "agent.sock"
        socket_path.touch()
        environment = _env(socket_path)
        environment[transport_mod.SESSION_ENV] = "relative/session"
        report = CursorCloudAgentAdapter(environment=environment).probe()
        assert report["status"] == "BLOCKED"
        assert report["readiness"]["transport"] == "READY"
        assert report["readiness"]["dispatch"] == "BLOCKED"
        assert report["blocker"]["code"] == "BLOCKED_API"
        _validate_capability(report)


def test_transport_timeout_cancels_pending_request():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-timeout-") as root:
        environment = {
            transport_mod.SESSION_ENV: str(Path(root) / "session")
        }
        paths = transport_mod.resolve_session_paths(environment)
        assert paths is not None
        transport = transport_mod.CursorTaskTransport(paths)
        request = _cursor_request()
        transport.publish_request(request, timeout_seconds=1)
        result = transport.wait_for_result(
            request["requestId"],
            timeout_seconds=0.05,
            poll_interval=0.01,
        )
        assert result["status"] == "TIMED_OUT"
        assert not (paths.requests_dir / f"{request['requestId']}.json").exists()


def test_transport_rejects_mismatched_result_identity():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-mismatch-") as root:
        environment = {
            transport_mod.SESSION_ENV: str(Path(root) / "session")
        }
        paths = transport_mod.resolve_session_paths(environment)
        assert paths is not None
        transport = transport_mod.CursorTaskTransport(paths)
        request = _cursor_request()
        transport.publish_request(request, timeout_seconds=1)
        result_path = paths.results_dir / f"{request['requestId']}.json"
        transport_mod.atomic_write_json(
            result_path,
            {
                "protocol": transport_mod.RESULT_PROTOCOL,
                "requestId": "req_wrong_result_0001",
                "status": "COMPLETED",
                "cloudAgentBcId": "bc-synthetic-wrong",
            },
        )
        try:
            transport.wait_for_result(
                request["requestId"],
                timeout_seconds=0.1,
                poll_interval=0.01,
            )
            raise AssertionError("expected CursorTransportError")
        except transport_mod.CursorTransportError:
            pass


def test_runner_blocks_when_task_bridge_is_not_ready():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-blocked-") as root:
        socket_path = Path(root) / "agent.sock"
        socket_path.touch()
        adapter = CursorCloudAgentAdapter(environment=_env(socket_path))
        registry = AdapterRegistry()
        registry.register(adapter)
        request = _cursor_request()
        receipt = ExecutionAdapterRunner(registry).execute(request)
        assert receipt["status"] == "BLOCKED"
        assert receipt["blocker"]["code"] == "BLOCKED_API"
        assert receipt["executionIdentity"] is None
        assert receipt["proof"]["level"] == "CAPABILITY_PROBE_ONLY"
        _validate_receipt(receipt, request)


def test_synthetic_bridge_executes_without_runtime_proof_promotion():
    with tempfile.TemporaryDirectory(prefix="asb-cursor-execute-") as root:
        root_path = Path(root)
        socket_path = root_path / "agent.sock"
        socket_path.touch()
        session = root_path / "session"
        environment = _env(socket_path, session)
        paths = transport_mod.resolve_session_paths(environment)
        assert paths is not None
        transport_mod.write_bridge_readiness(paths, "synthetic-monitor")

        stop = threading.Event()

        def bridge():
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline and not stop.is_set():
                for request_path in paths.requests_dir.glob("req_*.json"):
                    envelope = transport_mod.load_json(request_path)
                    request_id = envelope["requestId"]
                    transport_mod.atomic_write_json(
                        paths.results_dir / f"{request_id}.json",
                        {
                            "protocol": transport_mod.RESULT_PROTOCOL,
                            "requestId": request_id,
                            "status": "COMPLETED",
                            "cloudAgentBcId": "bc-synthetic-eat302",
                            "dashboardUrl": "https://cursor.com/agents/bc-synthetic-eat302",
                            "completedAt": datetime.now(timezone.utc)
                            .isoformat()
                            .replace("+00:00", "Z"),
                        },
                    )
                    return
                time.sleep(0.01)

        worker = threading.Thread(target=bridge, daemon=True)
        worker.start()
        try:
            registry = AdapterRegistry()
            registry.register(CursorCloudAgentAdapter(environment=environment))
            request = _cursor_request()
            receipt = ExecutionAdapterRunner(registry).execute(request)
        finally:
            stop.set()
            worker.join(timeout=2)

        assert receipt["status"] == "EXECUTED"
        assert receipt["executionIdentity"] == {
            "kind": "CURSOR_CLOUD_AGENT",
            "value": "bc-synthetic-eat302",
        }
        assert receipt["proof"]["level"] == "CONTRACT_STATIC"
        assert receipt["proof"]["independentValidationRequired"] is True
        assert receipt["proof"]["validationArtifact"] is None
        _validate_receipt(receipt, request)


def main() -> None:
    test_reuse_map_preserves_common_ownership_and_pr332_lineage()
    test_probe_wrong_host_blocks_host_dimension()
    test_probe_socket_presence_does_not_imply_dispatch_ready()
    test_fresh_private_bridge_readiness_is_ready()
    test_stale_bridge_readiness_fails_closed()
    test_relative_session_path_fails_closed()
    test_transport_timeout_cancels_pending_request()
    test_transport_rejects_mismatched_result_identity()
    test_runner_blocks_when_task_bridge_is_not_ready()
    test_synthetic_bridge_executes_without_runtime_proof_promotion()
    print("PASS: Cursor CloudAgent adapter EAT-302..304 synthetic contract")


if __name__ == "__main__":
    main()
