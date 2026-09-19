#!/usr/bin/env python3
"""Translate one asb.agent-observation/v1 into prompt-kit.routing-request/v1.

This is a read-only translation seam. It does not select prompts, consult a
registry, dispatch prompts, poke terminals, or mutate FirstMate/task state.
Callers provide an already-produced observation plus the routing intent
(mission summary, evidence state, signals) that only ASB correlation knows.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

OBSERVATION_SCHEMA = "asb.agent-observation/v1"
ROUTING_REQUEST_SCHEMA = "prompt-kit.routing-request/v1"
COMPONENT = "prompt-router-client"
VERSION = "1.0.0"

EVENT_RE = re.compile(r"^evt_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
CORR_RE = re.compile(r"^corr_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
GE_RE = re.compile(r"^ge_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

EVIDENCE_STATES = {
    "PLANNED_DESIGNED", "TRACKED", "IMPLEMENTED", "WIRED_REACHABLE",
    "VALIDATED", "INTEGRATED", "DEPLOYED", "OBSERVED",
}
SIGNALS = {
    "routing", "interpretation", "execution", "progression", "durability",
    "premature-terminal", "evidence-promotion", "regression", "environment", "unknown",
}
CORRECTION_KINDS = {
    "corrective_repeat_request", "explicit_correction", "restate_context",
    "restate_constraint", "reroute_owner", "reenumerate_work", "manual_workaround",
    "manual_context_transfer", "restart_conversation", "abandon",
}
EXECUTION_SURFACES = {"regular_ai_prompt", "gnhf_launch_artifact"}


class ContractError(ValueError):
    """Input cannot be translated without inventing contract state."""


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def semantic_sha(message: dict[str, Any]) -> str:
    payload = {k: v for k, v in message.items() if k not in {"eventId", "createdAt", "idempotency"}}
    return sha256_json(payload)


def idem_key(*parts: str) -> str:
    digest = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
    return f"idem_{digest}"


def require_pattern(value: Any, regex: re.Pattern[str], field: str) -> str:
    if not isinstance(value, str) or not regex.fullmatch(value):
        raise ContractError(f"{field} does not satisfy the v1 protocol pattern")
    return value


def require_dict(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{field} must be an object")
    return value


def build_routing_request(
    observation: dict[str, Any],
    *,
    summary: str,
    observed: str,
    claimed: str | None = None,
    execution_surface: str = "regular_ai_prompt",
    signals: list[str] | None = None,
    correction_kinds: list[str] | None = None,
    forbidden_scopes: list[str] | None = None,
    max_candidates: int = 3,
    created_at: str | None = None,
) -> dict[str, Any]:
    if observation.get("schema") != OBSERVATION_SCHEMA:
        raise ContractError(f"observation.schema must be {OBSERVATION_SCHEMA!r}")
    observation_event_id = require_pattern(observation.get("eventId"), EVENT_RE, "observation.eventId")
    correlation_id = require_pattern(observation.get("correlationId"), CORR_RE, "observation.correlationId")
    source = require_dict(observation.get("source"), "observation.source")
    task_id = require_pattern(source.get("taskId"), TASK_RE, "observation.source.taskId")
    repository = require_dict(observation.get("repository"), "observation.repository")
    require_pattern(repository.get("fullName"), REPO_RE, "observation.repository.fullName")
    prompt_context = require_dict(observation.get("promptContext"), "observation.promptContext")
    grounding_episode_id = require_pattern(
        prompt_context.get("groundingEpisodeId"), GE_RE, "observation.promptContext.groundingEpisodeId"
    )

    if not isinstance(summary, str) or not (1 <= len(summary) <= 1200):
        raise ContractError("summary must be 1..1200 characters")
    if observed not in EVIDENCE_STATES:
        raise ContractError(f"observed must be one of {sorted(EVIDENCE_STATES)}")
    if claimed is not None and claimed not in EVIDENCE_STATES:
        raise ContractError("claimed must be a valid evidence state or null")
    if execution_surface not in EXECUTION_SURFACES:
        raise ContractError(f"executionSurface must be one of {sorted(EXECUTION_SURFACES)}")

    signal_list = list(dict.fromkeys(signals or []))
    if len(signal_list) > 24 or any(s not in SIGNALS for s in signal_list):
        raise ContractError("signals must be <=24 unique protocol signal enums")
    correction_events = [{"kind": k, "corrective": True} for k in (correction_kinds or [])]
    if len(correction_events) > 24 or any(k not in CORRECTION_KINDS for k in (correction_kinds or [])):
        raise ContractError("correctionEvents must be <=24 valid correction kinds")
    scope_list = list(forbidden_scopes or [])
    if len(scope_list) > 64 or any(not isinstance(s, str) or len(s) > 240 for s in scope_list):
        raise ContractError("forbiddenScopes must be <=64 strings of <=240 characters")
    if not isinstance(max_candidates, int) or isinstance(max_candidates, bool) or not (1 <= max_candidates <= 3):
        raise ContractError("maxCandidates must be an integer in 1..3")

    evidence_refs = observation.get("evidence")
    if not isinstance(evidence_refs, list):
        raise ContractError("observation.evidence must be an array")
    if any(isinstance(e, dict) and e.get("containsSecrets") is not False for e in evidence_refs):
        raise ContractError("evidence with containsSecrets != false cannot be routed")
    if len(evidence_refs) > 32:
        raise ContractError("evidenceRefs must be <=32 entries")

    message: dict[str, Any] = {
        "schema": ROUTING_REQUEST_SCHEMA,
        "eventId": "",
        "correlationId": correlation_id,
        "causationId": observation_event_id,
        "createdAt": created_at if created_at is not None else observation.get("createdAt"),
        "producer": {"system": "agentswitchboard", "component": COMPONENT, "version": VERSION},
        "observationEventId": observation_event_id,
        "task": {"firstMateTaskId": task_id, "repository": repository},
        "mission": {"groundingEpisodeId": grounding_episode_id, "summary": summary},
        "executionSurface": execution_surface,
        "currentPrompt": prompt_context.get("currentPrompt"),
        "evidenceState": {"observed": observed, "claimed": claimed},
        "signals": signal_list,
        "correctionEvents": correction_events,
        "constraints": {
            "forbiddenScopes": scope_list,
            "evidenceRefs": evidence_refs,
            "rawTranscriptIncluded": False,
        },
        "routingPolicy": {
            "maxCandidates": max_candidates,
            "crossSurfaceFallbackAllowed": False,
            "requireCurrentRegistry": True,
        },
        "idempotency": {"key": "", "semanticSha256": ""},
    }
    semantic = semantic_sha(message)
    message["eventId"] = f"evt_route_{hashlib.sha256((observation_event_id + '|' + semantic).encode('utf-8')).hexdigest()[:24]}"
    message["idempotency"]["key"] = idem_key(
        ROUTING_REQUEST_SCHEMA, observation_event_id, grounding_episode_id, execution_surface
    )
    message["idempotency"]["semanticSha256"] = semantic
    return message


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Translate one asb.agent-observation/v1 JSON document into "
            "prompt-kit.routing-request/v1. The command is read-only."
        )
    )
    parser.add_argument("--observation", required=True, help="Path to asb.agent-observation/v1 JSON")
    parser.add_argument("--summary", required=True, help="Mission summary (1..1200 chars)")
    parser.add_argument("--observed", required=True, help="Observed evidence state")
    parser.add_argument("--claimed", help="Claimed evidence state (optional)")
    parser.add_argument("--execution-surface", default="regular_ai_prompt")
    parser.add_argument("--signal", action="append", default=[], dest="signals")
    parser.add_argument("--correction-event", action="append", default=[], dest="correction_kinds")
    parser.add_argument("--forbidden-scope", action="append", default=[], dest="forbidden_scopes")
    parser.add_argument("--max-candidates", type=int, default=3)
    parser.add_argument("--created-at")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        observation = json.loads(Path(args.observation).read_text(encoding="utf-8-sig"))
        if not isinstance(observation, dict):
            raise ContractError("observation root must be an object")
        message = build_routing_request(
            observation,
            summary=args.summary,
            observed=args.observed,
            claimed=args.claimed,
            execution_surface=args.execution_surface,
            signals=args.signals,
            correction_kinds=args.correction_kinds,
            forbidden_scopes=args.forbidden_scopes,
            max_candidates=args.max_candidates,
            created_at=args.created_at,
        )
    except (OSError, json.JSONDecodeError, ContractError) as exc:
        print(f"fm-asb-routing-request: {exc}", file=sys.stderr)
        return 2

    json.dump(message, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
