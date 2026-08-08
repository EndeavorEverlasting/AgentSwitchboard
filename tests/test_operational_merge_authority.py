#!/usr/bin/env python3
"""Regression contract for operational-harness merge-authority continuation."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPORTER = ROOT / "tooling" / "harness" / "operational" / "Get-OperationalHarnessStatus.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(result.returncode == 0, f"git {' '.join(args)} failed: {result.stderr}")
    return result.stdout.strip()


def run_report(*extra: str) -> tuple[subprocess.CompletedProcess[str], dict, dict, str]:
    with tempfile.TemporaryDirectory() as temp_dir:
        result = subprocess.run(
            [
                sys.executable,
                str(REPORTER),
                "--task", "complete validated PR integration",
                "--output-root", temp_dir,
                "--pr-number", "123",
                "--validated-command", "python tests/test_operational_merge_authority.py",
                "--gate-complete",
                *extra,
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        status_path = Path(temp_dir) / "operational-harness-status.json"
        handoff_path = Path(temp_dir) / "operational-harness-handoff.json"
        report_path = Path(temp_dir) / "operational-harness-report.md"
        status = json.loads(status_path.read_text(encoding="utf-8")) if status_path.is_file() else {}
        handoff = json.loads(handoff_path.read_text(encoding="utf-8")) if handoff_path.is_file() else {}
        report = report_path.read_text(encoding="utf-8") if report_path.is_file() else ""
        return result, status, handoff, report


def main() -> None:
    head = git("rev-parse", "HEAD")

    result, status, handoff, report = run_report()
    require(result.returncode == 0, f"unresolved-authority reporter failed: {result.stderr}")
    require(handoff["nextOwner"] == "repository owner", "unresolved merge authority must remain owner-controlled")
    require("explicit owner merge authorization" in handoff["nextDependency"], "unresolved authority dependency missing")
    require("merge authorization" in handoff["unproved"], "unresolved merge authority must remain unproved")
    require(f"--match-head-commit {head}" in handoff["nextCommand"], "unresolved merge command must pin exact head")
    require("merge authorized: `False`" in report, "report must render unresolved merge authority")

    source = "standing repository-owner directive: merge validated in-scope work"
    result, status, handoff, report = run_report(
        "--merge-authorized",
        "--merge-authority-source", source,
    )
    require(result.returncode == 0, f"authorized reporter failed: {result.stderr}")
    require(handoff["nextOwner"] == "current harness agent", "authorized merge must remain with the current harness agent")
    require("merge authorized by" in handoff["nextDependency"], "authorized dependency must preserve authority source")
    require(source in handoff["nextDependency"], "authorized dependency lost authority source")
    require("explicit owner merge authorization" not in handoff["nextDependency"], "authorized merge must not ask for authority again")
    require("merge authorization" not in handoff["unproved"], "recorded merge authority must not remain listed as unproved")
    require(f"--match-head-commit {head}" in handoff["nextCommand"], "authorized merge command must pin exact head")
    require("merge authorized: `True`" in report, "report must render granted merge authority")
    require(f"merge authority source: `{source}`" in report, "report must render authority source")
    require(status["routing"]["workflow"] == "handoff", "completed PR gate should still use handoff lifecycle metadata")

    with tempfile.TemporaryDirectory() as temp_dir:
        missing_source = subprocess.run(
            [
                sys.executable,
                str(REPORTER),
                "--output-root", temp_dir,
                "--pr-number", "123",
                "--validated-command", "synthetic validation",
                "--gate-complete",
                "--merge-authorized",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        require(missing_source.returncode != 0, "merge authority without a source must fail closed")
        require("requires --merge-authority-source" in missing_source.stderr, "missing authority source failure must be explicit")

    with tempfile.TemporaryDirectory() as temp_dir:
        source_without_authority = subprocess.run(
            [
                sys.executable,
                str(REPORTER),
                "--output-root", temp_dir,
                "--pr-number", "123",
                "--validated-command", "synthetic validation",
                "--gate-complete",
                "--merge-authority-source", source,
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        require(source_without_authority.returncode != 0, "authority source without --merge-authorized must fail closed")
        require("requires --merge-authorized" in source_without_authority.stderr, "orphan authority source failure must be explicit")

    print("PASS: operational harness preserves standing merge authority and exact-head integration ownership")


if __name__ == "__main__":
    main()
