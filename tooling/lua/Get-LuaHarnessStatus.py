#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "tooling" / "lua" / "harness"
CONTRACT = HARNESS / "lua-embedding.contract.json"
ARTIFACTS = HARNESS / "artifact-registry.json"
MANIFEST = HARNESS / "manifest.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def build_readiness():
    contract = load(CONTRACT)
    manifest = load(MANIFEST)
    return {
        "schema": "agentswitchboard.lua-readiness.v1",
        "status": "contract-ready-runtime-unproved",
        "contractReady": True,
        "runtimeEmbedded": False,
        "sandboxRuntimeProved": False,
        "stateIsolationRuntimeProved": False,
        "proofCeiling": manifest["proofCeiling"],
        "nextAction": (
            "Open a separately authorized Lua runtime integration sprint that pins an exact "
            "Lua implementation/version and official embedding API, then implements and proves "
            "host-owned create-run-close lifecycle, protected error handling, deny-by-default "
            "sandboxing, resource limits, and teardown before product-runtime promotion."
        ),
        "requiredRuntimeGates": contract["runtimePromotionGates"],
    }


def render_report(readiness):
    return "\n".join(
        [
            "# Lua embedding harness report",
            "",
            f"Status: **{readiness['status']}**",
            "",
            "## Working",
            "",
            "- Lua is modeled as an embedded library; the host owns the main loop.",
            "- Independent VM states and explicit state teardown are required.",
            "- Script errors terminate at a protected host catch boundary with host-owned cleanup.",
            "- Sandbox policy is default-deny with explicit host-function allow-listing.",
            "- `os`, `io`, `package`, and `debug` are forbidden by default.",
            "- JIT is optional and separately gated; interpreter-first remains acceptable.",
            "- Lua-native 1-based indexing is preserved.",
            "- AI-authored snippets require explicit capabilities and auditable side effects.",
            "",
            "## Broken or blocked",
            "",
            "- No exact Lua implementation/version or official embedding API is pinned by this harness sprint.",
            "- No AgentSwitchboard product host wrapper or Lua VM state exists under this harness scope.",
            "- Runtime memory limits, instruction/time limits, sandbox enforcement, teardown, and leak evidence are unproved.",
            "",
            "## Missing proof",
            "",
            *[f"- {item}" for item in readiness["requiredRuntimeGates"]],
            "",
            "## Next action",
            "",
            readiness["nextAction"],
            "",
            "## Proof ceiling",
            "",
            readiness["proofCeiling"],
            "",
        ]
    )


def main():
    parser = argparse.ArgumentParser(description="Render read-only Lua embedding harness readiness.")
    parser.add_argument("--no-write", action="store_true", help="Print the report only; create no files.")
    parser.add_argument("--output-root", help="Directory for generated untracked evidence.")
    parser.add_argument("--json", action="store_true", help="Print readiness JSON instead of Markdown.")
    args = parser.parse_args()

    readiness = build_readiness()
    report = render_report(readiness)

    if args.no_write:
        print(json.dumps(readiness, indent=2) if args.json else report)
        return 0

    registry = load(ARTIFACTS)
    names = {item["id"]: item["filename"] for item in registry["artifacts"]}
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = Path(args.output_root) if args.output_root else Path(tempfile.gettempdir()) / "AgentSwitchboard" / "LuaHarness" / run_id
    out.mkdir(parents=True, exist_ok=True)
    report_path = out / names["operator-report"]
    readiness_path = out / names["readiness"]
    report_path.write_text(report, encoding="utf-8")
    readiness_path.write_text(json.dumps(readiness, indent=2) + "\n", encoding="utf-8")
    print(str(report_path.resolve()))
    print(str(readiness_path.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
