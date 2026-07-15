"""CLI entrypoint for the AgentSwitchboard invocation command."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Optional

from .contract import (
    EXIT_ACTION_REQUIRED,
    EXIT_INTERNAL_FAILURE,
    EXIT_INVALID_REQUEST,
    EXIT_SUCCESS,
    EXIT_UNSUPPORTED_PROFILE,
    build_result,
    run_fixture,
    validate_request,
)


def print_usage():
    print(
        "Usage: agentswitchboard request.json [--pretty]\n"
        "       agentswitchboard --validate < request.json\n"
        "       agentswitchboard --supported-profiles\n"
        "       agentswitchboard --supported-operations\n"
        "       agentswitchboard --supported-agents\n"
        "       agentswitchboard --version"
    )


def handle_supported():
    """Print supported profiles, operations, or agents."""
    print(json.dumps({
        "supported_profiles": ["windows-native", "linux-native", "wsl-tmux"],
        "profiles_description": {
            "windows-native": "Native Windows with PowerShell 7",
            "linux-native": "Native Linux with Bash",
            "wsl-tmux": "WSL on Windows with tmux (optional, disabled by default)",
        },
        "supported_platforms": ["windows", "linux"],
        "unsupported_platforms": ["macos"],
    }, indent=2))


def main(argv: Optional[list[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    if not argv:
        print_usage()
        return EXIT_INVALID_REQUEST

    if argv[0] in ("-h", "--help"):
        print_usage()
        return EXIT_SUCCESS

    if argv[0] == "--version":
        print("agentswitchboard version 0.1.0")
        return EXIT_SUCCESS

    if argv[0] == "--supported-profiles":
        print("windows-native linux-native wsl-tmux")
        return EXIT_SUCCESS

    if argv[0] == "--supported-operations":
        print("inventory install-missing repair-check smoke")
        return EXIT_SUCCESS

    if argv[0] == "--supported-agents":
        print("opencode agy goose")
        return EXIT_SUCCESS

    if argv[0] == "--validate":
        try:
            raw = json.loads(sys.stdin.read())
        except json.JSONDecodeError as e:
            print(f"Invalid JSON: {e}", file=sys.stderr)
            return EXIT_INVALID_REQUEST

        errors = validate_request(raw)
        if errors:
            print("VALIDATION FAILED:")
            for err in errors:
                print(f"  - {err}", file=sys.stderr)
            return EXIT_INVALID_REQUEST
        else:
            print("VALIDATION PASSED")
            return EXIT_SUCCESS

    # Default: process a request file
    pretty = False
    args = list(argv)
    if "--pretty" in args:
        pretty = True
        args.remove("--pretty")

    if not args:
        print("Missing request file.", file=sys.stderr)
        return EXIT_INVALID_REQUEST

    path = Path(args[0])
    if not path.is_file():
        print(f"File not found: {path}", file=sys.stderr)
        return EXIT_INVALID_REQUEST

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        return EXIT_INVALID_REQUEST

    # Validate
    errors = validate_request(raw)
    if errors:
        print("ERROR: request validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return EXIT_INVALID_REQUEST

    # check for unsupported_profile
    profile = raw.get("execution_profile_id", "")
    raw_platform = raw.get("platform", "")
    is_macos = raw_platform == "macos" or (
        "platform" in raw and raw["platform"] not in ("windows", "linux")
    )
    if is_macos:
        result = build_result(
            raw, {}, "unsupported_profile", EXIT_UNSUPPORTED_PROFILE, False
        )
        print(json.dumps(result, indent=2 if pretty else None))
        return EXIT_UNSUPPORTED_PROFILE

    # Execute
    if raw.get("fixture_mode", False):
        result = run_fixture(raw)
    else:
        # For non-fixture, we return an "action_required" with a clear proof ceiling
        # Real execution is not implemented in this contract
        agents_data = {}
        for agent in raw.get("requested_agents", []):
            agents_data[agent] = {
                "installation_state": "unknown",
                "detected_version": None,
                "authentication_readiness": "unknown",
                "smoke_status": "skipped",
                "action_taken": "requires runtime execution — not available in contract proof",
                "reason_code": "requires_live_platform",
            }

        result = build_result(
            raw,
            agents_data,
            "FAIL",
            EXIT_ACTION_REQUIRED,
            False,
        )

        print(json.dumps(result, indent=2 if pretty else None))
        return EXIT_ACTION_REQUIRED

    # Print the result
    print(json.dumps(result, indent=2 if pretty else None))
    return EXIT_SUCCESS


if __name__ == "__main__":
    sys.exit(main())



EXIT_SUCCESS = 0
EXIT_ACTION_REQUIRED = 1
EXIT_INVALID_REQUEST = 2
EXIT_UNSUPPORTED_PROFILE = 3
EXIT_INTERNAL_FAILURE = 4

__all__ = [
    "EXIT_SUCCESS", "EXIT_ACTION_REQUIRED",
    "EXIT_INVALID_REQUEST", "EXIT_UNSUPPORTED_PROFILE", "EXIT_INTERNAL_FAILURE",
]
