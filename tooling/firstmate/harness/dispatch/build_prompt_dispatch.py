#!/usr/bin/env python3
"""Translate one prompt-kit.routing-decision/v1 into asb.prompt-dispatch/v1.

This is a read-only translation seam. It does not select prompts, consult a
registry, deliver prompts to FirstMate, poke terminals, or mutate task state.
Callers provide an already-produced routing decision plus the FirstMate task
identity and the resolved variables that ASB correlation determined.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

DECISION_SCHEMA = "prompt-kit.routing-decision/v1"
DISPATCH_SCHEMA = "asb.prompt-dispatch/v1"
COMPONENT = "firstmate-dispatch-adapter"
VERSION = "1.0.0"

EVENT_RE = re.compile(r"^evt_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
CORR_RE = re.compile(r"^corr_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
PROMPT_ID_RE = re.compile(r"^P[0-9]{2,3}$")
RFC3339_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"
)

ROUTE_ACTIONS_REQUIRING_PROMPT = {"KEEP_CURRENT_PROMPT", "SWITCH_PROMPT"}
ROUTE_ACTIONS_FORBIDDING_DISPATCH = {"NO_ROUTE", "BLOCKED"}
EXECUTION_SURFACES = {"regular_ai_prompt", "gnhf_launch_artifact"}


class ContractError(ValueError):
    """Input cannot be translated without inventing contract state."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def semantic_sha(message: dict[str, Any]) -> str:
    payload = {
        key: value
        for key, value in message.items()
        if key not in {"eventId", "createdAt", "idempotency"}
    }
    return sha256_json(payload)


def idem_key(*parts: str) -> str:
    digest = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
    return f"idem_{digest}"


def delivery_id(*parts: str) -> str:
    """Deterministic deliveryId from identity components."""
    digest = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
    return digest[:16]


def require_pattern(value: Any, regex: re.Pattern[str], field: str) -> str:
    if not isinstance(value, str) or not regex.fullmatch(value):
        raise ContractError(f"{field} does not satisfy the v1 protocol pattern")
    return value


def require_dict(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{field} must be an object")
    return value


def require_rfc3339(value: Any, field: str) -> str:
    if not isinstance(value, str) or not RFC3339_RE.fullmatch(value):
        raise ContractError(f"{field} must be an RFC3339 date-time")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00" if value.endswith("Z") else value)
    except ValueError as exc:
        raise ContractError(f"{field} must be an RFC3339 date-time") from exc
    if parsed.utcoffset() is None:
        raise ContractError(f"{field} must include a timezone")
    return value


def validate_prompt_ref(value: Any, field: str) -> dict[str, Any]:
    """Validate and normalize a promptRef, fail-closed on null for required actions."""
    if value is None:
        raise ContractError(f"{field} must not be null for this route action")
    prompt = require_dict(value, field)
    required = {"id", "kitVersion", "registrySha256", "promptSha256", "executionSurface"}
    missing = required - set(prompt)
    if missing:
        raise ContractError(f"{field} is missing required fields: {sorted(missing)}")
    extras = set(prompt) - required
    if extras:
        raise ContractError(f"{field} contains unsupported fields: {sorted(extras)}")
    require_pattern(prompt.get("id"), PROMPT_ID_RE, f"{field}.id")
    kit_version = prompt.get("kitVersion")
    if not isinstance(kit_version, str) or not (1 <= len(kit_version) <= 64):
        raise ContractError(f"{field}.kitVersion must be a string of 1..64 characters")
    require_pattern(prompt.get("registrySha256"), SHA256_RE, f"{field}.registrySha256")
    require_pattern(prompt.get("promptSha256"), SHA256_RE, f"{field}.promptSha256")
    if prompt.get("executionSurface") not in EXECUTION_SURFACES:
        raise ContractError(f"{field}.executionSurface must be a protocol execution surface")
    return dict(prompt)


def validate_resolved_variables(value: Any, field: str) -> dict[str, Any]:
    """Validate resolvedVariables object."""
    if not isinstance(value, dict):
        raise ContractError(f"{field} must be an object")
    if len(value) > 64:
        raise ContractError(f"{field} must have <=64 properties")
    for key, val in value.items():
        if not isinstance(key, str):
            raise ContractError(f"{field} keys must be strings")
        if not isinstance(val, (str, int, float, bool, type(None))):
            raise ContractError(f"{field}[{key}] must be string, number, boolean, or null")
        if isinstance(val, str) and len(val) > 4000:
            raise ContractError(f"{field}[{key}] string exceeds 4000 characters")
    return dict(value)


def validate_allowed_scopes(value: Any, field: str) -> list[str]:
    """Validate allowedScopes array."""
    if not isinstance(value, list):
        raise ContractError(f"{field} must be an array")
    if len(value) > 64:
        raise ContractError(f"{field} must be <=64 items")
    result = []
    for item in value:
        if not isinstance(item, str) or len(item) > 240:
            raise ContractError(f"{field} items must be strings of <=240 characters")
        result.append(item)
    return result


def validate_forbidden_scopes(value: Any, field: str) -> list[str]:
    """Validate forbiddenScopes array."""
    if not isinstance(value, list):
        raise ContractError(f"{field} must be an array")
    if len(value) > 64:
        raise ContractError(f"{field} must be <=64 items")
    result = []
    for item in value:
        if not isinstance(item, str) or len(item) > 240:
            raise ContractError(f"{field} items must be strings of <=240 characters")
        result.append(item)
    return result


def build_prompt_dispatch(
    decision: dict[str, Any],
    *,
    firstmate_task_id: str,
    resolved_variables: dict[str, Any] | None = None,
    instruction_summary: str,
    proof_gate: str,
    allow_mutation: bool = True,
    allowed_scopes: list[str] | None = None,
    forbidden_scopes: list[str] | None = None,
    expected_generation: int | None = None,
    created_at: str | None = None,
) -> dict[str, Any]:
    """Build asb.prompt-dispatch/v1 from a routing-decision.

    Args:
        decision: A valid prompt-kit.routing-decision/v1 document.
        firstmate_task_id: The FirstMate task identifier.
        resolved_variables: Variable bindings (optional, defaults to empty).
        instruction_summary: The instruction packet summary (1..4000 chars).
        proof_gate: The proof gate text (1..4000 chars).
        allow_mutation: Whether mutation is allowed (default True).
        allowed_scopes: Allowed scope patterns (optional).
        forbidden_scopes: Forbidden scope patterns (optional).
        expected_generation: Expected task generation (optional).
        created_at: RFC3339 timestamp (optional, defaults to decision.createdAt).

    Returns:
        A valid asb.prompt-dispatch/v1 message.

    Raises:
        ContractError: If the decision cannot be dispatched or inputs are invalid.
    """
    if decision.get("schema") != DECISION_SCHEMA:
        raise ContractError(f"decision.schema must be {DECISION_SCHEMA!r}")

    decision_event_id = require_pattern(decision.get("eventId"), EVENT_RE, "decision.eventId")
    correlation_id = require_pattern(decision.get("correlationId"), CORR_RE, "decision.correlationId")
    require_rfc3339(decision.get("createdAt"), "decision.createdAt")

    routing_decision_event_id = require_pattern(
        decision.get("routingRequestEventId"), EVENT_RE, "decision.routingRequestEventId"
    )

    decision_obj = require_dict(decision.get("decision"), "decision.decision")
    route_action = decision_obj.get("routeAction")
    if route_action not in (ROUTE_ACTIONS_REQUIRING_PROMPT | ROUTE_ACTIONS_FORBIDDING_DISPATCH):
        raise ContractError(f"decision.routeAction must be a valid protocol action")

    # Fail-closed: NO_ROUTE and BLOCKED cannot be dispatched
    if route_action in ROUTE_ACTIONS_FORBIDDING_DISPATCH:
        raise ContractError(
            f"Cannot dispatch prompt for routeAction={route_action}; no prompt is routed"
        )

    # Fail-closed: KEEP_CURRENT_PROMPT and SWITCH_PROMPT require primaryPrompt
    primary_prompt = decision_obj.get("primaryPrompt")
    if route_action in ROUTE_ACTIONS_REQUIRING_PROMPT:
        if primary_prompt is None:
            raise ContractError(
                f"decision.primaryPrompt must not be null for routeAction={route_action}"
            )

    prompt_ref = validate_prompt_ref(primary_prompt, "decision.primaryPrompt")
    prompt_sha256 = prompt_ref["promptSha256"]

    # Validate inputs
    require_pattern(firstmate_task_id, TASK_RE, "firstmate_task_id")
    variables = validate_resolved_variables(
        resolved_variables if resolved_variables is not None else {}, "resolved_variables"
    )

    if not isinstance(instruction_summary, str) or not (1 <= len(instruction_summary) <= 4000):
        raise ContractError("instruction_summary must be 1..4000 characters")
    if not isinstance(proof_gate, str) or not (1 <= len(proof_gate) <= 4000):
        raise ContractError("proof_gate must be 1..4000 characters")

    if not isinstance(allow_mutation, bool):
        raise ContractError("allow_mutation must be boolean")

    allowed = validate_allowed_scopes(allowed_scopes if allowed_scopes is not None else [], "allowed_scopes")
    forbidden = validate_forbidden_scopes(
        forbidden_scopes if forbidden_scopes is not None else [], "forbidden_scopes"
    )

    if expected_generation is not None:
        # bool is an int subclass but is not a protocol integer
        if isinstance(expected_generation, bool) or not isinstance(expected_generation, int):
            raise ContractError("expected_generation must be an integer or null")
        if expected_generation < 0:
            raise ContractError("expected_generation must be >= 0")

    output_created_at = require_rfc3339(
        created_at if created_at is not None else decision.get("createdAt"),
        "dispatch.createdAt",
    )

    # Build idempotency key and deliveryId from deterministic identity
    idem = idem_key(DISPATCH_SCHEMA, decision_event_id, firstmate_task_id, prompt_sha256)
    delivery = delivery_id(DISPATCH_SCHEMA, decision_event_id, firstmate_task_id, prompt_sha256)

    message: dict[str, Any] = {
        "schema": DISPATCH_SCHEMA,
        "eventId": "",
        "correlationId": correlation_id,
        "causationId": decision_event_id,
        "createdAt": output_created_at,
        "producer": {
            "system": "agentswitchboard",
            "component": COMPONENT,
            "version": VERSION,
        },
        "routingDecisionEventId": decision_event_id,
        "target": {
            "firstMateTaskId": firstmate_task_id,
            "expectedGeneration": expected_generation,
            "deliveryPlane": "durable-inbox",
        },
        "prompt": {
            "ref": prompt_ref,
            "deliveryMode": "reference",
            "inlineText": None,
        },
        "resolvedVariables": variables,
        "instructionPacket": {
            "summary": instruction_summary,
            "proofGate": proof_gate,
            "evidenceRefs": [],
        },
        "authority": {
            "allowMutation": allow_mutation,
            "allowedScopes": allowed,
            "forbiddenScopes": forbidden,
        },
        "delivery": {
            "deliveryId": delivery,
            "expectsReply": True,
            "resolveKeys": [],
        },
        "expectedResult": {
            "acceptedStates": ["running", "needs-decision", "blocked", "completed", "failed"],
            "coordinatorValidationRequired": True,
        },
        "idempotency": {
            "key": idem,
            "semanticSha256": "",
        },
    }

    semantic = semantic_sha(message)
    message["eventId"] = f"evt_dispatch_{hashlib.sha256((decision_event_id + '|' + semantic).encode('utf-8')).hexdigest()[:24]}"
    message["idempotency"]["semanticSha256"] = semantic

    return message


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Translate one prompt-kit.routing-decision/v1 JSON document into "
            "asb.prompt-dispatch/v1. The command is read-only."
        )
    )
    parser.add_argument("--decision", required=True, help="Path to prompt-kit.routing-decision/v1 JSON")
    parser.add_argument("--firstmate-task-id", required=True, help="FirstMate task identifier")
    parser.add_argument("--instruction-summary", required=True, help="Instruction packet summary (1..4000 chars)")
    parser.add_argument("--proof-gate", required=True, help="Proof gate text (1..4000 chars)")
    parser.add_argument("--allow-mutation", type=bool, default=True, help="Allow mutation (default True)")
    parser.add_argument("--allowed-scope", action="append", default=[], dest="allowed_scopes")
    parser.add_argument("--forbidden-scope", action="append", default=[], dest="forbidden_scopes")
    parser.add_argument("--expected-generation", type=int, help="Expected task generation (optional)")
    parser.add_argument("--created-at", help="RFC3339 timestamp (optional)")
    parser.add_argument("--var", action="append", default=[], dest="variables", help="key=value pairs")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        decision = json.loads(Path(args.decision).read_text(encoding="utf-8-sig"))
        if not isinstance(decision, dict):
            raise ContractError("decision root must be an object")

        # Parse variables from key=value pairs
        resolved_variables = {}
        for var in args.variables:
            if "=" not in var:
                raise ContractError(f"Variable must be key=value format: {var}")
            key, value = var.split("=", 1)
            # Try to parse as JSON value
            try:
                resolved_variables[key] = json.loads(value)
            except json.JSONDecodeError:
                # Treat as string
                resolved_variables[key] = value

        message = build_prompt_dispatch(
            decision,
            firstmate_task_id=args.firstmate_task_id,
            resolved_variables=resolved_variables if resolved_variables else None,
            instruction_summary=args.instruction_summary,
            proof_gate=args.proof_gate,
            allow_mutation=args.allow_mutation,
            allowed_scopes=args.allowed_scopes,
            forbidden_scopes=args.forbidden_scopes,
            expected_generation=args.expected_generation,
            created_at=args.created_at,
        )
    except (OSError, json.JSONDecodeError, ContractError) as exc:
        print(f"fm-asb-prompt-dispatch: {exc}", file=sys.stderr)
        return 2

    json.dump(message, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
