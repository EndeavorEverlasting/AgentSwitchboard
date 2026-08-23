#!/usr/bin/env python3
"""Fail-closed exact-output grounding gate for AgentSwitchboard.

The host runtime owns execution authority. This module only builds a compact packet
from a current JSON Schema and validates a proposed protected action against it.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
import argparse
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Callable

PACKET_SCHEMA_ID = "agentswitchboard.exact-grounding-packet/v1"
STATUSES = {
    "GROUNDED_PASS",
    "UNSOURCED_BLOCK",
    "CONTRADICTION_BLOCK",
    "SCHEMA_MISMATCH",
    "GROUNDING_FAILURE",
}


@dataclass(frozen=True)
class GateResult:
    status: str
    reason: str
    executed: bool = False
    executionResult: Any = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _pointer_escape(token: str) -> str:
    return token.replace("~", "~0").replace("/", "~1")


def _read_json(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = path.read_bytes()
    parsed = json.loads(raw.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError("authoritative source must be a JSON object")
    return parsed, raw


def _require_action_schema(schema: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise ValueError("authoritative schema must declare JSON Schema draft 2020-12")
    if not isinstance(schema.get("$id"), str) or not schema["$id"].strip():
        raise ValueError("authoritative schema requires non-empty $id")
    if not isinstance(schema.get("x-source-version"), str) or not schema["x-source-version"].strip():
        raise ValueError("authoritative schema requires non-empty x-source-version")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        raise ValueError("protected action root must be a closed object")
    props = schema.get("properties")
    if not isinstance(props, dict):
        raise ValueError("protected action schema requires properties")
    required = schema.get("required")
    if not isinstance(required, list) or "tool" not in required or "arguments" not in required:
        raise ValueError("protected action schema must require tool and arguments")
    tool_schema = props.get("tool")
    args_schema = props.get("arguments")
    if not isinstance(tool_schema, dict) or not isinstance(tool_schema.get("const"), str):
        raise ValueError("tool must be governed by a string const")
    if not isinstance(args_schema, dict) or args_schema.get("type") != "object":
        raise ValueError("arguments must be an object schema")
    if args_schema.get("additionalProperties") is not False:
        raise ValueError("arguments must set additionalProperties=false")
    if not isinstance(args_schema.get("properties"), dict):
        raise ValueError("arguments schema requires properties")
    if not isinstance(args_schema.get("required", []), list):
        raise ValueError("arguments required must be a list")
    return tool_schema["const"], args_schema


def build_grounding_packet(source_path: Path, proposal: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build the smallest packet needed for one proposed protected action."""
    schema, raw = _read_json(source_path)
    tool_name, args_schema = _require_action_schema(schema)
    all_arg_props: dict[str, Any] = args_schema["properties"]
    required_args = list(args_schema.get("required", []))

    proposed_args: dict[str, Any] = {}
    if proposal is not None and isinstance(proposal.get("arguments"), dict):
        proposed_args = proposal["arguments"]

    selected_names: list[str] = []
    for name in [*required_args, *proposed_args.keys()]:
        if name in all_arg_props and name not in selected_names:
            selected_names.append(name)

    selected_constraints = {name: all_arg_props[name] for name in selected_names}
    source_sha = _sha256(raw)
    field_sources = {"tool": "/properties/tool/const"}
    for name in selected_names:
        field_sources[f"arguments.{name}"] = f"/properties/arguments/properties/{_pointer_escape(name)}"

    return {
        "packetSchema": PACKET_SCHEMA_ID,
        "source": {
            "path": str(source_path),
            "sha256": source_sha,
            "schemaId": schema["$id"],
            "version": schema["x-source-version"],
        },
        "action": {
            "name": tool_name,
            "requiredArguments": required_args,
            "allowedArguments": list(all_arg_props.keys()),
            "argumentConstraints": selected_constraints,
        },
        "criticalFields": ["tool", *[f"arguments.{name}" for name in selected_names]],
        "fieldSources": field_sources,
    }


def _packet_shape_error(packet: Any) -> str | None:
    if not isinstance(packet, dict):
        return "packet_not_object"
    if packet.get("packetSchema") != PACKET_SCHEMA_ID:
        return "packet_schema_id_mismatch"
    for key in ("source", "action", "criticalFields", "fieldSources"):
        if key not in packet:
            return f"packet_missing_{key}"
    source = packet.get("source")
    action = packet.get("action")
    if not isinstance(source, dict) or not isinstance(action, dict):
        return "packet_source_or_action_not_object"
    for key in ("path", "sha256", "schemaId", "version"):
        if not isinstance(source.get(key), str) or not source[key]:
            return f"packet_source_missing_{key}"
    for key in ("name", "requiredArguments", "allowedArguments", "argumentConstraints"):
        if key not in action:
            return f"packet_action_missing_{key}"
    if not isinstance(action["name"], str):
        return "packet_action_name_not_string"
    if not isinstance(action["requiredArguments"], list) or not isinstance(action["allowedArguments"], list):
        return "packet_argument_lists_invalid"
    if not isinstance(action["argumentConstraints"], dict):
        return "packet_constraints_not_object"
    if not isinstance(packet["criticalFields"], list) or not isinstance(packet["fieldSources"], dict):
        return "packet_critical_or_sources_invalid"
    return None


def _proposal_shape_error(proposal: Any) -> str | None:
    if not isinstance(proposal, dict):
        return "proposal_not_object"
    if set(proposal.keys()) != {"tool", "arguments", "provenance"}:
        return "proposal_top_level_shape"
    if not isinstance(proposal.get("tool"), str) or not proposal["tool"]:
        return "proposal_tool_invalid"
    if not isinstance(proposal.get("arguments"), dict):
        return "proposal_arguments_not_object"
    provenance = proposal.get("provenance")
    if not isinstance(provenance, dict):
        return "proposal_provenance_not_object"
    for key in ("sourceSha256", "sourceVersion", "fieldSources"):
        if key not in provenance:
            return f"proposal_provenance_missing_{key}"
    if not isinstance(provenance["sourceSha256"], str) or not isinstance(provenance["sourceVersion"], str):
        return "proposal_source_identity_invalid"
    if not isinstance(provenance["fieldSources"], dict):
        return "proposal_field_sources_not_object"
    return None


def _source_freshness_error(packet: dict[str, Any]) -> str | None:
    source = packet["source"]
    path = Path(source["path"])
    try:
        schema, raw = _read_json(path)
        tool_name, args_schema = _require_action_schema(schema)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        return f"authoritative_source_unavailable_or_invalid:{type(exc).__name__}"
    if _sha256(raw) != source["sha256"]:
        return "stale_source_sha256"
    if schema.get("$id") != source["schemaId"]:
        return "stale_source_schema_id"
    if schema.get("x-source-version") != source["version"]:
        return "stale_source_version"
    if tool_name != packet["action"]["name"]:
        return "stale_tool_identity"
    current_allowed = list(args_schema["properties"].keys())
    if current_allowed != packet["action"]["allowedArguments"]:
        return "stale_argument_surface"
    return None


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "null":
        return value is None
    if expected == "array":
        return isinstance(value, list)
    if expected == "object":
        return isinstance(value, dict)
    return False


def _constraint_error(value: Any, constraint: dict[str, Any]) -> str | None:
    expected_type = constraint.get("type")
    if isinstance(expected_type, str) and not _matches_type(value, expected_type):
        return f"type:{expected_type}"
    if "const" in constraint and value != constraint["const"]:
        return "const"
    enum = constraint.get("enum")
    if isinstance(enum, list) and value not in enum:
        return "enum"
    pattern = constraint.get("pattern")
    if isinstance(pattern, str) and isinstance(value, str):
        try:
            if re.fullmatch(pattern, value) is None:
                return "pattern"
        except re.error:
            return "checker_pattern_invalid"
    if isinstance(value, str):
        if isinstance(constraint.get("minLength"), int) and len(value) < constraint["minLength"]:
            return "minLength"
        if isinstance(constraint.get("maxLength"), int) and len(value) > constraint["maxLength"]:
            return "maxLength"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(constraint.get("minimum"), (int, float)) and value < constraint["minimum"]:
            return "minimum"
        if isinstance(constraint.get("maximum"), (int, float)) and value > constraint["maximum"]:
            return "maximum"
    return None


def gate_proposal(packet: Any, proposal: Any) -> GateResult:
    """Validate a proposed exact action. Never executes anything."""
    packet_error = _packet_shape_error(packet)
    if packet_error:
        return GateResult("GROUNDING_FAILURE", packet_error)
    freshness_error = _source_freshness_error(packet)
    if freshness_error:
        return GateResult("GROUNDING_FAILURE", freshness_error)
    proposal_error = _proposal_shape_error(proposal)
    if proposal_error:
        return GateResult("SCHEMA_MISMATCH", proposal_error)

    source = packet["source"]
    provenance = proposal["provenance"]
    if provenance["sourceSha256"] != source["sha256"] or provenance["sourceVersion"] != source["version"]:
        return GateResult("GROUNDING_FAILURE", "proposal_source_identity_stale")

    if proposal["tool"] != packet["action"]["name"]:
        return GateResult("UNSOURCED_BLOCK", f"tool_not_grounded:{proposal['tool']}")

    allowed = set(packet["action"]["allowedArguments"])
    proposal_args = proposal["arguments"]
    unknown = [name for name in proposal_args if name not in allowed]
    if unknown:
        return GateResult("UNSOURCED_BLOCK", f"argument_not_grounded:{unknown[0]}")

    missing = [name for name in packet["action"]["requiredArguments"] if name not in proposal_args]
    if missing:
        return GateResult("SCHEMA_MISMATCH", f"required_argument_missing:{missing[0]}")

    expected_sources: dict[str, str] = packet["fieldSources"]
    proposed_sources: dict[str, str] = provenance["fieldSources"]
    critical_paths = ["tool", *[f"arguments.{name}" for name in proposal_args]]
    for field in critical_paths:
        expected_pointer = expected_sources.get(field)
        if not expected_pointer or proposed_sources.get(field) != expected_pointer:
            return GateResult("UNSOURCED_BLOCK", f"missing_or_wrong_attribution:{field}")

    constraints = packet["action"]["argumentConstraints"]
    for name, value in proposal_args.items():
        constraint = constraints.get(name)
        if not isinstance(constraint, dict):
            return GateResult("UNSOURCED_BLOCK", f"constraint_not_grounded:{name}")
        violation = _constraint_error(value, constraint)
        if violation == "checker_pattern_invalid":
            return GateResult("GROUNDING_FAILURE", f"checker_failure:{name}:pattern")
        if violation:
            return GateResult("CONTRADICTION_BLOCK", f"constraint_violation:{name}:{violation}")

    return GateResult("GROUNDED_PASS", "deterministic_grounding_gate_passed")


def intercept_and_execute(
    packet: Any,
    proposal: Any,
    executor: Callable[[dict[str, Any]], Any],
) -> GateResult:
    """Host-owned side-effect seam: execute exactly once only after GROUNDED_PASS."""
    result = gate_proposal(packet, proposal)
    if result.status != "GROUNDED_PASS":
        return result
    execution_result = executor(proposal)
    return GateResult("GROUNDED_PASS", result.reason, executed=True, executionResult=execution_result)


def _load(path: str) -> dict[str, Any]:
    parsed = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError(f"expected JSON object: {path}")
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description="Build or evaluate an exact-output grounding packet.")
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build-packet", help="Build compact grounding from a current protected-action JSON Schema.")
    build.add_argument("--schema", required=True)
    build.add_argument("--proposal")
    build.add_argument("--output", required=True)

    gate = sub.add_parser("gate", help="Validate a proposal against a packet and current source identity.")
    gate.add_argument("--packet", required=True)
    gate.add_argument("--proposal", required=True)
    gate.add_argument("--output")

    args = parser.parse_args()
    try:
        if args.command == "build-packet":
            proposal = _load(args.proposal) if args.proposal else None
            packet = build_grounding_packet(Path(args.schema).resolve(), proposal)
            Path(args.output).write_text(json.dumps(packet, indent=2) + "\n", encoding="utf-8")
            print(json.dumps({"status": "GROUNDED_PASS", "packet": str(Path(args.output).resolve())}))
            return 0
        packet = _load(args.packet)
        proposal = _load(args.proposal)
        result = gate_proposal(packet, proposal).to_dict()
        if args.output:
            Path(args.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result))
        return 0 if result["status"] == "GROUNDED_PASS" else 2
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        result = GateResult("GROUNDING_FAILURE", f"grounding_or_checker_failure:{type(exc).__name__}").to_dict()
        if getattr(args, "output", None):
            Path(args.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result))
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
