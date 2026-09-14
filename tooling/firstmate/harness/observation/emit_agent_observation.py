#!/usr/bin/env python3
"""Translate one FirstMate fleet-snapshot task into asb.agent-observation/v1.

This is a read-only translation seam. It does not start a watcher, invoke
FirstMate, read pane text, route Prompt Kit prompts, or mutate repository/task
state. Callers provide an already-produced `fm-fleet-snapshot.v1` document.
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

SNAPSHOT_SCHEMA = "fm-fleet-snapshot.v1"
OBSERVATION_SCHEMA = "asb.agent-observation/v1"
COMPONENT = "firstmate-observation-adapter"
VERSION = "1.0.0"

CORRELATION_RE = re.compile(r"^corr_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
GROUNDING_RE = re.compile(r"^ge_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
EVENT_RE = re.compile(r"^evt_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA40_RE = re.compile(r"^[a-f0-9]{40}$")

PHASE_BY_FIRSTMATE_STATE = {
    "working": "running",
    "idle": "paused",
    "parked": "paused",
    "paused": "paused",
    "blocked": "blocked",
    "done": "completed",
    "failed": "failed",
    "queued": "queued",
    "unknown": "unknown",
}
TASK_KINDS = {"ship", "scout", "secondmate"}
TERMINAL_PHASES = {"completed", "failed"}


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


def parse_rfc3339(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ContractError(f"{field} must be a non-empty RFC3339 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ContractError(f"{field} is not RFC3339: {value!r}") from exc
    if parsed.tzinfo is None:
        raise ContractError(f"{field} must include a timezone")
    return value


def require_pattern(value: str | None, regex: re.Pattern[str], field: str) -> str:
    if value is None or not regex.fullmatch(value):
        raise ContractError(f"{field} does not satisfy the v1 protocol pattern")
    return value


def parse_generation(value: Any) -> int | None:
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def worktree_id(task_id: str, task: dict[str, Any]) -> str | None:
    paths = task.get("paths")
    if not isinstance(paths, dict):
        return None
    worktree = paths.get("worktree")
    if not isinstance(worktree, dict):
        return None
    path = worktree.get("path")
    if not isinstance(path, str) or not path:
        return None
    digest = hashlib.sha256(path.encode("utf-8")).hexdigest()[:16]
    return f"fm_{task_id}_{digest}"


def safe_task_projection(task: dict[str, Any]) -> dict[str, Any]:
    """Return only non-transcript, non-path state used to identify an observation."""
    current = task.get("current_state")
    current = current if isinstance(current, dict) else {}
    hints = task.get("hints")
    hints = hints if isinstance(hints, dict) else {}
    endpoint = task.get("endpoint")
    endpoint = endpoint if isinstance(endpoint, dict) else {}
    paths = task.get("paths")
    paths = paths if isinstance(paths, dict) else {}
    worktree = paths.get("worktree")
    worktree = worktree if isinstance(worktree, dict) else {}
    report = paths.get("report")
    report = report if isinstance(report, dict) else {}

    open_decisions = []
    raw_decisions = hints.get("open_decisions")
    if isinstance(raw_decisions, list):
        for decision in raw_decisions:
            if not isinstance(decision, dict):
                continue
            open_decisions.append({"key": decision.get("key"), "verb": decision.get("verb")})

    return {
        "id": task.get("id"),
        "kind": task.get("kind"),
        "harness": task.get("harness"),
        "backend": task.get("backend"),
        "spawn_gen": task.get("spawn_gen"),
        "current_state": {
            "state": current.get("state"),
            "source": current.get("source"),
            "freshness": current.get("freshness"),
        },
        "endpoint": {
            "exists": endpoint.get("exists"),
            "agent_alive": endpoint.get("agent_alive"),
            "status": endpoint.get("status"),
        },
        "hints": {
            "pending_decision": bool(hints.get("pending_decision")),
            "blocked_event": bool(hints.get("blocked_event")),
            "open_decisions": open_decisions,
            "scout_report_present": bool(hints.get("scout_report_present")),
        },
        "paths": {
            "worktree_present": worktree.get("present"),
            "report_present": report.get("present"),
        },
    }


def phase_for(task: dict[str, Any]) -> str:
    current = task.get("current_state")
    current = current if isinstance(current, dict) else {}
    hints = task.get("hints")
    hints = hints if isinstance(hints, dict) else {}

    if bool(hints.get("pending_decision")):
        return "needs-decision"
    decisions = hints.get("open_decisions")
    if isinstance(decisions, list) and any(
        isinstance(item, dict) and item.get("verb") == "needs-decision" for item in decisions
    ):
        return "needs-decision"

    state = current.get("state")
    if bool(hints.get("blocked_event")) or state == "blocked":
        return "blocked"
    if not isinstance(state, str):
        return "unknown"
    return PHASE_BY_FIRSTMATE_STATE.get(state, "unknown")


def select_task(snapshot: dict[str, Any], task_id: str) -> dict[str, Any]:
    if snapshot.get("schema") != SNAPSHOT_SCHEMA:
        raise ContractError(
            f"snapshot.schema must be {SNAPSHOT_SCHEMA!r}; got {snapshot.get('schema')!r}"
        )
    tasks = snapshot.get("tasks")
    if not isinstance(tasks, list):
        raise ContractError("snapshot.tasks must be an array")
    matches = [task for task in tasks if isinstance(task, dict) and task.get("id") == task_id]
    if len(matches) != 1:
        raise ContractError(f"expected exactly one task {task_id!r} in snapshot; found {len(matches)}")
    return matches[0]


def build_observation(
    snapshot: dict[str, Any],
    *,
    task_id: str,
    repository_full_name: str,
    branch: str | None,
    head_sha: str | None,
    correlation_id: str,
    grounding_episode_id: str,
    causation_id: str | None,
) -> dict[str, Any]:
    require_pattern(task_id, TASK_RE, "task_id")
    require_pattern(repository_full_name, REPO_RE, "repository_full_name")
    require_pattern(correlation_id, CORRELATION_RE, "correlation_id")
    require_pattern(grounding_episode_id, GROUNDING_RE, "grounding_episode_id")
    if causation_id is not None:
        require_pattern(causation_id, EVENT_RE, "causation_id")
    if head_sha is not None:
        require_pattern(head_sha, SHA40_RE, "head_sha")

    task = select_task(snapshot, task_id)
    generated = parse_rfc3339(snapshot.get("generated"), "snapshot.generated")
    projection = safe_task_projection(task)
    projection_sha = sha256_json(projection)
    event_material = f"{generated}|{projection_sha}"
    event_digest = hashlib.sha256(event_material.encode("utf-8")).hexdigest()
    event_key = f"snapshot-{event_digest[:32]}-{task_id}"
    event_id = f"evt_fmobs_{event_digest[:24]}"

    phase = phase_for(task)
    task_kind = task.get("kind")
    if task_kind not in TASK_KINDS:
        task_kind = "unknown"
    harness = task.get("harness")
    if not isinstance(harness, str) or not harness:
        harness = None
    backend = task.get("backend")
    if not isinstance(backend, str) or not backend:
        backend = None

    message: dict[str, Any] = {
        "schema": OBSERVATION_SCHEMA,
        "eventId": event_id,
        "correlationId": correlation_id,
        "causationId": causation_id,
        "createdAt": generated,
        "producer": {
            "system": "agentswitchboard",
            "component": COMPONENT,
            "version": VERSION,
        },
        "idempotency": {
            "key": idem_key(OBSERVATION_SCHEMA, task_id, event_key),
            "semanticSha256": "",
        },
        "source": {
            "system": "firstmate",
            "taskId": task_id,
            "eventKey": event_key,
            "eventType": (
                "task-terminal"
                if phase in TERMINAL_PHASES
                else "needs-decision" if phase == "needs-decision" else "task-status"
            ),
            "taskKind": task_kind,
            "harness": harness,
            "backend": backend,
            "generation": parse_generation(task.get("spawn_gen")),
        },
        "repository": {
            "fullName": repository_full_name,
            "branch": branch,
            "headSha": head_sha,
            "worktreeId": worktree_id(task_id, task),
        },
        "state": {
            "phase": phase,
            "terminal": phase in TERMINAL_PHASES,
            "statusKey": f"firstmate:{phase}",
        },
        "output": {
            "format": "none",
            "rawIncluded": False,
            "sha256": None,
            "artifactRef": None,
            "recordCount": 0,
        },
        "evidence": [
            {
                "kind": "firstmate-state",
                "ref": f"urn:firstmate:normalized-task-state:{projection_sha}",
                "sha256": projection_sha,
                "containsRawUserText": False,
                "containsSecrets": False,
            }
        ],
        "promptContext": {
            "groundingEpisodeId": grounding_episode_id,
            "currentPrompt": None,
            "currentDispatchEventId": None,
        },
        # Context pressure is a later phase with its own verified adapter.
        "contextPressure": None,
    }
    message["idempotency"]["semanticSha256"] = semantic_sha(message)
    return message


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Translate one task from an existing fm-fleet-snapshot.v1 JSON document "
            "into asb.agent-observation/v1. The command is read-only."
        )
    )
    parser.add_argument("--snapshot", required=True, help="Path to fm-fleet-snapshot.v1 JSON")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--repository-full-name", required=True, help="owner/name")
    parser.add_argument("--branch")
    parser.add_argument("--head-sha")
    parser.add_argument("--correlation-id", required=True)
    parser.add_argument("--grounding-episode-id", required=True)
    parser.add_argument("--causation-id")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        snapshot_path = Path(args.snapshot)
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8-sig"))
        if not isinstance(snapshot, dict):
            raise ContractError("snapshot root must be an object")
        message = build_observation(
            snapshot,
            task_id=args.task_id,
            repository_full_name=args.repository_full_name,
            branch=args.branch,
            head_sha=args.head_sha,
            correlation_id=args.correlation_id,
            grounding_episode_id=args.grounding_episode_id,
            causation_id=args.causation_id,
        )
    except (OSError, json.JSONDecodeError, ContractError) as exc:
        print(f"fm-asb-observation: {exc}", file=sys.stderr)
        return 2

    json.dump(message, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
