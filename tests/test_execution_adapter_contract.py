from __future__ import annotations

import copy
import datetime as dt
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DIR = ROOT / "tooling" / "harness" / "execution-adapters"
SCHEMA_DIR = CONTRACT_DIR / "schemas"
FIXTURE_DIR = CONTRACT_DIR / "fixtures"
PLAN_ID = "ASB-2026-09-EXECUTION-ADAPTER-TRIO-V1"


class ContractError(AssertionError):
    pass


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def matches_type(value, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    raise ContractError(f"unsupported schema type {expected!r}")


def resolve_ref(root_schema: dict, ref: str) -> dict:
    if not ref.startswith("#/"):
        raise ContractError(f"external ref unsupported in dependency-free validator: {ref}")
    value = root_schema
    for part in ref[2:].split("/"):
        value = value[part.replace("~1", "/").replace("~0", "~")]
    if not isinstance(value, dict):
        raise ContractError(f"ref does not resolve to schema object: {ref}")
    return value


def validate_json_schema(value, schema: dict, root_schema: dict | None = None, path: str = "$") -> None:
    if root_schema is None:
        root_schema = schema

    if "$ref" in schema:
        validate_json_schema(value, resolve_ref(root_schema, schema["$ref"]), root_schema, path)
        return

    if "oneOf" in schema:
        matches = 0
        errors = []
        for option in schema["oneOf"]:
            try:
                validate_json_schema(value, option, root_schema, path)
                matches += 1
            except ContractError as exc:
                errors.append(str(exc))
        if matches != 1:
            raise ContractError(f"{path}: expected exactly one oneOf match, got {matches}; {errors}")
        return

    if "allOf" in schema:
        for item in schema["allOf"]:
            condition = item.get("if")
            then = item.get("then")
            if condition is None or then is None:
                validate_json_schema(value, item, root_schema, path)
                continue
            try:
                validate_json_schema(value, condition, root_schema, path)
            except ContractError:
                continue
            validate_json_schema(value, then, root_schema, path)

    if "const" in schema and value != schema["const"]:
        raise ContractError(f"{path}: expected const {schema['const']!r}")

    if "enum" in schema and value not in schema["enum"]:
        raise ContractError(f"{path}: {value!r} not in enum")

    expected_type = schema.get("type")
    if expected_type is not None:
        allowed = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(matches_type(value, item) for item in allowed):
            raise ContractError(f"{path}: expected {allowed}, got {type(value).__name__}")

    if isinstance(value, dict):
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            raise ContractError(f"{path}: too few properties")
        if "maxProperties" in schema and len(value) > schema["maxProperties"]:
            raise ContractError(f"{path}: too many properties")
        required = schema.get("required", [])
        missing = [name for name in required if name not in value]
        if missing:
            raise ContractError(f"{path}: missing required fields {missing}")
        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        if additional is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise ContractError(f"{path}: unexpected properties {extras}")
        for key, child in value.items():
            if key in properties:
                validate_json_schema(child, properties[key], root_schema, f"{path}.{key}")
            elif isinstance(additional, dict):
                validate_json_schema(child, additional, root_schema, f"{path}.{key}")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            raise ContractError(f"{path}: too few items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise ContractError(f"{path}: too many items")
        if "items" in schema:
            for index, child in enumerate(value):
                validate_json_schema(child, schema["items"], root_schema, f"{path}[{index}]")

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            raise ContractError(f"{path}: string too short")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            raise ContractError(f"{path}: string too long")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            raise ContractError(f"{path}: does not match {schema['pattern']!r}")
        if schema.get("format") == "date-time":
            try:
                parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError as exc:
                raise ContractError(f"{path}: invalid date-time") from exc
            if parsed.tzinfo is None:
                raise ContractError(f"{path}: date-time lacks timezone")

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise ContractError(f"{path}: below minimum")
        if "maximum" in schema and value > schema["maximum"]:
            raise ContractError(f"{path}: above maximum")


def validate_request_semantics(request: dict) -> None:
    if request["adapterKind"] != request["input"]["kind"]:
        raise ContractError("adapterKind/input.kind mismatch")
    if request["executionPolicy"]["interactiveAuthAllowed"] is not False:
        raise ContractError("interactive authentication must remain disabled")
    if request["executionPolicy"]["profile"] == "READ_ONLY" and request["mutation"]["allowed"]:
        raise ContractError("READ_ONLY request cannot allow mutation")
    if request["adapterKind"] == "local-argv":
        argv = request["input"]["argv"]
        if not argv or not all(isinstance(item, str) and item for item in argv):
            raise ContractError("local argv must be a non-empty string array")
    if request["adapterKind"] == "claude-code" and not request["input"]["structuredOutputRequired"]:
        raise ContractError("Claude Code v1 requires structured output")


def validate_capability_semantics(report: dict) -> None:
    if report["proofCeiling"] != "CAPABILITY_PROBE_ONLY":
        raise ContractError("probe proof ceiling promotion")
    if report["status"] == "READY":
        if report["blocker"] is not None:
            raise ContractError("READY report cannot carry blocker")
        invalid = {
            name: state
            for name, state in report["readiness"].items()
            if state not in {"READY", "NOT_APPLICABLE"}
        }
        if invalid:
            raise ContractError(f"READY report has unproven readiness dimensions: {invalid}")
    elif report["blocker"] is None:
        raise ContractError("blocked/unsupported report requires blocker")


def validate_receipt_semantics(receipt: dict, request: dict | None = None) -> None:
    status = receipt["status"]
    if status == "EXECUTED":
        if receipt["executionIdentity"] is None:
            raise ContractError("EXECUTED requires native execution identity")
        if receipt["blocker"] is not None:
            raise ContractError("EXECUTED cannot carry blocker")
    elif receipt["blocker"] is None:
        raise ContractError(f"{status} requires explicit blocker")

    started = dt.datetime.fromisoformat(receipt["startedAt"].replace("Z", "+00:00"))
    completed = dt.datetime.fromisoformat(receipt["completedAt"].replace("Z", "+00:00"))
    elapsed_ms = (completed - started).total_seconds() * 1000
    if elapsed_ms < 0:
        raise ContractError("completedAt cannot precede startedAt")
    tolerance_ms = max(1.0, elapsed_ms * 0.01)
    if abs(float(receipt["durationMs"]) - elapsed_ms) > tolerance_ms:
        raise ContractError("durationMs is inconsistent with startedAt/completedAt")

    runtime_proof = {
        "LOCAL_RUNTIME_OBSERVED": ("local-argv", "PROCESS"),
        "CLAUDE_CODE_RUNTIME_OBSERVED": ("claude-code", "CLAUDE_SESSION"),
        "CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED": ("cursor-cloud-agent", "CURSOR_CLOUD_AGENT"),
    }
    proof = receipt["proof"]
    if proof["level"] in runtime_proof:
        expected_adapter, expected_identity = runtime_proof[proof["level"]]
        if receipt["adapterKind"] != expected_adapter:
            raise ContractError("runtime proof level does not match adapterKind")
        identity = receipt["executionIdentity"]
        if not isinstance(identity, dict) or identity.get("kind") != expected_identity:
            raise ContractError("runtime proof level does not match execution identity")
        if proof["independentValidationRequired"] is not True or not proof["validationArtifact"]:
            raise ContractError("runtime proof requires independent validation artifact")

    if request is not None:
        for field in ("requestId", "correlationId", "adapterKind"):
            if receipt[field] != request[field]:
                raise ContractError(f"receipt/request {field} mismatch")
        output_bytes = len(
            json.dumps(receipt["output"], ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        )
        if output_bytes > request["executionPolicy"]["maxOutputBytes"]:
            raise ContractError("receipt output exceeds request maxOutputBytes")


def assert_negative(fn, message: str) -> None:
    try:
        fn()
    except ContractError:
        return
    raise AssertionError(message)


def main() -> None:
    contract = load_json(CONTRACT_DIR / "execution-adapter-contract.v1.json")
    request_schema = load_json(SCHEMA_DIR / "execution-request.v1.schema.json")
    receipt_schema = load_json(SCHEMA_DIR / "execution-receipt.v1.schema.json")
    capability_schema = load_json(SCHEMA_DIR / "capability-report.v1.schema.json")

    assert contract["contractId"] == "agentswitchboard.execution-adapter.v1"
    assert contract["status"] == "accepted-contract-only"
    assert [item["adapterKind"] for item in contract["adapterKinds"]] == [
        "local-argv", "claude-code", "cursor-cloud-agent"
    ]
    assert contract["ownership"]["brokerOwner"].startswith("AgentSwitchboard")
    assert "FirstMate" in contract["ownership"]["crewRuntimeBoundary"]
    joined_invariants = "\n".join(contract["invariants"]).lower()
    assert "human scheduler" in joined_invariants
    assert "interactive authentication" in joined_invariants
    assert "prompt kit" in joined_invariants
    assert "no adapter invents success" in joined_invariants

    for schema in (request_schema, receipt_schema, capability_schema):
        assert schema["type"] == "object"
        assert schema["additionalProperties"] is False

    requests = [
        load_json(FIXTURE_DIR / "execution-request.local-argv.valid.json"),
        load_json(FIXTURE_DIR / "execution-request.claude-code.valid.json"),
        load_json(FIXTURE_DIR / "execution-request.cursor-cloud-agent.valid.json"),
    ]
    for request in requests:
        validate_json_schema(request, request_schema)
        validate_request_semantics(request)

    capability = load_json(FIXTURE_DIR / "capability-report.blocked-auth.valid.json")
    validate_json_schema(capability, capability_schema)
    validate_capability_semantics(capability)

    receipts = [
        load_json(FIXTURE_DIR / "execution-receipt.local-argv.valid.json"),
        load_json(FIXTURE_DIR / "execution-receipt.blocked.valid.json"),
    ]
    requests_by_id = {request["requestId"]: request for request in requests}
    for receipt in receipts:
        validate_json_schema(receipt, receipt_schema)
        validate_receipt_semantics(receipt, requests_by_id.get(receipt["requestId"]))

    bad = copy.deepcopy(requests[0])
    bad["input"]["kind"] = "claude-code"
    assert_negative(lambda: validate_request_semantics(bad), "adapter/input mismatch was accepted")

    bad = copy.deepcopy(requests[1])
    bad["executionPolicy"]["interactiveAuthAllowed"] = True
    assert_negative(lambda: validate_json_schema(bad, request_schema), "interactive authentication was accepted")

    bad = copy.deepcopy(requests[0])
    bad["executionPolicy"]["profile"] = "READ_ONLY"
    bad["mutation"]["allowed"] = True
    assert_negative(lambda: validate_json_schema(bad, request_schema), "READ_ONLY mutation was accepted by schema")

    bad = copy.deepcopy(receipts[0])
    bad["executionIdentity"] = None
    assert_negative(lambda: validate_json_schema(bad, receipt_schema), "EXECUTED without identity was accepted by schema")
    assert_negative(lambda: validate_receipt_semantics(bad), "EXECUTED without identity was accepted")

    bad = copy.deepcopy(receipts[1])
    bad["blocker"] = None
    assert_negative(lambda: validate_json_schema(bad, receipt_schema), "BLOCKED without blocker was accepted by schema")
    assert_negative(lambda: validate_receipt_semantics(bad), "BLOCKED without blocker was accepted")

    ready = copy.deepcopy(capability)
    ready["status"] = "READY"
    assert_negative(lambda: validate_json_schema(ready, capability_schema), "READY with blocker was accepted by schema")
    assert_negative(lambda: validate_capability_semantics(ready), "READY with blocker was accepted")

    ready = copy.deepcopy(capability)
    ready["status"] = "READY"
    ready["blocker"] = None
    ready["readiness"] = {name: "READY" for name in ready["readiness"]}
    validate_json_schema(ready, capability_schema)
    validate_capability_semantics(ready)
    unknown = copy.deepcopy(ready)
    unknown["readiness"]["dispatch"] = "UNKNOWN"
    assert_negative(lambda: validate_json_schema(unknown, capability_schema), "READY with UNKNOWN was accepted by schema")
    assert_negative(lambda: validate_capability_semantics(unknown), "READY with UNKNOWN was accepted")

    reversed_time = copy.deepcopy(receipts[0])
    reversed_time["completedAt"] = "2026-09-20T16:59:59Z"
    assert_negative(lambda: validate_receipt_semantics(reversed_time), "reversed receipt timing was accepted")

    wrong_duration = copy.deepcopy(receipts[0])
    wrong_duration["durationMs"] = 999
    assert_negative(lambda: validate_receipt_semantics(wrong_duration), "inconsistent durationMs was accepted")

    promoted = copy.deepcopy(receipts[0])
    promoted["proof"]["level"] = "CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED"
    promoted["proof"]["independentValidationRequired"] = False
    promoted["proof"]["validationArtifact"] = None
    assert_negative(lambda: validate_receipt_semantics(promoted), "cross-adapter self-promoted runtime proof was accepted")

    over_budget_request = copy.deepcopy(requests[0])
    over_budget_request["executionPolicy"]["maxOutputBytes"] = 1024
    over_budget_receipt = copy.deepcopy(receipts[0])
    over_budget_receipt["output"]["stdoutExcerpt"] = "x" * 1024
    assert_negative(
        lambda: validate_receipt_semantics(over_budget_receipt, over_budget_request),
        "receipt output exceeding request maxOutputBytes was accepted",
    )

    nested = copy.deepcopy(receipts[0])
    nested["output"]["structuredResult"] = {"nested": {"not": "bounded-v1"}}
    assert_negative(
        lambda: validate_json_schema(nested, receipt_schema),
        "nested unbounded structuredResult was accepted by schema",
    )

    registry = load_json(ROOT / "plans" / "plan-registry.json")
    entry = next(item for item in registry["plans"] if item["planId"] == PLAN_ID)
    assert entry["path"] == "plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json"
    assert entry["summaryPath"] == "plans/active/ASB-2026-09-execution-adapter-trio-v1.md"

    plan = load_json(ROOT / entry["path"])
    expected_task_ids = [
        "EAT-001", "EAT-002", "EAT-003", "EAT-004", "EAT-005", "EAT-006",
        "EAT-101", "EAT-102", "EAT-103", "EAT-104", "EAT-105", "EAT-106", "EAT-107",
        "EAT-201", "EAT-202", "EAT-203", "EAT-204", "EAT-205", "EAT-206", "EAT-207", "EAT-208",
        "EAT-301", "EAT-302", "EAT-303", "EAT-304", "EAT-305", "EAT-306", "EAT-307", "EAT-308", "EAT-309",
        "EAT-401", "EAT-402", "EAT-403", "EAT-404", "EAT-405", "EAT-406", "EAT-407",
    ]
    actual_task_ids = [task["taskId"] for task in plan["tasks"]]
    assert actual_task_ids == expected_task_ids, actual_task_ids
    assert len(actual_task_ids) == len(set(actual_task_ids))
    assert "PR #332" in "\n".join(plan["forbiddenScope"] + plan["dependencies"] + plan["safeParallelWork"])
    assert "CONTRACT_STATIC" in plan["proof"]["ceiling"]

    floor = load_json(ROOT / ".ai" / "harness" / "automated-test-floor.manifest.json")
    gates = {gate["id"]: gate for gate in floor["gates"]}
    assert gates["execution-adapter-contract-script"]["path"] == "tests/test_execution_adapter_contract.py"
    assert gates["execution-adapter-contract-script"]["required"] is True
    assert gates["execution-adapter-registry-script"]["path"] == "tests/test_execution_adapter_registry.py"
    assert gates["execution-adapter-registry-script"]["required"] is True

    codebase_map = (ROOT / "CODEBASE_MAP.md").read_text(encoding="utf-8")
    assert "## Execution adapter contract" in codebase_map
    assert "execution-adapter-contract.v1.json" in codebase_map
    assert "adapter_protocol.py" in codebase_map
    assert "registry.py" in codebase_map
    assert "runner.py" in codebase_map

    work_queue = (ROOT / ".ai" / "WORK_QUEUE.md").read_text(encoding="utf-8")
    assert "ASQ-022 — Execute adapter trio v1 implementation waves" in work_queue
    assert "ASB-2026-09-EXECUTION-ADAPTER-TRIO-V1" in work_queue

    print("PASS: execution adapter contract v1")


if __name__ == "__main__":
    main()
