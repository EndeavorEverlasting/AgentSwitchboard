#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MANIFEST = Path(__file__).with_name("manifest.json")


def select(parallel_writers: int, floor: str, platform: str, request_herdr: bool) -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    herdr_enabled = bool(manifest["routing"]["herdr_selection_enabled"])

    if parallel_writers < 1:
        raise ValueError("parallel_writers must be >= 1")

    if request_herdr and not herdr_enabled:
        return {
            "status": "blocked",
            "route": "runtime-promotion",
            "session_backend": "tmux",
            "execution_allowed": False,
            "owner": "separate Herdr compatibility/migration lane",
            "dependency": "Herdr pinned-contract, aggregate-registration, and live-runtime gates",
            "blocker": "herdr-selection-disabled",
            "next_command": "bash Test-AgentSwitchboard-FirstMate-Harness.sh contract",
        }

    if platform != "linux-wsl":
        return {
            "status": "ready",
            "route": "direct-asb",
            "session_backend": "tmux",
            "execution_allowed": True,
            "owner": "AgentSwitchboard platform/profile owner",
            "dependency": "selected platform profile",
            "reason": f"First Mate crew lane is not certified for platform={platform}",
            "next_command": "python3 tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py",
        }

    if parallel_writers == 1:
        return {
            "status": "ready",
            "route": "direct-asb",
            "session_backend": "tmux",
            "execution_allowed": True,
            "owner": "current AgentSwitchboard writer",
            "dependency": "normal repository validator",
            "reason": "one writer does not require a crew orchestration layer",
            "next_command": "python3 tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py",
        }

    if floor != "pass":
        return {
            "status": "blocked",
            "route": "firstmate-readiness",
            "session_backend": "tmux",
            "execution_allowed": False,
            "owner": "First Mate interoperability lane",
            "dependency": "read-only First Mate repository/toolchain floor",
            "blocker": f"firstmate-floor-{floor}",
            "next_command": "bash tooling/firstmate/Test-FirstMateInterop.sh --firstmate <path>",
        }

    return {
        "status": "ready",
        "route": "firstmate-local-only",
        "session_backend": "tmux",
        "delivery_mode": "local-only",
        "execution_allowed": True,
        "owner": "First Mate captain under AgentSwitchboard policy",
        "dependency": "disjoint worker branches/worktrees and bounded task contracts",
        "reason": "parallel Linux/WSL work with the First Mate floor proved",
        "next_command": "bash Test-AgentSwitchboard-FirstMate-Harness.sh report",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Deterministically select the AgentSwitchboard/First Mate crew route.")
    parser.add_argument("--parallel-writers", type=int, default=1)
    parser.add_argument("--firstmate-floor", choices=("pass", "unproved", "fail"), default="unproved")
    parser.add_argument("--platform", choices=("linux-wsl", "windows", "android", "other"), default="linux-wsl")
    parser.add_argument("--request-herdr", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()

    try:
        result = select(args.parallel_writers, args.firstmate_floor, args.platform, args.request_herdr)
    except ValueError as exc:
        parser.error(str(exc))

    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
        print(output)
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
