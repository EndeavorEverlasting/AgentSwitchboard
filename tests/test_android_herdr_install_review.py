#!/usr/bin/env python3
"""Contracts for the source-bound Android Herdr installation review."""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling/profiles/android/harness/herdr"
SOURCE_REL = "tooling/profiles/android/harness/herdr/upstream-installation-source.json"


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
    source = json.loads(tracked(SOURCE_REL).read_text(encoding="utf-8"))
    assert source["schema"] == "agentswitchboard.android-herdr-upstream-installation-source.v1"
    assert source["source"]["kind"] == "official-upstream"
    assert source["source"]["repository"] == "https://github.com/herdrdev/herdr"
    assert source["source"]["installDocs"] == "https://herdr.dev/docs/install/"
    assert source["source"]["releaseTag"] == "v0.8.0"
    assert len(source["source"]["releaseCommit"]) == 40
    assert source["source"]["tagObject"] == "857196dee1ce98df53efdd3f437aa2ac8a75b608"
    assert source["androidTermuxSupport"] == "not-stated"
    assert source["cargoInstallDocumented"] is False
    assert "Linux aarch64" in source["documentedArchitectures"]
    candidate = source["candidate"]
    assert candidate["artifact"] == "herdr-linux-aarch64"
    assert candidate["sizeBytes"] == 19960864
    assert candidate["digestAlgorithm"] == "sha256"
    assert candidate["digest"] == "f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
    assert candidate["decision"] == "BLOCKED"
    assert candidate["installCommand"] is None
    assert candidate["rollbackCommand"] is None
    assert candidate["nextGate"] == "prove-android-runtime-compatibility-or-obtain-explicit-upstream-support"
    assert source["safety"] == {
        "linuxAarch64IsAndroidProof": False,
        "curlPipeShellAcceptedAsProof": False,
        "automaticAndroidPolicyMutationAllowed": False,
        "tmuxRollbackRequired": True,
    }

    with tempfile.TemporaryDirectory() as temp_dir:
        review = Path(temp_dir) / "review.md"
        result = subprocess.run(
            ["python", str(BASE / "Build-HerdrInstallReview.py"), "--output", str(review)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr
        assert "DECISION=BLOCKED" in result.stdout
        assert "NEXT_GATE=prove-android-runtime-compatibility-or-obtain-explicit-upstream-support" in result.stdout
        text = review.read_text(encoding="utf-8")
        for token in (
            "Status: BLOCKED",
            "v0.8.0 / " + source["source"]["releaseCommit"],
            "sha256:" + candidate["digest"],
            "Explicit Android/Termux support claim: not-stated",
            "Linux aarch64 is not treated as Android compatibility proof: yes",
            "`cargo install herdr` is documented by the pinned upstream source: no",
            "Exact installation command, only when APPROVED: none",
            "tmux remains installed and available for rollback: yes",
        ):
            assert token in text, token

    print("PASS: Android Herdr source-bound installation review")


if __name__ == "__main__":
    main()
