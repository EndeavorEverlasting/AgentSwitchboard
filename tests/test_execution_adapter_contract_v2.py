from __future__ import annotations

import copy
import json
from pathlib import Path

from test_execution_adapter_contract import (
    ContractError,
    assert_negative,
    load_json,
    validate_json_schema,
    validate_receipt_semantics,
    validate_request_semantics,
)

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DIR = ROOT / "tooling" / "harness" / "execution-adapters"
SCHEMA_DIR = CONTRACT_DIR / "schemas"
FIXTURE_DIR = CONTRACT_DIR / "fixtures"


def validate_request_v2_semantics(request: dict) -> None:
    validate_request_semantics(request)
    envelope = request["executionEnvelope"]
    if envelope["maxParallelWorkers"] > envelope["maxWorkers"]:
        raise ContractError("maxParallelWorkers cannot exceed maxWorkers")
    if envelope["maxWallClockSeconds"] > request["timeoutSeconds"]:
        raise ContractError("maxWallClockSeconds cannot exceed timeoutSeconds")


def validate_receipt_v2_semantics(receipt: dict, request: dict) -> None:
    validate_receipt_semantics(receipt, request)
    if receipt["actionFingerprint"] != request["actionFingerprint"]:
        raise ContractError("receipt/request actionFingerprint mismatch")

    usage = receipt["executionUsage"]
    envelope = request["executionEnvelope"]
    if usage["workersStarted"] > envelope["maxWorkers"]:
        raise ContractError("workersStarted exceeds maxWorkers")
    if usage["peakParallelWorkers"] > envelope["maxParallelWorkers"]:
        raise ContractError("peakParallelWorkers exceeds maxParallelWorkers")
    if usage["peakParallelWorkers"] > usage["workersStarted"]:
        raise ContractError("peakParallelWorkers cannot exceed workersStarted")
    if usage["modelTokensUsed"] > envelope["maxModelTokens"]:
        raise ContractError("modelTokensUsed exceeds maxModelTokens")
    if usage["wallClockMs"] > envelope["maxWallClockSeconds"] * 1000:
        raise ContractError("wallClockMs exceeds maxWallClockSeconds")
    duration_ms = float(receipt["durationMs"])
    tolerance_ms = max(1.0, duration_ms * 0.01)
    if abs(float(usage["wallClockMs"]) - duration_ms) > tolerance_ms:
        raise ContractError("wallClockMs is inconsistent with receipt durationMs")


def main() -> None:
    contract = load_json(CONTRACT_DIR / "execution-adapter-contract.v2.json")
    request_v1_schema = load_json(SCHEMA_DIR / "execution-request.v1.schema.json")
    receipt_v1_schema = load_json(SCHEMA_DIR / "execution-receipt.v1.schema.json")
    request_v2_schema = load_json(SCHEMA_DIR / "execution-request.v2.schema.json")
    receipt_v2_schema = load_json(SCHEMA_DIR / "execution-receipt.v2.schema.json")

    assert contract["contractId"] == "agentswitchboard.execution-adapter.v2"
    assert contract["versioning"]["v1"]["status"] == "unchanged-compatible"
    assert contract["versioning"]["v2"]["status"] == "authority-budget-bound"

    request_v1 = load_json(FIXTURE_DIR / "execution-request.local-argv.valid.json")
    receipt_v1 = load_json(FIXTURE_DIR / "execution-receipt.local-argv.valid.json")
    request_v2 = load_json(FIXTURE_DIR / "execution-request.v2.valid.json")
    receipt_v2 = load_json(FIXTURE_DIR / "execution-receipt.v2.valid.json")

    # Existing v1 remains valid and is not silently widened into v2.
    validate_json_schema(request_v1, request_v1_schema)
    validate_json_schema(receipt_v1, receipt_v1_schema)
    assert_negative(
        lambda: validate_json_schema(request_v1, request_v2_schema),
        "v1 request was silently accepted as v2",
    )
    assert_negative(
        lambda: validate_json_schema(receipt_v1, receipt_v2_schema),
        "v1 receipt was silently accepted as v2",
    )

    # v2 is valid only with the authority binding and execution envelope.
    validate_json_schema(request_v2, request_v2_schema)
    validate_request_v2_semantics(request_v2)
    validate_json_schema(receipt_v2, receipt_v2_schema)
    validate_receipt_v2_semantics(receipt_v2, request_v2)
    assert_negative(
        lambda: validate_json_schema(request_v2, request_v1_schema),
        "v2 request was silently accepted by v1",
    )
    assert_negative(
        lambda: validate_json_schema(receipt_v2, receipt_v1_schema),
        "v2 receipt was silently accepted by v1",
    )

    missing_fingerprint = load_json(
        FIXTURE_DIR / "execution-request.v2.missing-action-fingerprint.invalid.json"
    )
    assert_negative(
        lambda: validate_json_schema(missing_fingerprint, request_v2_schema),
        "v2 request missing actionFingerprint was accepted",
    )

    mismatched = load_json(
        FIXTURE_DIR / "execution-receipt.v2.mismatched-action-fingerprint.invalid.json"
    )
    validate_json_schema(mismatched, receipt_v2_schema)
    assert_negative(
        lambda: validate_receipt_v2_semantics(mismatched, request_v2),
        "mismatched actionFingerprint was accepted",
    )

    independent_budget_fixtures = [
        ("over-workers", "execution-receipt.v2.over-workers.invalid.json"),
        ("over-parallel", "execution-receipt.v2.over-parallel.invalid.json"),
        ("over-tokens", "execution-receipt.v2.over-tokens.invalid.json"),
        ("over-time", "execution-receipt.v2.over-time.invalid.json"),
    ]
    for label, fixture_name in independent_budget_fixtures:
        mutated = load_json(FIXTURE_DIR / fixture_name)
        validate_json_schema(mutated, receipt_v2_schema)
        assert_negative(
            lambda value=mutated: validate_receipt_v2_semantics(value, request_v2),
            f"{label} execution usage was accepted",
        )

    invalid_parallel = copy.deepcopy(request_v2)
    invalid_parallel["executionEnvelope"]["maxParallelWorkers"] = (
        invalid_parallel["executionEnvelope"]["maxWorkers"] + 1
    )
    validate_json_schema(invalid_parallel, request_v2_schema)
    assert_negative(
        lambda: validate_request_v2_semantics(invalid_parallel),
        "parallelism exceeding worker ceiling was accepted",
    )

    invalid_wall = copy.deepcopy(request_v2)
    invalid_wall["executionEnvelope"]["maxWallClockSeconds"] = (
        invalid_wall["timeoutSeconds"] + 1
    )
    validate_json_schema(invalid_wall, request_v2_schema)
    assert_negative(
        lambda: validate_request_v2_semantics(invalid_wall),
        "wall-clock ceiling exceeding request timeout was accepted",
    )

    wrong_workers = copy.deepcopy(receipt_v2)
    wrong_workers["executionUsage"]["workersStarted"] = (
        request_v2["executionEnvelope"]["maxWorkers"] + 1
    )
    assert_negative(
        lambda: validate_receipt_v2_semantics(wrong_workers, request_v2),
        "worker usage exceeding request ceiling was accepted",
    )

    contradictory_peak = copy.deepcopy(receipt_v2)
    contradictory_peak["executionUsage"]["peakParallelWorkers"] = 2
    contradictory_peak["executionUsage"]["workersStarted"] = 1
    assert_negative(
        lambda: validate_receipt_v2_semantics(contradictory_peak, request_v2),
        "peak parallelism exceeding workersStarted was accepted",
    )

    contradictory_wall = copy.deepcopy(receipt_v2)
    contradictory_wall["executionUsage"]["wallClockMs"] = 1000
    assert_negative(
        lambda: validate_receipt_v2_semantics(contradictory_wall, request_v2),
        "wallClockMs contradicting receipt duration was accepted",
    )

    oversized_output = copy.deepcopy(receipt_v2)
    oversized_output["output"]["stdoutExcerpt"] = "x" * 8192
    validate_json_schema(oversized_output, receipt_v2_schema)
    assert_negative(
        lambda: validate_receipt_v2_semantics(oversized_output, request_v2),
        "v2 receipt exceeding request maxOutputBytes was accepted",
    )

    # Every v2 action identity is a stable digest, not agent prose or mutable authority.
    assert request_v2["actionFingerprint"].startswith("sha256:")
    assert len(request_v2["actionFingerprint"]) == 71
    assert json.loads(json.dumps(request_v2)) == request_v2

    print("PASS: execution adapter contract v2 authority/budget envelope")


if __name__ == "__main__":
    main()
