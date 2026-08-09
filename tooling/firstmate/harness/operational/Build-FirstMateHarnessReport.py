#!/usr/bin/env python3
import argparse
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


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
        "- tmux remains the reference session backend.",
        "- The Windows-to-WSL proof bridge keeps WSL diagnostics on stderr and machine-readable output on stdout; it does not depend on `wslpath`.",
        f"- {len(workflows['workflows'])} workflow specs, {len(validators['validators'])} validators, and {len(artifacts['artifacts'])} generated artifact roles are registered.",
        "",
        "## Broken or blocked",
        "",
        "- Live First Mate crew dispatch is not yet runtime-proved.",
        "- The repaired Windows-to-WSL bridge still requires physical-laptop exact-head reproof after the observed `wslpath` transport failure.",
        "- Herdr automatic selection is disabled; its separate compatibility/migration lane must clear pinned-contract and live-runtime gates.",
        "- Native Windows First Mate behavior is unverified; the bridge only launches the Linux/WSL lane from Windows.",
        "",
        "## Missing proof",
        "",
        "- One successful physical-laptop Windows-to-WSL floor proof using the tracked bridge.",
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
        "On the Windows laptop, run the tracked Windows-to-WSL bridge at the exact PR head. If the read-only floor passes, route a bounded parallel task to `firstmate-local-only`; do not wait for Android or Herdr readiness.",
        "",
        "## Proof ceiling",
        "",
        manifest["proof_ceiling"],
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    text = render()
    if args.stdout:
        if args.output:
            parser.error("--stdout and --output are mutually exclusive")
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


if __name__ == "__main__":
    raise SystemExit(main())
