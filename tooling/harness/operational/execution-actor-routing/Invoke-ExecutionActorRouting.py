#!/usr/bin/env python3
"""Fail-closed execution actor binding and verification for AgentSwitchboard harness work."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

EXPLICIT_ACTORS = {"chatgpt", "agentswitchboard", "operator"}
REQUESTED_ACTORS = EXPLICIT_ACTORS | {"auto"}
SOURCES = {"user-explicit", "task-contract", "context-inferred"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def default_root() -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return Path(tempfile.gettempdir()) / "AgentSwitchboard" / "execution-actor-routing" / f"{stamp}-{os.getpid()}"


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def digest_json(payload: dict) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def render_report(root: Path, state: dict, phase: str) -> Path:
    path = root / "execution-actor-operator-report.md"
    if phase == "bind":
        ok = state["status"] == "actor-bound"
        working = (
            f"Requested actor `{state['requestedActor']}` is bound to selected actor `{state['selectedActor']}`."
            if ok
            else f"Requested actor `{state['requestedActor']}` does not match selected actor `{state['selectedActor']}`."
        )
        missing = "Execution evidence and actual-actor verification." if ok else "A valid actor binding."
        next_action = (
            f"Execute `{state['operation']}` through `{state['selectedActor']}`, then verify the resulting actor-owned evidence."
            if ok
            else "Do not execute. Re-bind with the requested actor or obtain a new actor-selection decision."
        )
    else:
        ok = state["status"] == "actor-verified"
        working = (
            f"Actual actor `{state['actualActor']}` matches selected actor `{state['selectedActor']}`."
            if ok
            else f"Actual actor `{state['actualActor']}` does not match selected actor `{state['selectedActor']}`."
        )
        missing = "None for actor identity routing." if ok else "Valid proof that the selected actor performed the operation."
        next_action = (
            "Continue the owning repository workflow; validate the underlying operation with its own evidence."
            if ok
            else "Do not claim completion for the requested actor. Preserve this receipt and repair the routing mismatch."
        )

    path.write_text(
        "\n".join([
            "# AgentSwitchboard Execution Actor Routing",
            "",
            f"- Status: {state['status']}",
            f"- Requested actor: {state['requestedActor']}",
            f"- Selected actor: {state['selectedActor']}",
            f"- Task: {state['task']}",
            f"- Operation: {state['operation']}",
            "",
            "## Working",
            "",
            working,
            "",
            "## Broken",
            "",
            "None." if ok else "Execution actor continuity failed.",
            "",
            "## Missing",
            "",
            missing,
            "",
            "## Next action",
            "",
            next_action,
            "",
            "## Proof ceiling",
            "",
            "This report proves only execution-actor routing state. It does not prove authorization, correctness, mergeability, deployment, or acceptance of the underlying operation.",
            "",
        ]) + "\n",
        encoding="utf-8",
    )
    return path


def bind(args: argparse.Namespace) -> int:
    if args.requested_actor not in REQUESTED_ACTORS:
        raise ValueError("unsupported requested actor")
    if args.selected_actor not in EXPLICIT_ACTORS:
        raise ValueError("unsupported selected actor")
    if args.selection_source not in SOURCES:
        raise ValueError("unsupported selection source")
    if args.requested_actor != "auto" and args.selected_actor != args.requested_actor:
        status = "actor-mismatch"
    else:
        status = "actor-bound"
    if args.requested_actor == "auto" and not (args.selection_reason or "").strip():
        raise ValueError("--selection-reason is required when --requested-actor auto")
    if args.selection_source == "user-explicit" and args.requested_actor == "auto":
        raise ValueError("user-explicit selection source cannot use requested actor auto")

    root = Path(args.output_root).expanduser().resolve() if args.output_root else default_root()
    root.mkdir(parents=True, exist_ok=True)
    binding = {
        "schemaVersion": 1,
        "runId": root.name,
        "status": status,
        "requestedActor": args.requested_actor,
        "selectedActor": args.selected_actor,
        "selectionSource": args.selection_source,
        "selectionReason": (args.selection_reason or "").strip() or None,
        "task": args.task.strip(),
        "operation": args.operation.strip(),
        "boundAtUtc": utc_now(),
    }
    binding_path = root / "execution-actor-binding.json"
    write_json(binding_path, binding)
    report_path = render_report(root, binding, "bind")
    print(f"STATUS={status}")
    print(f"BINDING={binding_path}")
    print(f"REPORT={report_path}")
    print(f"SELECTED_ACTOR={args.selected_actor}")
    return 0 if status == "actor-bound" else 9


def verify(args: argparse.Namespace) -> int:
    binding_path = Path(args.binding).expanduser().resolve()
    binding = json.loads(binding_path.read_text(encoding="utf-8"))
    required = {"schemaVersion", "runId", "status", "requestedActor", "selectedActor", "selectionSource", "task", "operation", "boundAtUtc"}
    missing = sorted(required - set(binding))
    if missing:
        raise ValueError(f"binding missing required keys: {', '.join(missing)}")
    if binding["status"] != "actor-bound":
        raise ValueError("binding is not actor-bound")
    if args.actual_actor not in EXPLICIT_ACTORS:
        raise ValueError("unsupported actual actor")
    evidence = (args.evidence or "").strip()
    if not evidence:
        raise ValueError("--evidence is required for verification")

    status = "actor-verified" if args.actual_actor == binding["selectedActor"] else "actor-mismatch"
    receipt = {
        "schemaVersion": 1,
        "runId": binding["runId"],
        "status": status,
        "requestedActor": binding["requestedActor"],
        "selectedActor": binding["selectedActor"],
        "actualActor": args.actual_actor,
        "selectionSource": binding["selectionSource"],
        "task": binding["task"],
        "operation": binding["operation"],
        "bindingSha256": digest_json(binding),
        "evidence": evidence,
        "verifiedAtUtc": utc_now(),
    }
    root = binding_path.parent
    receipt_path = root / "execution-actor-receipt.json"
    write_json(receipt_path, receipt)
    report_path = render_report(root, receipt, "verify")
    print(f"STATUS={status}")
    print(f"RECEIPT={receipt_path}")
    print(f"REPORT={report_path}")
    return 0 if status == "actor-verified" else 10


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Bind and verify the execution actor for an AgentSwitchboard operation.")
    sub = p.add_subparsers(dest="command", required=True)

    b = sub.add_parser("bind", help="Bind requested actor to selected actor before mutation.")
    b.add_argument("--requested-actor", required=True, choices=sorted(REQUESTED_ACTORS))
    b.add_argument("--selected-actor", required=True, choices=sorted(EXPLICIT_ACTORS))
    b.add_argument("--selection-source", required=True, choices=sorted(SOURCES))
    b.add_argument("--selection-reason")
    b.add_argument("--task", required=True)
    b.add_argument("--operation", required=True)
    b.add_argument("--output-root")
    b.set_defaults(func=bind)

    v = sub.add_parser("verify", help="Verify that the actual actor matches the selected actor.")
    v.add_argument("--binding", required=True)
    v.add_argument("--actual-actor", required=True, choices=sorted(EXPLICIT_ACTORS))
    v.add_argument("--evidence", required=True)
    v.set_defaults(func=verify)
    return p


def main() -> int:
    args = parser().parse_args()
    try:
        return args.func(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR={exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
