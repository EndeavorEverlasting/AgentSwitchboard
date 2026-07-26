#!/usr/bin/env python3
"""Dependency-free semantic tests for the typed cascade harness."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PATH = ROOT / "tooling/cascade/harness/typed-gates/fixtures/typed-cascade.cases.json"
REGISTRY_PATH = ROOT / "tooling/cascade/harness/typed-gates/typed-cascade.registry.json"
ONTOLOGY_PATH = ROOT / "tooling/cascade/harness/typed-gates/ontology.registry.json"


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def reduce_case(case: dict[str, Any], fixture: dict[str, Any], ontology: dict[str, Any]) -> str:
    request = case["request"]
    contract = fixture["preGateContract"]
    payload = request.get("input")

    if not isinstance(payload, dict):
        return "REJECT_INPUT_SCHEMA"

    count = payload.get("count")
    if not isinstance(count, int) or isinstance(count, bool):
        return "REJECT_INPUT_SCHEMA"
    count_contract = contract["count"]
    if count < count_contract["minimum"] or count > count_contract["maximum"]:
        return "REJECT_INPUT_SCHEMA"

    mode = payload.get("mode")
    if mode not in contract["mode"]["allowed"]:
        return "REJECT_INPUT_SCHEMA"

    if request.get("authorityDeclared") is not True:
        return "REJECT_INPUT_AUTHORITY"

    observation = case.get("observation")
    if not isinstance(observation, dict) or observation.get("observed") is not True:
        return "BLOCKED_ACTION_NOT_OBSERVED"

    if observation.get("sameRun") is not True or observation.get("sameCorrelation") is not True:
        return "REJECT_STALE_RESULT"

    terminal_values = observation.get("terminalClassifications", [])
    if not isinstance(terminal_values, list) or len(terminal_values) != 1:
        return "REJECT_RESULT_CARDINALITY"

    classes = set(observation.get("classes", []))
    disjoint_rule = next(rule for rule in ontology["cascadeRules"] if rule["ruleId"] == "success-and-rejection-are-disjoint")
    if disjoint_rule["leftClass"] in classes and disjoint_rule["rightClass"] in classes:
        return "REJECT_RESULT_DISJOINTNESS"

    proof_rule = next(rule for rule in ontology["cascadeRules"] if rule["ruleId"] == "proof-level-is-closed")
    if observation.get("proofLevel") not in proof_rule["allowed"]:
        return "REJECT_RESULT_ENUMERATION"

    if observation.get("causationClass") != "RuntimeEvent":
        return "REJECT_RESULT_DOMAIN_RANGE"

    if observation.get("actionIdExists") is not True or observation.get("causationExists") is not True:
        return "REJECT_RESULT_REFERENCE"

    if not (
        observation.get("successorCorrelationInherited") is True
        and observation.get("successorCausationIsParent") is True
        and observation.get("successorSequenceAdvanced") is True
    ):
        return "REJECT_CAUSALITY"

    return "PASS_SYNTHETIC_CASCADE"


def main() -> int:
    fixture = load_json(FIXTURE_PATH)
    registry = load_json(REGISTRY_PATH)
    ontology = load_json(ONTOLOGY_PATH)

    failures: list[str] = []

    if fixture.get("suiteId") != "typed-cascade-gates/v1":
        failures.append("unexpected fixture suite ID")

    discipline = registry["executionDiscipline"]
    expected_discipline = {
        "agentMayMutateExternalState": False,
        "deterministicBoundaryOwnsMutation": True,
        "preGateRequiredBeforeExecution": True,
        "postGateRequiredBeforeSuccessorEmission": True,
        "silentGateBypassAllowed": False,
    }
    for key, expected in expected_discipline.items():
        if discipline.get(key) is not expected:
            failures.append(f"execution discipline mismatch: {key}")

    rule_types = {item["type"] for item in ontology["ruleTypes"]}
    required_rule_types = {"functional-property", "disjoint-classes", "one-of", "domain-range", "required-reference"}
    missing_rule_types = required_rule_types - rule_types
    if missing_rule_types:
        failures.append(f"missing ontology rule types: {sorted(missing_rule_types)}")

    seen: set[str] = set()
    for case in fixture["cases"]:
        case_id = case["caseId"]
        if case_id in seen:
            failures.append(f"duplicate case ID: {case_id}")
            continue
        seen.add(case_id)
        actual = reduce_case(case, fixture, ontology)
        expected = case["expectedClassification"]
        if actual != expected:
            failures.append(f"{case_id}: expected {expected}, got {actual}")
        else:
            print(f"[PASS] {case_id} -> {actual}")

    required_classifications = {
        "PASS_SYNTHETIC_CASCADE",
        "REJECT_INPUT_SCHEMA",
        "REJECT_INPUT_AUTHORITY",
        "BLOCKED_ACTION_NOT_OBSERVED",
        "REJECT_STALE_RESULT",
        "REJECT_RESULT_CARDINALITY",
        "REJECT_RESULT_DISJOINTNESS",
        "REJECT_RESULT_ENUMERATION",
        "REJECT_RESULT_DOMAIN_RANGE",
        "REJECT_RESULT_REFERENCE",
        "REJECT_CAUSALITY",
    }
    registered = set(registry["cascade"]["terminalClassifications"])
    if not required_classifications.issubset(registered):
        failures.append(f"registry missing classifications: {sorted(required_classifications - registered)}")

    if failures:
        for failure in failures:
            print(f"[FAIL] {failure}", file=sys.stderr)
        print(f"Result: {len(seen) - len(failures)} case/contract checks passed with {len(failures)} failure(s)")
        return 1

    print(f"Result: {len(seen)} fixture cases passed; typed cascade semantics are internally consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
