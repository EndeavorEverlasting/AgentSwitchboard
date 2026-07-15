"""Command-line entrypoint for the versioned AgentSwitchboard contract."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from .contract import (
    EXIT_INTERNAL_FAILURE, EXIT_INVALID_REQUEST, EXIT_SUCCESS, EXIT_UNSUPPORTED_PROFILE,
    build_result, run_fixture, run_live, validate_request,
)


def _read_json(text: str):
    try: return json.loads(text), None
    except json.JSONDecodeError as exc: return None, f"Invalid JSON: {exc}"


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in {"-h", "--help"}:
        print("Usage: python -m agentswitchboard REQUEST.json [--pretty] | --validate")
        return EXIT_SUCCESS if args else EXIT_INVALID_REQUEST
    if args[0] == "--version": print("agentswitchboard 0.2.0"); return EXIT_SUCCESS
    if args[0] == "--supported-profiles": print("windows-native windows-wsl linux-native"); return EXIT_SUCCESS
    if args[0] == "--supported-operations": print("inventory install-missing repair-check smoke"); return EXIT_SUCCESS
    if args[0] == "--supported-agents": print("opencode agy goose"); return EXIT_SUCCESS
    if args[0] == "--validate":
        raw, problem = _read_json(sys.stdin.read())
        if problem: print(problem, file=sys.stderr); return EXIT_INVALID_REQUEST
        errors = validate_request(raw)
        if errors:
            print("VALIDATION FAILED", file=sys.stderr)
            for error in errors: print(f"- {error}", file=sys.stderr)
            return EXIT_INVALID_REQUEST
        print("VALIDATION PASSED"); return EXIT_SUCCESS
    pretty = "--pretty" in args
    args = [arg for arg in args if arg != "--pretty"]
    path = Path(args[0])
    if not path.is_file(): print(f"File not found: {path}", file=sys.stderr); return EXIT_INVALID_REQUEST
    raw, problem = _read_json(path.read_text(encoding="utf-8-sig"))
    if problem: print(problem, file=sys.stderr); return EXIT_INVALID_REQUEST
    if isinstance(raw, dict) and raw.get("platform") == "macos":
        result = build_result(raw, {}, "unsupported", EXIT_UNSUPPORTED_PROFILE)
        print(json.dumps(result, indent=2 if pretty else None)); return EXIT_UNSUPPORTED_PROFILE
    errors = validate_request(raw)
    if errors:
        for error in errors: print(f"- {error}", file=sys.stderr)
        return EXIT_INVALID_REQUEST
    try:
        result = run_fixture(raw) if raw["posture"] == "fixture" else run_live(raw, Path(__file__).resolve().parents[1])
    except Exception as exc:
        print(f"AgentSwitchboard internal failure: {exc}", file=sys.stderr)
        return EXIT_INTERNAL_FAILURE
    print(json.dumps(result, indent=2 if pretty else None))
    return int(result.get("exit_code", EXIT_INTERNAL_FAILURE))


if __name__ == "__main__":
    raise SystemExit(main())
