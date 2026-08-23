#!/usr/bin/env python3
"""Zero-entropy boundary tests for the exact-output grounding interceptor."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tooling/harness/operational/exact-grounding/exact_grounding.py"
FIXTURE = ROOT / "tooling/harness/operational/exact-grounding/fixtures/protected-action.schema.json"
MANIFEST = ROOT / "tooling/harness/operational/exact-grounding/manifest.json"
PACKET_SCHEMA = ROOT / "tooling/harness/operational/exact-grounding/schemas/grounding-packet.schema.json"

spec = importlib.util.spec_from_file_location("exact_grounding", MODULE_PATH)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def proposal(packet: dict, **argument_overrides):
    arguments = {"calendar_id": "primary", "summary": "Grounded fixture"}
    arguments.update(argument_overrides)
    sources = {"tool": packet["fieldSources"]["tool"]}
    for name in arguments:
        path = f"arguments.{name}"
        if path in packet["fieldSources"]:
            sources[path] = packet["fieldSources"][path]
    return {
        "tool": packet["action"]["name"],
        "arguments": arguments,
        "provenance": {
            "sourceSha256": packet["source"]["sha256"],
            "sourceVersion": packet["source"]["version"],
            "fieldSources": sources,
        },
    }


def main() -> None:
    for path in (MODULE_PATH, FIXTURE, MANIFEST, PACKET_SCHEMA):
        require(path.is_file(), f"missing exact-grounding component: {path.relative_to(ROOT)}")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    require(manifest["harnessId"] == "agentswitchboard.exact-output-grounding.v1", "manifest id")
    require(set(manifest["gateStatuses"]) == mod.STATUSES, "registered statuses must equal runtime statuses")
    require(manifest["executionAuthority"] == "host-runtime-only-after-GROUNDED_PASS", "host must own execution")

    packet_schema = json.loads(PACKET_SCHEMA.read_text(encoding="utf-8"))
    require(packet_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "packet schema draft")
    require(packet_schema["properties"]["packetSchema"]["const"] == mod.PACKET_SCHEMA_ID, "packet schema identity")

    base_for_build = {"arguments": {"calendar_id": "primary", "summary": "Grounded fixture", "visibility": "private"}}
    packet = mod.build_grounding_packet(FIXTURE.resolve(), base_for_build)
    require(packet["action"]["allowedArguments"] == ["calendar_id", "summary", "visibility", "send_updates"], "allowed surface order")
    require(set(packet["action"]["argumentConstraints"]) == {"calendar_id", "summary", "visibility"}, "packet should omit unused optional send_updates constraint")
    require("arguments.send_updates" not in packet["fieldSources"], "unused optional field should not inflate packet")

    valid = proposal(packet, visibility="private")
    calls: list[dict] = []
    passed = mod.intercept_and_execute(packet, valid, lambda action: calls.append(action) or "executed-once")
    require(passed.status == "GROUNDED_PASS", f"valid proposal should pass: {passed}")
    require(passed.executed is True and passed.executionResult == "executed-once", "pass should expose execution proof")
    require(len(calls) == 1, "valid side effect must execute exactly once")

    hallucinated_tool = json.loads(json.dumps(valid))
    hallucinated_tool["tool"] = "fixture.calendar.creat"
    calls.clear()
    blocked = mod.intercept_and_execute(packet, hallucinated_tool, lambda action: calls.append(action))
    require(blocked.status == "UNSOURCED_BLOCK", "hallucinated tool identifier must block")
    require(not calls and blocked.executed is False, "blocked tool must not execute")

    hallucinated_arg = json.loads(json.dumps(valid))
    hallucinated_arg["arguments"]["calendarID"] = hallucinated_arg["arguments"].pop("calendar_id")
    calls.clear()
    blocked = mod.intercept_and_execute(packet, hallucinated_arg, lambda action: calls.append(action))
    require(blocked.status == "UNSOURCED_BLOCK", "hallucinated argument identifier must block")
    require(not calls, "unsourced argument must not execute")

    contradiction = proposal(packet, visibility="secret")
    calls.clear()
    blocked = mod.intercept_and_execute(packet, contradiction, lambda action: calls.append(action))
    require(blocked.status == "CONTRADICTION_BLOCK", "enum contradiction must block")
    require(not calls, "contradicting value must not execute")

    malformed = {"tool": packet["action"]["name"], "arguments": {}}
    blocked = mod.gate_proposal(packet, malformed)
    require(blocked.status == "SCHEMA_MISMATCH", "malformed proposal must be schema mismatch")

    malformed_packet = {"packetSchema": mod.PACKET_SCHEMA_ID}
    blocked = mod.gate_proposal(malformed_packet, valid)
    require(blocked.status == "GROUNDING_FAILURE", "malformed packet must fail closed")

    bad_attribution = json.loads(json.dumps(valid))
    bad_attribution["provenance"]["fieldSources"]["arguments.visibility"] = "/invented/path"
    blocked = mod.gate_proposal(packet, bad_attribution)
    require(blocked.status == "UNSOURCED_BLOCK", "wrong source pointer must block")

    with tempfile.TemporaryDirectory() as temp_dir:
        stale_source = Path(temp_dir) / "protected-action.schema.json"
        shutil.copy2(FIXTURE, stale_source)
        stale_packet = mod.build_grounding_packet(stale_source.resolve(), base_for_build)
        stale_valid = proposal(stale_packet, visibility="private")
        data = json.loads(stale_source.read_text(encoding="utf-8"))
        data["x-source-version"] = "2026-08-22.2"
        stale_source.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        blocked = mod.gate_proposal(stale_packet, stale_valid)
        require(blocked.status == "GROUNDING_FAILURE" and "stale_source" in blocked.reason, "stale authority must fail closed")

    with tempfile.TemporaryDirectory() as temp_dir:
        missing_source = Path(temp_dir) / "authority.json"
        shutil.copy2(FIXTURE, missing_source)
        missing_packet = mod.build_grounding_packet(missing_source.resolve(), base_for_build)
        missing_valid = proposal(missing_packet, visibility="private")
        missing_source.unlink()
        blocked = mod.gate_proposal(missing_packet, missing_valid)
        require(blocked.status == "GROUNDING_FAILURE", "unavailable authority must fail closed")

    with tempfile.TemporaryDirectory() as temp_dir:
        checker_source = Path(temp_dir) / "checker-invalid.schema.json"
        checker_data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        checker_data["properties"]["arguments"]["properties"]["visibility"]["pattern"] = "["
        checker_source.write_text(json.dumps(checker_data, indent=2) + "\n", encoding="utf-8")
        checker_packet = mod.build_grounding_packet(checker_source.resolve(), base_for_build)
        checker_valid = proposal(checker_packet, visibility="private")
        blocked = mod.gate_proposal(checker_packet, checker_valid)
        require(blocked.status == "GROUNDING_FAILURE" and "checker_failure" in blocked.reason, "checker failure must fail closed")

    with tempfile.TemporaryDirectory() as temp_dir:
        malformed_source = Path(temp_dir) / "malformed.json"
        malformed_source.write_text("{", encoding="utf-8")
        try:
            mod.build_grounding_packet(malformed_source)
        except json.JSONDecodeError:
            pass
        else:
            raise AssertionError("malformed grounding source must fail packet build")

    print("EXACT GROUNDING GATE: PASS")
    print("fixtures: GROUNDED_PASS, UNSOURCED_BLOCK, CONTRADICTION_BLOCK, SCHEMA_MISMATCH, GROUNDING_FAILURE")
    print("side-effect proof: valid action executed exactly once; all deterministic blocks executed zero times")


if __name__ == "__main__":
    main()
