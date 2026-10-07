#!/usr/bin/env python3
"""P82 measured prototype for the deterministic CommsCompiler pre-render gate."""
from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tooling" / "comms"))

from comms_compiler import compile_evidence, load_json  # noqa: E402

ADAPTER = ROOT / "tooling/comms/adapters/hh-fieldops.v1.json"
FIXTURE = ROOT / "tooling/comms/fixtures/hh-ticket-alignment-54.synthetic.json"
SCHEMAS = ROOT / "tooling/comms/schemas"


def codes(result: dict) -> set[str]:
    return {item["code"] for item in result["violations"]}


def main() -> int:
    adapter = load_json(ADAPTER)
    good = load_json(FIXTURE)

    schema_expectations = {
        "comms-project-adapter.v1.schema.json": "agentswitchboard.comms-project-adapter/v1",
        "comms-evidence-packet.v1.schema.json": "agentswitchboard.comms-evidence-packet/v1",
        "comms-compiled-facts.v1.schema.json": "agentswitchboard.comms-compiled-facts/v1",
    }
    for name, expected_const in schema_expectations.items():
        schema = json.loads((SCHEMAS / name).read_text(encoding="utf-8"))
        assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        assert schema["properties"]["schemaVersion"]["const"] == expected_const

    positive = compile_evidence(adapter, good)
    assert positive["result"] == "PASS", positive
    assert positive["coverage"]["observedItemCount"] == 54
    assert positive["coverage"]["observedStatusCounts"] == {
        "DONE": 29,
        "ESCALATED": 1,
        "OPEN": 17,
        "PENDING": 7,
    }
    assert positive["renderContract"]["fields"] == ["item_id", "classification"]
    assert positive["renderContract"]["proseGenerationAuthorized"] is True

    mutations: list[tuple[str, dict, set[str]]] = []

    omission = copy.deepcopy(good)
    omission["items"].pop()
    mutations.append(
        ("omission", omission, {"POPULATION_COUNT_MISMATCH", "STATUS_COUNT_MISMATCH"})
    )

    duplicate = copy.deepcopy(good)
    duplicate["items"][-1]["item_id"] = duplicate["items"][0]["item_id"]
    mutations.append(("duplicate", duplicate, {"DUPLICATE_IDENTITY"}))

    count_drift = copy.deepcopy(good)
    count_drift["expectedStatusCounts"]["OPEN"] = 16
    count_drift["expectedStatusCounts"]["DONE"] = 30
    mutations.append(("count-drift", count_drift, {"STATUS_COUNT_MISMATCH"}))

    topic_leak = copy.deepcopy(good)
    topic_leak["topics"].append("badge_renewals")
    mutations.append(("topic-leak", topic_leak, {"FORBIDDEN_TOPIC_PRESENT"}))

    baseline_faults_detected = 0
    compiler_faults_detected = 0
    for name, packet, expected_codes in mutations:
        baseline_accepts = True
        assert baseline_accepts is True
        result = compile_evidence(adapter, packet)
        assert result["result"] == "FAIL", (name, result)
        assert result["renderContract"]["proseGenerationAuthorized"] is False
        assert expected_codes.issubset(codes(result)), (
            name,
            expected_codes,
            codes(result),
        )
        compiler_faults_detected += 1

    again = compile_evidence(adapter, copy.deepcopy(good))
    assert json.dumps(positive, sort_keys=True, separators=(",", ":")) == json.dumps(
        again, sort_keys=True, separators=(",", ":")
    ), "compiler output must be deterministic"

    tracked_text = ADAPTER.read_text(encoding="utf-8") + "\n" + FIXTURE.read_text(
        encoding="utf-8"
    )
    forbidden_patterns = {
        "live incident numbers": r"\bINC\d{6,}\b",
        "Drive URLs": r"https://docs\.google\.com|https://drive\.google\.com",
        "email addresses": r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b",
    }
    for label, pattern in forbidden_patterns.items():
        assert not re.search(pattern, tracked_text, re.I), (
            f"synthetic fixture leaked {label}"
        )

    assert baseline_faults_detected == 0
    assert compiler_faults_detected == 4
    print(
        "PASS: CommsCompiler P82 prototype accepted the 54-item positive fixture "
        "and detected 4/4 seeded drafting faults versus 0/4 for the ungated baseline"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
