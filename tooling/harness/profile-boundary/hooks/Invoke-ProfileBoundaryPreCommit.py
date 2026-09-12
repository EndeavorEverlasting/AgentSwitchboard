#!/usr/bin/env python3
"""Optional pre-commit gate for profile-boundary harness changes."""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]


def run(*args: str) -> None:
    result = subprocess.run(args, cwd=ROOT, check=False)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def main() -> int:
    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if staged.returncode != 0:
        return staged.returncode
    relevant_prefixes = (
        "tooling/harness/profile-boundary/",
        ".ai/skills/profile-boundary-routing/",
        "docs/harness/profile-boundary-operational-harness.md",
        "scripts/Test-ProfileBoundaryHarness.py",
        "tests/test_profile_boundary_harness.py",
        ".github/workflows/profile-boundary-harness.yml",
        "PROFILE_BOUNDARY_HARNESS.md",
        "Test-ProfileBoundaryHarness.cmd",
    )
    paths = [line.strip() for line in staged.stdout.splitlines() if line.strip()]
    if not any(path.startswith(relevant_prefixes) for path in paths):
        print("SKIP: no staged profile-boundary harness paths")
        return 0

    run(sys.executable, "scripts/Test-ProfileBoundaryHarness.py")
    run(sys.executable, "tests/test_profile_boundary_harness.py")
    run("git", "diff", "--cached", "--check")
    print("PASS: profile-boundary pre-commit gate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
