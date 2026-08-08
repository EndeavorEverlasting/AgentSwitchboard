#!/usr/bin/env python3
"""Contracts for proof-first Android Herdr migration."""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling/profiles/android/harness/herdr"


def tracked(path: str) -> Path:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    assert result.returncode == 0, f"not tracked: {path}"
    return target


def main() -> None:
    manifest = json.loads(tracked("tooling/profiles/android/harness/herdr/manifest.json").read_text(encoding="utf-8"))
    assert manifest["status"] == "experimental-unproved"
    assert manifest["currentRuntime"]["multiplexer"] == "tmux"
    assert manifest["candidate"]["termuxAndroid"] == "not-officially-claimed"
    assert manifest["candidate"]["cargoInstallClaim"] == "not-used-until-upstream-documents-it"
    assert "linux-aarch64" in manifest["candidate"]["officialStablePlatforms"]

    required_gates = {
        "termux-environment-observed",
        "herdr-command-identity-observed",
        "herdr-version-observed",
        "background-server-start-observed",
        "detach-reattach-observed",
        "agent-state-observed",
        "android-background-survival-observed",
        "bounded-agent-sprint-observed",
    }
    assert required_gates == set(manifest["gates"])
    assert "Do not replace tmux" in manifest["promotionRule"]

    for path in manifest["components"].values():
        tracked(path)

    probe = tracked("tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh").read_text(encoding="utf-8")
    for token in (
        "KEEP_TMUX_HERDR_NOT_INSTALLED",
        "KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY",
        "HERDR_BINARY_CANDIDATE_ONLY",
        "proof_level=binary-readiness-only",
        "live-server-detach-reattach-and-agent-state-proof",
    ):
        assert token in probe
    for forbidden in ("device_config put", "max_phantom_processes", "curl -fsSL https://herdr.dev/install.sh | sh", "cargo install herdr"):
        assert forbidden not in probe

    wrapper = tracked("Test-AgentSwitchboard-Android-Herdr.sh").read_text(encoding="utf-8")
    assert "Probe-Herdr-Migration.sh" in wrapper

    contract = subprocess.run(
        ["bash", str(ROOT / "Test-AgentSwitchboard-Android-Herdr.sh"), "contract"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert contract.returncode == 0, contract.stderr
    assert "HERDR_MIGRATION_CONTRACT=PASS" in contract.stdout
    assert "CANONICAL_ANDROID_MULTIPLEXER=tmux" in contract.stdout

    guide = tracked("docs/workstation/android-herdr-migration.md").read_text(encoding="utf-8")
    for token in (
        "experimental candidate",
        "Linux `aarch64`",
        "does **not** currently claim Android/Termux support",
        "Do **not** uninstall tmux",
        "bash Test-AgentSwitchboard-Android-Herdr.sh evidence",
        "same-device evidence",
        "Proof ceiling",
    ):
        assert token in guide

    print("PASS: Android Herdr migration contracts")


if __name__ == "__main__":
    main()
