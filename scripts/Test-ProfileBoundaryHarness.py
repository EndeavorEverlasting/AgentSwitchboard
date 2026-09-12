#!/usr/bin/env python3
"""Tracked-file completeness validator for the profile-boundary harness."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tooling/harness/profile-boundary/manifest.json"


def tracked(path: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    required = [
        "AGENTS.md",
        ".ai/harness/device-profile-registry.json",
        "docs/governance/device-profile-launcher-contract.md",
        *manifest["components"].values(),
    ]
    failures = []
    for rel in required:
        path = ROOT / rel
        if not path.is_file():
            failures.append(f"missing:{rel}")
        elif not tracked(rel):
            failures.append(f"untracked:{rel}")

    for rel in (
        "tooling/harness/profile-boundary/manifest.json",
        "tooling/harness/profile-boundary/codebase-map.json",
        "tooling/harness/profile-boundary/profile-boundary.registry.json",
        "tooling/harness/profile-boundary/artifact-registry.json",
        "tooling/harness/profile-boundary/command-envelope.schema.json",
        "tooling/harness/profile-boundary/workflow-specs.json",
        "tooling/harness/profile-boundary/fixtures/command-envelopes.json",
    ):
        try:
            json.loads((ROOT / rel).read_text(encoding="utf-8"))
        except Exception as exc:
            failures.append(f"invalid-json:{rel}:{exc}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    print(f"PASS: profile-boundary harness completeness ({len(required)}/{len(required)} tracked owners)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
