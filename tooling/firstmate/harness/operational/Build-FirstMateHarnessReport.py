#!/usr/bin/env python3
import argparse
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXIT_OPERATIONAL = 2


def load(name: str) -> dict:
    return json.loads((HERE / name).read_text(encoding="utf-8"))


def render() -> str:
    manifest = load("manifest.json")
    codebase = load("codebase-map.json")
    workflows = load("workflow-registry.json")
    artifacts = load("artifact-registry.json")
    validators = load("validator-registry.json")
    contract = json.loads((ROOT / "tooling/firstmate/harness/integration-contract.json").read_text(encoding="utf-8"))

    lines = [
        "# First Mate operational harness report",
        "",
        f"Status: **{manifest['status']}**",
        "",
        "## Role boundaries",
        "",
        f"- AgentSwitchboard: {contract['role_boundaries']['agentswitchboard']}.",
        f"- First Mate: {contract['role_boundaries']['firstmate']}.",
        f"- Session backend: {contract['role_boundaries']['session_backend']}.",
        f"- Coding agent: {contract['role_boundaries']['coding_agent']}.",
        "",
        "## Working",
        "",
        "- Exact First Mate upstream pin and read-only Linux/WSL compatibility contract are tracked.",
        "- Deterministic direct-vs-crew routing is tracked and testable.",
        "- The first safe sprint contract requires `local-only` with `first_safe_sprint.yolo_enabled: false`.",
        "- tmux remains the reference session backend.",
        "- Windows paths cross into WSL through `WSLENV /p`; WSL stderr is isolated from machine-readable stdout.",
        "- The Windows bridge derives committed source state and creates a WSL-owned standalone exact-head clone instead of running Linux Git inside a Windows-created linked worktree.",
        f"- {len(workflows['workflows'])} workflow specs, {len(validators['validators'])} validators, and {len(artifacts['artifacts'])} generated artifact roles are registered.",
        "",
        "## Broken or blocked",
        "",
        "- Live First Mate crew dispatch is not yet runtime-proved.",
        "- The physical laptop proved that a Windows-created detached worktree is not a sufficient Linux Git execution surface for this bridge; the standalone-clone repair now requires exact-head reproof.",
        "- Herdr automatic selection is disabled; its separate compatibility/migration lane must clear pinned-contract and live-runtime gates.",
        "- Native Windows First Mate behavior is unverified; the bridge only launches the Linux/WSL lane from Windows.",
        "",
        "## Missing proof",
        "",
        "- One successful physical-laptop Windows-to-WSL floor proof using the WSL-owned standalone clone.",
        "- One bounded local-only First Mate crew sprint with isolated worker worktrees.",
        "- Live worker state, validator receipt, and convergence evidence from that sprint.",
        "- Any Herdr session-backend promotion evidence.",
        "",
        "## Canonical entry commands",
        "",
        f"- Contract: `{codebase['entrypoints']['crew_harness']}`",
        f"- Windows/WSL bridge: `{codebase['entrypoints']['windows_wsl_bridge']}`",
        f"- First Mate probe: `{codebase['entrypoints']['firstmate_probe']}`",
        f"- Route selector: `{codebase['entrypoints']['route_selector']}`",
        "",
        "## Next useful unproved state",
        "",
        "On the Windows laptop, run the tracked Windows-to-WSL bridge at the exact PR head. Require a WSL-owned standalone clone at the same SHA plus the registered floor/report/route diagnostics. If the read-only floor passes, route a bounded parallel task to `firstmate-local-only`; do not wait for Android or Herdr readiness.",
        "",
        "## Proof ceiling",
        "",
        manifest["proof_ceiling"],
        "",
    ]
    return "\n".join(lines)


def emit_error(error_id: str, exc: Exception, next_command: str) -> int:
    payload = {
        "status": "error",
        "error": error_id,
        "message": str(exc),
        "next_command": next_command,
    }
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    return EXIT_OPERATIONAL


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    if args.stdout and args.output:
        parser.error("--stdout and --output are mutually exclusive")

    try:
        text = render()
        if args.stdout:
            print(text)
            return 0

        if args.output:
            output = Path(args.output).expanduser().resolve()
        else:
            output = Path(tempfile.gettempdir()) / "agentswitchboard" / "firstmate-harness" / "firstmate-harness-report.md"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
        print(output)
        return 0
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        return emit_error(
            "firstmate-report-operational-error",
            exc,
            "bash Test-AgentSwitchboard-FirstMate-Harness.sh contract",
        )


if __name__ == "__main__":
    raise SystemExit(main())
