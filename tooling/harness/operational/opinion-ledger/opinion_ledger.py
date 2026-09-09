#!/usr/bin/env python3
"""Local-only candidate opinion ledger tracer for AgentSwitchboard."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import sys
from typing import Iterable

SCHEMA_VERSION = "agentswitchboard.opinion-entry.v1"
SOURCE_TYPES = ("operator", "chat", "repository", "review", "other")
CONFIDENCE_LEVELS = ("low", "medium", "high")
VISIBILITY = "local-only"
STATUS = "candidate"


class OpinionLedgerError(RuntimeError):
    pass


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def resolve_state_root(explicit: str | None = None) -> pathlib.Path:
    if explicit:
        return pathlib.Path(explicit).expanduser()

    override = os.environ.get("AGENTSWITCHBOARD_OPINION_STATE_ROOT")
    if override:
        return pathlib.Path(override).expanduser()

    if os.name == "nt":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if not local_app_data:
            raise OpinionLedgerError(
                "LOCALAPPDATA is unavailable; refusing to invent a Windows opinion-ledger state path"
            )
        return pathlib.Path(local_app_data) / "AgentSwitchboard" / "opinion-ledger"

    xdg_state_home = os.environ.get("XDG_STATE_HOME")
    if xdg_state_home:
        return pathlib.Path(xdg_state_home).expanduser() / "agentswitchboard" / "opinion-ledger"

    return pathlib.Path.home() / ".local" / "state" / "agentswitchboard" / "opinion-ledger"


def ledger_path(state_root: pathlib.Path) -> pathlib.Path:
    return state_root / "opinions.jsonl"


def _prepare_private_path(state_root: pathlib.Path) -> pathlib.Path:
    state_root.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        try:
            state_root.chmod(0o700)
        except OSError:
            pass

    path = ledger_path(state_root)
    if not path.exists():
        path.touch(exist_ok=False)
    if os.name != "nt":
        try:
            path.chmod(0o600)
        except OSError:
            pass
    return path


def _normalize_tags(tags: Iterable[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for raw in tags:
        value = raw.strip()
        if not value:
            continue
        key = value.casefold()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(value)
    if len(normalized) > 20:
        raise OpinionLedgerError("at most 20 tags are allowed")
    return normalized


def _validate_text(value: str, label: str, maximum: int) -> str:
    normalized = value.strip()
    if not normalized:
        raise OpinionLedgerError(f"{label} must not be empty")
    if len(normalized) > maximum:
        raise OpinionLedgerError(f"{label} exceeds {maximum} characters")
    return normalized


def _record_digest(payload: dict) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def build_entry(
    *,
    text: str,
    scope: str,
    source_type: str,
    source_ref: str | None,
    confidence: str,
    tags: Iterable[str],
) -> dict:
    if source_type not in SOURCE_TYPES:
        raise OpinionLedgerError(f"unsupported source_type: {source_type}")
    if confidence not in CONFIDENCE_LEVELS:
        raise OpinionLedgerError(f"unsupported confidence: {confidence}")

    created_at = _utc_now()
    body = {
        "schema_version": SCHEMA_VERSION,
        "created_at": created_at,
        "text": _validate_text(text, "text", 4000),
        "scope": _validate_text(scope, "scope", 160),
        "source_type": source_type,
        "source_ref": source_ref.strip() if source_ref and source_ref.strip() else None,
        "confidence": confidence,
        "tags": _normalize_tags(tags),
        "visibility": VISIBILITY,
        "status": STATUS,
        "advisory_only": True,
        "execution_authority": False,
        "promoted_owner": None,
    }
    body["opinion_id"] = f"opn-{_record_digest(body)[:20]}"
    return body


def validate_entry(entry: object, *, line_number: int | None = None) -> dict:
    prefix = f"line {line_number}: " if line_number else ""
    if not isinstance(entry, dict):
        raise OpinionLedgerError(prefix + "entry must be an object")

    required = {
        "schema_version",
        "opinion_id",
        "created_at",
        "text",
        "scope",
        "source_type",
        "source_ref",
        "confidence",
        "tags",
        "visibility",
        "status",
        "advisory_only",
        "execution_authority",
        "promoted_owner",
    }
    missing = sorted(required.difference(entry))
    if missing:
        raise OpinionLedgerError(prefix + "missing required field(s): " + ", ".join(missing))
    if entry["schema_version"] != SCHEMA_VERSION:
        raise OpinionLedgerError(prefix + "unsupported schema_version")
    if entry["visibility"] != VISIBILITY or entry["status"] != STATUS:
        raise OpinionLedgerError(prefix + "only local-only candidate entries are accepted")
    if entry["advisory_only"] is not True or entry["execution_authority"] is not False:
        raise OpinionLedgerError(prefix + "opinion entries must remain advisory and non-authoritative")
    if entry["promoted_owner"] is not None:
        raise OpinionLedgerError(prefix + "promotion is not owned by the tracer")
    if entry["source_type"] not in SOURCE_TYPES:
        raise OpinionLedgerError(prefix + "invalid source_type")
    if entry["confidence"] not in CONFIDENCE_LEVELS:
        raise OpinionLedgerError(prefix + "invalid confidence")
    if not isinstance(entry["tags"], list) or any(not isinstance(tag, str) for tag in entry["tags"]):
        raise OpinionLedgerError(prefix + "tags must be an array of strings")
    _validate_text(str(entry["text"]), "text", 4000)
    _validate_text(str(entry["scope"]), "scope", 160)
    return entry


def append_entry(path: pathlib.Path, entry: dict) -> None:
    validate_entry(entry)
    serialized = json.dumps(entry, sort_keys=True, ensure_ascii=False)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(serialized + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def load_entries(path: pathlib.Path) -> list[dict]:
    if not path.exists():
        return []
    entries: list[dict] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            if not raw.strip():
                continue
            try:
                parsed = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise OpinionLedgerError(f"line {line_number}: malformed JSON: {exc.msg}") from exc
            entries.append(validate_entry(parsed, line_number=line_number))
    return entries


def search_entries(entries: Iterable[dict], query: str, limit: int) -> list[dict]:
    if limit < 1 or limit > 100:
        raise OpinionLedgerError("limit must be between 1 and 100")
    needle = _validate_text(query, "query", 500).casefold()
    matches: list[dict] = []
    for entry in entries:
        haystack = " ".join([entry["text"], entry["scope"], " ".join(entry["tags"])]).casefold()
        if needle in haystack:
            matches.append(entry)
    return list(reversed(matches))[:limit]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state-root",
        help="explicit local state root; intended for deterministic operator/test isolation",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    record = commands.add_parser("record", help="append one local-only candidate opinion")
    record.add_argument("--text", required=True)
    record.add_argument("--scope", required=True)
    record.add_argument("--source-type", choices=SOURCE_TYPES, default="operator")
    record.add_argument("--source-ref")
    record.add_argument("--confidence", choices=CONFIDENCE_LEVELS, default="medium")
    record.add_argument("--tag", action="append", default=[])

    search = commands.add_parser("search", help="search candidate opinions by literal text")
    search.add_argument("--query", required=True)
    search.add_argument("--limit", type=int, default=20)

    commands.add_parser("state-root", help="print the resolved local state root without mutating it")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        state_root = resolve_state_root(args.state_root)
        if args.command == "state-root":
            print(json.dumps({"state_root": str(state_root), "storage": "local-only"}, sort_keys=True))
            return 0

        path = ledger_path(state_root)
        if args.command == "record":
            entry = build_entry(
                text=args.text,
                scope=args.scope,
                source_type=args.source_type,
                source_ref=args.source_ref,
                confidence=args.confidence,
                tags=args.tag,
            )
            path = _prepare_private_path(state_root)
            append_entry(path, entry)
            print(json.dumps({"recorded": True, "path": str(path), "entry": entry}, sort_keys=True))
            return 0

        if args.command == "search":
            results = search_entries(load_entries(path), args.query, args.limit)
            print(
                json.dumps(
                    {"query": args.query, "count": len(results), "results": results, "path": str(path)},
                    sort_keys=True,
                )
            )
            return 0
    except OpinionLedgerError as exc:
        print(f"[opinion-ledger] ERROR: {exc}", file=sys.stderr)
        return 2

    print("[opinion-ledger] ERROR: unsupported command", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
