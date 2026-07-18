#!/usr/bin/env python3
"""Linux-runnable validator for the P00 GNHF orchestration contracts.

This script does not require jsonschema. It performs structural checks, schema
const matching, dependency cycle detection, and PowerShell syntax validation when
PowerShell is available. It does not launch agents or mutate repositories.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / "schemas"
FIXTURES = ROOT / "tests" / "fixtures"
RESULTS_DIR = ROOT / "tests" / "results"

SCHEMA_CONSTS = {
    "prompt-queue.schema.json": "agentswitchboard.gnhf.prompt-queue.v1",
    "queue-plan.schema.json": "agentswitchboard.gnhf.queue-plan.v1",
    "lane-result.schema.json": "agentswitchboard.gnhf.lane-result.v1",
    "child-operation-request.schema.json": "agentswitchboard.gnhf.child-operation-request.v1",
    "child-operation-result.schema.json": "agentswitchboard.gnhf.child-operation-result.v1",
    "trigger-snapshot.schema.json": "agentswitchboard.gnhf.trigger-snapshot.v1",
}

FIXTURE_CONSTS = {
    "example-prompt-queue.json": "agentswitchboard.gnhf.prompt-queue.v1",
    "example-child-operation-request.json": "agentswitchboard.gnhf.child-operation-request.v1",
    "example-trigger-snapshot.json": "agentswitchboard.gnhf.trigger-snapshot.v1",
}

REQUIRED_PS1 = [
    "Compile-GnhfPromptQueue.ps1",
    "Invoke-GnhfChildOperation.ps1",
    "Test-GnhfOrchestrationContracts.ps1",
]


class Validator:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.passes = 0

    def check(self, condition: bool, name: str, message: str = "") -> None:
        if condition:
            self.passes += 1
            print(f"[PASS] {name}")
        else:
            self.errors.append(f"{name}: {message}" if message else name)
            print(f"[FAIL] {name} - {message}")

    def load_json(self, path: Path, name: str) -> dict[str, Any] | None:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            self.check(False, f"parse/{name}", f"invalid JSON: {exc}")
            return None


def _check_const(validator: Validator, data: dict[str, Any] | None, expected: str, name: str) -> None:
    if data is None:
        return
    actual = data.get("schema")
    validator.check(actual == expected, f"schema/{name}", f"expected {expected!r}, got {actual!r}")


def _check_no_trailing_whitespace(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        if line.endswith(" ") or line.endswith("\t"):
            return False
    return True


def _detect_cycle(lanes: list[dict[str, Any]]) -> list[str] | None:
    ids = {str(lane["id"]) for lane in lanes}
    in_degree: dict[str, int] = {lid: 0 for lid in ids}
    successors: dict[str, list[str]] = {lid: [] for lid in ids}
    for lane in lanes:
        lid = str(lane["id"])
        for dep in lane.get("dependsOn", []):
            dep = str(dep)
            if dep in ids:
                in_degree[lid] += 1
                successors[dep].append(lid)
    ready = [lid for lid, d in in_degree.items() if d == 0]
    order: list[str] = []
    while ready:
        current = ready.pop(0)
        order.append(current)
        for nxt in successors[current]:
            in_degree[nxt] -= 1
            if in_degree[nxt] == 0:
                ready.append(nxt)
    if len(order) != len(lanes):
        return sorted(ids - set(order))
    return None


def _validate_prompt_queue(validator: Validator, data: dict[str, Any]) -> None:
    if data is None:
        return
    required = ["schema", "queueId", "generatedUtc", "sprint", "baseBranch", "lanes"]
    for field in required:
        validator.check(field in data, f"prompt-queue/required/{field}")
    lanes = data.get("lanes", [])
    validator.check(isinstance(lanes, list) and len(lanes) > 0, "prompt-queue/lanes", "must be a non-empty array")
    if not isinstance(lanes, list):
        return
    lane_ids = [str(lane["id"]) for lane in lanes if isinstance(lane, dict)]
    validator.check(len(lane_ids) == len(set(lane_ids)), "prompt-queue/lane-ids-unique", "lane ids must be unique")
    cycle = _detect_cycle(lanes)
    validator.check(cycle is None, "prompt-queue/no-dependency-cycle", f"cycle detected: {cycle}")


def _validate_child_request(validator: Validator, data: dict[str, Any]) -> None:
    if data is None:
        return
    required = ["schema", "requestId", "generatedUtc", "consumerId", "targetRepository", "operationId", "inputs", "authorityBoundary"]
    for field in required:
        validator.check(field in data, f"child-request/required/{field}")
    allowed_boundaries = ["repository-intake", "static-validation", "child-validator", "child-build", "read-only-runtime", "none"]
    boundary = data.get("authorityBoundary")
    validator.check(boundary in allowed_boundaries, "child-request/authority-boundary", f"{boundary!r} not in allowed list")


def _validate_trigger_snapshot(validator: Validator, data: dict[str, Any]) -> None:
    if data is None:
        return
    required = ["schema", "triggerId", "generatedUtc", "source", "eventType"]
    for field in required:
        validator.check(field in data, f"trigger-snapshot/required/{field}")


def _validate_powershell_parse(validator: Validator, script: Path, name: str) -> None:
    """Use PowerShell parser if available; otherwise skip with a note."""
    pwsh = shutil.which("pwsh")
    powershell = shutil.which("powershell")
    binary = pwsh or powershell
    if not binary:
        print(f"[SKIP] powershell-parse/{name} (PowerShell not available on this host)")
        return
    try:
        result = subprocess.run(
            [binary, "-NoLogo", "-NoProfile", "-Command",
             f"$tokens=$null; $errors=$null; [void][Management.Automation.Language.Parser]::ParseFile('{script}', [ref]$tokens, [ref]$errors); if ($errors.Count -gt 0) {{ exit 1 }}"],
            capture_output=True, text=True, timeout=30, check=False
        )
        validator.check(result.returncode == 0, f"powershell-parse/{name}", result.stderr or "parse errors")
    except Exception as exc:  # noqa: BLE001
        validator.check(False, f"powershell-parse/{name}", str(exc))


def main() -> int:
    validator = Validator()
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # Schema files exist and parse, with correct const values.
    for schema_name, expected_const in SCHEMA_CONSTS.items():
        schema_path = SCHEMAS / schema_name
        validator.check(schema_path.exists(), f"required/schema/{schema_name}")
        data = validator.load_json(schema_path, schema_name)
        if data is not None:
            validator.check("$schema" in data, f"schema/meta/{schema_name}")
            validator.check("$id" in data, f"schema/id/{schema_name}")
            properties = data.get("properties", {})
            schema_property = properties.get("schema", {})
            actual_const = schema_property.get("const")
            validator.check(
                actual_const == expected_const,
                f"schema/const/{schema_name}",
                f"expected {expected_const!r}, got {actual_const!r}"
            )

    # Fixture files exist and parse with correct const values.
    for fixture_name, expected_const in FIXTURE_CONSTS.items():
        fixture_path = FIXTURES / fixture_name
        validator.check(fixture_path.exists(), f"required/fixture/{fixture_name}")
        data = validator.load_json(fixture_path, fixture_name)
        _check_const(validator, data, expected_const, fixture_name)
        if fixture_name == "example-prompt-queue.json":
            _validate_prompt_queue(validator, data)
        elif fixture_name == "example-child-operation-request.json":
            _validate_child_request(validator, data)
        elif fixture_name == "example-trigger-snapshot.json":
            _validate_trigger_snapshot(validator, data)

    # Required PowerShell files exist and parse.
    for ps1_name in REQUIRED_PS1:
        ps1_path = ROOT / ps1_name
        validator.check(ps1_path.exists(), f"required/ps1/{ps1_name}")
        _validate_powershell_parse(validator, ps1_path, ps1_name)

    # Trailing whitespace check for new files.
    for path in list(SCHEMAS.glob("*.json")) + list(FIXTURES.glob("*.json")) + [ROOT / n for n in REQUIRED_PS1] + [ROOT / "README.md", ROOT / "docs" / "recovery" / "mainline-orchestration-value-map.md"]:
        if path.exists():
            validator.check(_check_no_trailing_whitespace(path), f"whitespace/{path.name}", "trailing whitespace")

    status = "PASS" if not validator.errors else "FAIL"
    result = {
        "schema": "agentswitchboard.gnhf.orchestration-validation.v1",
        "generatedUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "status": status,
        "passes": validator.passes,
        "errors": validator.errors,
    }
    result_path = RESULTS_DIR / "validation-result.json"
    result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"Result: {validator.passes} passed / {len(validator.errors)} failed")
    print(f"Evidence: {result_path}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
