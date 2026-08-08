#!/usr/bin/env python3
"""Dependency-free Android/Termux operational harness contracts."""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/profiles/android/harness/termux"


def load_json(path: Path):
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8"))


def require(path: str) -> Path:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    assert tracked.returncode == 0, f"not tracked in Git index: {path}"
    return target


def main() -> None:
    manifest = load_json(HARNESS / "manifest.json")
    codebase = load_json(HARNESS / "codebase-map.json")
    artifacts = load_json(HARNESS / "artifact-registry.json")
    capture = load_json(HARNESS / "workflows/capture-terminal-output.workflow.json")
    intake = load_json(HARNESS / "workflows/task-intake.workflow.json")
    load_json(HARNESS / "workflows/validate-terminal-boundary.workflow.json")
    load_json(HARNESS / "workflows/handle-input-boundary-failure.workflow.json")

    assert manifest["harnessId"] == "agentswitchboard.android-termux-operational-harness.v1"
    assert manifest["runtimeEntrypoint"] == "Start-AgentSwitchboard-Android.sh"
    assert manifest["status"] == "operational-harness-runtime-separate"
    assert set(manifest["requiredTools"]) == {"git", "tmux", "gh", "ssh", "curl", "jq", "python"}
    assert manifest["harnessBootstrap"] == "pkg install -y python"
    assert manifest["authorityRef"] == ".ai/agent-contract.json"
    assert manifest["repositoryFamilyRegistry"] == ".ai/harness/repository-family.registry.json"
    assert manifest["repositoryFamilyStatusProbe"] == "scripts/Get-RepositoryFamilyHarnessStatus.ps1"

    for group in ("workflows", "fixtures", "hooks", "skills"):
        for path in manifest["components"][group]:
            require(path)
    for key in ("codebaseMap", "artifactRegistry", "operatorReport", "operatorGuide", "portableTest", "completenessValidator", "ci"):
        require(manifest["components"][key])
    for path in (manifest["authorityRef"], manifest["repositoryFamilyRegistry"], manifest["repositoryFamilyStatusProbe"]):
        require(path)

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
    assert "git rev-parse --show-toplevel" in commands
    assert codebase["entrypoints"]["harnessPrerequisiteInstall"] == "pkg install -y python"
    assert codebase["entrypoints"]["repositoryFamilyStatus"].endswith("scripts/Get-RepositoryFamilyHarnessStatus.ps1")

    traps = "\n".join(codebase["knownTraps"])
    for token in ("long-press selection", "Touch scrolling", "authentication/device-code", "[200~", "usable local clone", "Python", "Repository-family status"):
        assert token in traps

    step_ids = [step["id"] for step in intake["steps"]]
    assert step_ids.index("verify-local-clone") < step_ids.index("preserve-main")
    assert "repository-family-gate" in step_ids
    intake_text = json.dumps(intake)
    for token in ("pkg install -y python", "command -v python", ".ai/agent-contract.json", ".ai/harness/repository-family.registry.json", "Get-RepositoryFamilyHarnessStatus.ps1"):
        assert token in intake_text

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

    recovery_skill = require(".ai/skills/android-termux-terminal-recovery/SKILL.md").read_text(encoding="utf-8")
    for token in ("tmux list-panes", "tmux capture-pane", "Ctrl+B", "QR", "Never solve a secrecy problem"):
        assert token in recovery_skill

    bootstrap_skill = require(".ai/skills/android-termux-repo-bootstrap/SKILL.md").read_text(encoding="utf-8")
    for token in ("pkg install -y python", "verify the local path", "repository-family.registry.json", "Get-RepositoryFamilyHarnessStatus.ps1", "does not modify runtime product code"):
        assert token in bootstrap_skill

    guide = require("docs/harness/android-termux-operational-harness.md").read_text(encoding="utf-8")
    for token in ("pane identity beats touch selection", "capture-pane", "copy mode", "pkg install -y python", "Clone before branch operations", "Get-RepositoryFamilyHarnessStatus.ps1", "Runtime boundary"):
        assert token in guide

    for hook in manifest["components"]["hooks"]:
        text = require(hook).read_text(encoding="utf-8")
        assert "test_android_termux_harness.py" in text
        assert "diff --check" in text
        assert "python" in text

    workflow = require(".github/workflows/android-termux-harness.yml").read_text(encoding="utf-8")
    assert workflow.count("persist-credentials: false") == 2
    assert "windows-entrypoints:" in workflow
    assert "scripts/Test-RuntimeEventContract.ps1" in workflow
    assert "Test-AppHarness.cmd" in workflow

    print("PASS: Android Termux operational harness contracts")


if __name__ == "__main__":
    main()
