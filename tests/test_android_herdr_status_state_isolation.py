#!/usr/bin/env python3
"""Prove Herdr status routing is isolated from ambient operator artifacts."""
from __future__ import annotations
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling/profiles/android/harness/herdr"
FIXTURE = BASE / "fixtures/herdr-not-installed.fixture.env"
STATUS = BASE / "Get-HerdrHarnessStatus.py"
INSTALL = BASE / "Build-HerdrInstallReview.py"


def run(args: list[str], *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, env=env, check=False)
    assert result.returncode == 0, result.stderr
    return result


def status(*extra: str, env: dict[str, str] | None = None) -> dict:
    result = run([sys.executable, str(STATUS), "--evidence", str(FIXTURE), "--format", "json", *extra], env=env)
    return json.loads(result.stdout)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        xdg = tmp / "xdg-state"
        ambient = xdg / "agentswitchboard/android-herdr-migration"
        isolated = tmp / "isolated-validator-state"
        ambient.mkdir(parents=True)
        isolated.mkdir()

        ambient_review = ambient / "herdr-install-review-20260809T000000Z.md"
        run([sys.executable, str(INSTALL), "--output", str(ambient_review)])

        env = os.environ.copy()
        env["XDG_STATE_HOME"] = str(xdg)

        clean = status("--state-root", str(isolated), env=env)
        assert clean["stateRoot"] == str(isolated)
        assert clean["installReviewSource"] == "none"
        assert clean["status"] == "blocked-herdr-not-installed"
        assert clean["nextGate"] == "reviewed-installation-method"

        ambient_status = status(env=env)
        assert ambient_status["stateRoot"] == str(ambient)
        assert ambient_status["installReviewSource"] == str(ambient_review)
        assert ambient_status["status"] == "blocked-herdr-runtime-compatibility-unproved"
        assert ambient_status["nextGate"] == "source-bound-runtime-compatibility-review"

        isolated_review = isolated / "herdr-install-review-20260809T000001Z.md"
        run([sys.executable, str(INSTALL), "--output", str(isolated_review)])
        isolated_after = status("--state-root", str(isolated), env=env)
        assert isolated_after["installReviewSource"] == str(isolated_review)
        assert isolated_after["status"] == "blocked-herdr-runtime-compatibility-unproved"
        assert isolated_after["nextGate"] == "source-bound-runtime-compatibility-review"

        written = run([
            sys.executable,
            str(STATUS),
            "--state-root", str(isolated),
            "--evidence", str(FIXTURE),
            "--install-review", str(isolated_review),
            "--write",
        ], env=env)
        paths = {}
        for line in written.stdout.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                paths[key] = value
        assert Path(paths["STATUS_JSON"]).parent == isolated
        assert Path(paths["STATUS_MARKDOWN"]).parent == isolated
        assert paths["STATUS"] == "blocked-herdr-runtime-compatibility-unproved"

    print("PASS: Android Herdr status state-root isolation")


if __name__ == "__main__":
    main()
