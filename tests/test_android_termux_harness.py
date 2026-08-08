#!/usr/bin/env python3
"""Dependency-free Android/Termux operational harness contracts."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/profiles/android/harness/termux"


def load_json(path: Path):
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8"))


def require(path: str) -> Path:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    return target


def main() -> None:
    manifest = load_json(HARNESS / "manifest.json")
    codebase = load_json(HARNESS / "codebase-map.json")
    artifacts = load_json(HARNESS / "artifact-registry.json")
    capture = load_json(HARNESS / "workflows/capture-terminal-output.workflow.json")
    load_json(HARNESS / "workflows/task-intake.workflow.json")
    load_json(HARNESS / "workflows/validate-terminal-boundary.workflow.json")
    load_json(HARNESS / "workflows/handle-input-boundary-failure.workflow.json")

    assert manifest["harnessId"] == "agentswitchboard.android-termux-operational-harness.v1"
    assert manifest["runtimeEntrypoint"] == "Start-AgentSwitchboard-Android.sh"
    assert manifest["status"] == "operational-harness-runtime-separate"
    assert set(manifest["requiredTools"]) == {"git", "tmux", "gh", "ssh", "curl", "jq"}

    for group in ("workflows", "fixtures", "hooks", "skills"):
        for path in manifest["components"][group]:
            require(path)
    for key in ("codebaseMap", "artifactRegistry", "operatorReport", "operatorGuide", "portableTest", "completenessValidator", "ci"):
        require(manifest["components"][key])

    registry = load_json(ROOT / ".ai/harness/device-profile-registry.json")
    android = next(item for item in registry["profiles"] if item["profileId"] == "android")
    assert android["status"] == "implemented-runtime-unproved"
    assert android["frontend"] == "termux"
    assert android["canonicalSourcePath"] == "Start-AgentSwitchboard-Android.sh"
    require("Start-AgentSwitchboard-Android.sh")
    require("tooling/profiles/android/AgentSwitchboard-Android.sh")

    commands = json.dumps(codebase["operatorCommands"])
    assert "tmux list-panes" in commands
    assert "tmux capture-pane -p -S -200" in commands
    assert "Ctrl+B" in commands and "PgUp" in commands

    traps = "\n".join(codebase["knownTraps"])
    assert "long-press selection" in traps
    assert "Touch scrolling" in traps
    assert "authentication/device-code" in traps
    assert "[200~" in traps

    ids = {item["artifactId"] for item in artifacts["artifacts"]}
    assert {"tmux-pane-inventory", "tmux-pane-capture", "terminal-interaction-report"} <= ids
    assert artifacts["capturePolicy"]["defaultHistoryLines"] == 200
    forbidden = " ".join(artifacts["forbiddenContent"])
    for token in ("device codes", "access tokens", "private SSH keys", "credential file"):
        assert token in forbidden

    workflow_text = json.dumps(capture)
    for token in ("list-panes", "capture-pane", "exactly one tmux target", "OAuth/device codes", "copy mode", "QR/live-document/file"):
        assert token in workflow_text
    assert "does not prove the captured command succeeded" in capture["proofCeiling"]

    fixture = require("tooling/profiles/android/harness/termux/fixtures/multi-pane-selection.fixture.txt").read_text(encoding="utf-8")
    assert "CLASSIFICATION=terminal-selection-and-scrollback-boundary" in fixture
    assert "REQUIRED_RECOVERY=" in fixture

    skill = require(".ai/skills/android-termux-terminal-recovery/SKILL.md").read_text(encoding="utf-8")
    for token in ("tmux list-panes", "tmux capture-pane", "Ctrl+B", "QR", "Never solve a secrecy problem"):
        assert token in skill

    guide = require("docs/harness/android-termux-operational-harness.md").read_text(encoding="utf-8")
    for token in ("pane identity beats touch selection", "capture-pane", "copy mode", "implemented", "Runtime boundary"):
        assert token in guide

    for hook in manifest["components"]["hooks"]:
        text = require(hook).read_text(encoding="utf-8")
        assert "test_android_termux_harness.py" in text
        assert "diff --check" in text

    print("PASS: Android Termux operational harness contracts")


if __name__ == "__main__":
    main()
