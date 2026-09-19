#!/usr/bin/env python3
"""Contracts for source-bound Android/Termux compatibility review and no-install probe."""
import json, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling/profiles/android/harness/herdr"
SOURCE = BASE / "upstream-runtime-compatibility.json"
BUILDER = BASE / "Build-HerdrCompatibilityReview.py"
PROBE = BASE / "Probe-HerdrPrebuiltCompatibility.py"


def main() -> None:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert data["schema"] == "agentswitchboard.android-herdr-runtime-compatibility-source.v1"
    assert data["source"]["releaseTag"] == "v0.8.0"
    assert data["source"]["releaseCommit"] == "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
    assert data["source"]["artifact"] == "herdr-linux-aarch64"
    assert data["source"]["artifactSizeBytes"] == 19960864
    assert data["source"]["artifactSha256"] == "f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
    assert data["compatibility"]["nativeAndroidSourceBuild"]["decision"] == "BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK"
    prebuilt = data["compatibility"]["linuxMuslPrebuiltOnTermux"]
    assert prebuilt["buildTarget"] == "aarch64-unknown-linux-musl"
    assert prebuilt["decision"] == "EXECUTION_PROBE_APPROVED_NO_INSTALL"
    assert data["migrationDecision"] == "KEEP_TMUX"
    assert data["nextGate"] == "exact-device-prebuilt-execution-identity"

    with tempfile.TemporaryDirectory() as d:
        out = Path(d) / "compatibility.md"
        r = subprocess.run(["python", str(BUILDER), "--output", str(out)], cwd=ROOT, text=True, capture_output=True)
        assert r.returncode == 0, r.stderr
        text = out.read_text(encoding="utf-8")
        for token in (
            "Status: EXECUTION_PROBE_APPROVED_NO_INSTALL",
            "Release build target: aarch64-unknown-linux-musl",
            "Decision: BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK",
            "Installation authorized: no",
            "Server startup authorized: no",
            "Probe-HerdrPrebuiltCompatibility.py evidence",
            "exact-device-prebuilt-execution-identity",
        ):
            assert token in text, token
        assert "DECISION=EXECUTION_PROBE_APPROVED_NO_INSTALL" in r.stdout
        assert "MIGRATION_DECISION=KEEP_TMUX" in r.stdout

    r = subprocess.run(["python", str(PROBE), "contract"], cwd=ROOT, text=True, capture_output=True)
    assert r.returncode == 0, r.stderr
    for token in (
        "HERDR_PREBUILT_COMPATIBILITY_CONTRACT=PASS",
        "DECISION=EXECUTION_PROBE_APPROVED_NO_INSTALL",
        "MIGRATION_DECISION=KEEP_TMUX",
        "NEXT_GATE=exact-device-prebuilt-execution-identity",
    ):
        assert token in r.stdout, token

    probe = PROBE.read_text(encoding="utf-8")
    for forbidden in (
        "cargo install herdr",
        "device_config put",
        "max_phantom_processes",
        "PREFIX/bin",
        "herdr update",
        "subprocess.run([str(candidate), \"server\"",
    ):
        assert forbidden not in probe, forbidden
    assert '[str(candidate), "--version"]' in probe
    assert 'TemporaryDirectory(prefix="agentswitchboard-herdr-probe-")' in probe
    assert 'artifactSha256' in probe and 'artifactSizeBytes' in probe
    assert 'timeout=10' in probe

    print("PASS: Android Herdr prebuilt compatibility review")


if __name__ == "__main__":
    main()
