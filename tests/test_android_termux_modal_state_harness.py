#!/usr/bin/env python3
"""Portable contracts for Android/Termux modal-state and sprint-prompt recovery."""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/profiles/android/harness/termux"


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


def load(path: str):
    return json.loads(tracked(path).read_text(encoding="utf-8"))


def main() -> None:
    manifest = load("tooling/profiles/android/harness/termux/manifest.json")
    codebase = load("tooling/profiles/android/harness/termux/codebase-map.json")
    artifacts = load("tooling/profiles/android/harness/termux/artifact-registry.json")
    workflow_path = "tooling/profiles/android/harness/termux/workflows/recover-modal-terminal-state.workflow.json"
    fixture_path = "tooling/profiles/android/harness/termux/fixtures/nano-modal-editor.fixture.txt"
    inspector_path = "tooling/profiles/android/harness/termux/Inspect-TerminalState.sh"
    workflow = load(workflow_path)

    assert manifest["components"]["terminalStateInspector"] == inspector_path
    assert workflow_path in manifest["components"]["workflows"]
    assert fixture_path in manifest["components"]["fixtures"]
    assert manifest["components"]["modalStatePortableTest"] == "tests/test_android_termux_modal_state_harness.py"
    assert manifest["components"]["modalStateCompletenessValidator"] == "scripts/Test-AndroidTermuxModalStateHarness.ps1"
    assert any(item["id"] == "nano-modal-editor" for item in manifest["knownFailureSignatures"])

    assert workflow["workflowId"] == "android-termux-recover-modal-terminal-state"
    workflow_text = json.dumps(workflow)
    for token in ("expected next screen", "pane_current_command=nano", "Ctrl+X", "N to discard", "Y then Enter", "shell-bootstrap-text", "PHONE_SHELL_READY", "agentswitchboard-android sprint --prompt-file"):
        assert token in workflow_text, token
    assert "does not prove provider/model behavior" in workflow["proofCeiling"]

    inspector = tracked(inspector_path).read_text(encoding="utf-8")
    for token in ("pane_current_command", "CLASSIFICATION=modal-editor:nano", "HUNG_CLAIM=no", "Ctrl+X", "N discards changes", "Y then Enter saves", "PROMPT_FILE_RULE"):
        assert token in inspector, token
    subprocess.run(["bash", "-n", str(ROOT / inspector_path)], check=True)

    fixture = tracked(fixture_path).read_text(encoding="utf-8")
    for token in ("CLASSIFICATION=modal-editor:nano", "HUNG_CLAIM=no", "^X Exit", "N=discard", "Y then Enter=save", "PROMPT_FILE_RULE", "REQUIRED_RECOVERY"):
        assert token in fixture, token

    artifact_ids = {item["artifactId"] for item in artifacts["artifacts"]}
    assert "terminal-state-report" in artifact_ids
    assert "modalState" in artifacts["capturePolicy"]

    commands = json.dumps(codebase["operatorCommands"])
    for token in ("Inspect-TerminalState.sh", "Ctrl+X", "PHONE_SHELL_READY"):
        assert token in commands, token
    traps = "\n".join(codebase["knownTraps"])
    for token in ("modal editor waiting for input", "Every instruction that opens a modal surface", "content of sprint.md"):
        assert token in traps, token

    skill = tracked(".ai/skills/android-termux-terminal-recovery/SKILL.md").read_text(encoding="utf-8")
    for token in ("version: 1.1.0", "Inspect-TerminalState.sh", "modal-editor:nano", "Ctrl+X", "PHONE_SHELL_READY", "shell-bootstrap"):
        assert token in skill, token

    guide = tracked("docs/harness/android-termux-operational-harness.md").read_text(encoding="utf-8")
    for token in ("Modal terminal state is not a hang by default", "Inspect-TerminalState.sh", "Sprint prompt boundary", "Ctrl+X", "PHONE_SHELL_READY"):
        assert token in guide, token

    report = tracked("tooling/profiles/android/harness/termux/operator-report.template.md").read_text(encoding="utf-8")
    for token in ("Foreground command", "Terminal state", "Hung claim", "Exit contract", "Prompt file classification"):
        assert token in report, token

    print("PASS: Android Termux modal-state harness contracts")


if __name__ == "__main__":
    main()
