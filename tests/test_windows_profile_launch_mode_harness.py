#!/usr/bin/env python3
"""Dependency-free Windows Profile launch-mode harness contracts."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(path: str) -> dict:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    return json.loads(target.read_text(encoding="utf-8-sig"))


def identity_key(window: dict) -> tuple[str, str, str | None, str]:
    identity = window["workspaceIdentity"]
    return (
        identity["profileId"],
        identity["workspaceId"],
        identity["instanceId"],
        identity["tmuxSession"],
    )


def new_windows(before: dict, after: dict) -> list[dict]:
    before_ids = {item["windowId"] for item in before["windows"]}
    return [item for item in after["windows"] if item["windowId"] not in before_ids]


def duplicate_identity(snapshot: dict) -> bool:
    keys = [identity_key(item) for item in snapshot["windows"]]
    return len(keys) != len(set(keys))


def validate_fixture(fixture: dict) -> bool:
    created = new_windows(fixture["before"], fixture["afterFirst"])
    duplicate = len(created) > 1 or duplicate_identity(fixture["afterFirst"])

    if not fixture["expectedValid"]:
        return (
            fixture["expectedOutcome"] == "duplicate-detected"
            and fixture["expectedDuplicateDetected"] is True
            and duplicate
        )

    if duplicate or len(created) != fixture["expectedNewTopLevelWindows"]:
        return False

    if fixture["mode"] == "open-or-activate":
        return (
            fixture["expectedOutcome"] == "activated"
            and len(fixture["afterSecond"]["windows"])
            == len(fixture["afterFirst"]["windows"])
        )

    if fixture["mode"] == "new-instance":
        if len(created) != 1:
            return False
        window = created[0]
        return (
            fixture["expectedOutcome"] == "new-instance-opened"
            and window["workspaceIdentity"]["instanceId"] == fixture["instanceId"]
            and window["workspaceIdentity"]["tmuxSession"] != "dev"
            and window["processId"] != fixture["before"]["windows"][0]["processId"]
            and len(fixture["afterSecond"]["windows"])
            == len(fixture["afterFirst"]["windows"])
        )

    return False


def main() -> None:
    prefix = "tooling/profiles/windows/harness/launch-modes"
    registry = load(f"{prefix}/launch-mode.registry.json")
    artifacts = load(f"{prefix}/artifact-registry.json")
    schema = load(f"{prefix}/schemas/windows-launch-mode-harness.schema.json")

    assert registry["schema"] == (
        "agentswitchboard.windows-profile-launch-mode-registry.v1"
    )
    assert registry["profileId"] == "windows"
    assert registry["canonicalOwner"] == "EndeavorEverlasting/AgentSwitchboard"
    assert registry["status"] == "contract-only"
    assert registry["defaultMode"] == "open-or-activate"
    assert registry["sameCanonicalLauncherForAllModes"] is True
    assert registry["rawFrontendInvocationAllowed"] is False

    modes = {item["modeId"]: item for item in registry["modes"]}
    assert set(modes) == {"open-or-activate", "new-instance"}
    assert modes["open-or-activate"]["requiresExplicitRequest"] is False
    assert modes["open-or-activate"]["sameIdentityConverges"] is True
    assert modes["open-or-activate"]["maximumNewTopLevelWindows"] == 1
    assert modes["new-instance"]["requiresExplicitRequest"] is True
    assert modes["new-instance"]["requiresInstanceId"] is True
    assert modes["new-instance"]["tmuxSessionIdentityMustBeUnique"] is True
    assert modes["new-instance"]["separateFrontendProcessRequired"] is True
    assert modes["new-instance"]["maximumNewTopLevelWindows"] == 1

    duplicate = registry["duplicateDetection"]
    assert duplicate["oneRequestMayCreateAtMostOneTopLevelWindow"] is True
    assert duplicate["sameWorkspaceInMultipleUnexpectedWindowsIsFailure"] is True
    assert duplicate["sameInstanceIdInMultipleWindowsIsFailure"] is True
    assert duplicate["rawProcessCountAloneIsInsufficient"] is True
    assert registry["runtimeEvidence"]["generatedEvidenceTracked"] is False

    expected_artifacts = {
        "windows-launch-mode-run-context",
        "windows-launch-before-snapshot",
        "windows-launch-after-snapshot",
        "windows-launch-mode-result",
        "windows-launch-mode-operator-report",
        "windows-launch-mode-final-handoff",
    }
    assert artifacts["tracked"] is False
    assert artifacts["sensitivity"] == "local-operational"
    assert {item["artifactId"] for item in artifacts["artifacts"]} == expected_artifacts
    assert schema["$defs"]["identity"]["additionalProperties"] is False
    assert schema["$defs"]["launchResult"]["additionalProperties"] is False

    workflows = {
        "launch-request-intake.workflow.json": "windows-launch-mode-intake",
        "open-or-activate-verification.workflow.json": (
            "open-or-activate-verification"
        ),
        "new-instance-verification.workflow.json": "new-instance-verification",
        "duplicate-window-diagnosis.workflow.json": "duplicate-window-diagnosis",
    }
    loaded_workflows = {}
    for filename, expected_id in workflows.items():
        workflow = load(f"{prefix}/workflows/{filename}")
        loaded_workflows[filename] = workflow
        assert workflow["schema"] == "agentswitchboard.windows-launch-mode-workflow.v1"
        assert workflow["workflowId"] == expected_id
        assert len(workflow["steps"]) >= 6
        assert workflow["proofCeiling"]

    intake_text = json.dumps(
        loaded_workflows["launch-request-intake.workflow.json"]
    )
    for token in (
        "requestedMode is absent",
        "open-or-activate-verification",
        "new-instance-verification",
        "duplicate-window-diagnosis",
        "same tmux session for an explicit separate instance",
    ):
        assert token in intake_text

    for filename in (
        "valid-open-or-activate.fixture.json",
        "valid-new-instance.fixture.json",
        "invalid-duplicate-burst.fixture.json",
    ):
        assert validate_fixture(load(f"{prefix}/fixtures/{filename}"))

    skill = (
        ROOT / ".ai/skills/windows-profile-launch-mode-validation/SKILL.md"
    ).read_text(encoding="utf-8")
    for token in (
        "id: windows-profile-launch-mode-validation",
        "status: canonical",
        "## Trigger",
        "## Inputs",
        "## Procedure",
        "## Outputs",
        "## Deterministic validation",
        "## Forbidden scope",
        "## Stop and escalate",
        "exactly one new top-level WezTerm window",
        "unique tmux session",
        "duplicate-window-diagnosis.workflow.json",
    ):
        assert token in skill

    manifest = load(".ai/harness/manifest.json")
    assert manifest["entrypoints"]["windowsLaunchModeRegistry"].endswith(
        "launch-mode.registry.json"
    )
    assert manifest["entrypoints"]["windowsLaunchModeValidator"] == (
        "scripts/Test-WindowsProfileLaunchModeHarness.ps1"
    )
    assert manifest["entrypoints"]["windowsLaunchModeSkill"] == (
        ".ai/skills/windows-profile-launch-mode-validation/SKILL.md"
    )
    mode_manifest = manifest["windowsProfileLaunchModes"]
    assert mode_manifest["status"] == "contract-only"
    assert mode_manifest["defaultMode"] == "open-or-activate"
    assert mode_manifest["explicitNewInstanceAllowed"] is True
    assert mode_manifest["generatedEvidenceTracked"] is False
    assert mode_manifest["runtimeExecutionAllowed"] is False

    central = load(".ai/harness/artifact-registry.json")["artifacts"]
    by_id = {item["artifactId"]: item for item in central}
    for artifact_id in expected_artifacts:
        assert artifact_id in by_id
        assert by_id[artifact_id]["tracked"] is False
        assert by_id[artifact_id]["sensitivity"] == "local-operational"

    graph = load(".ai/harness/app-composition.graph.json")
    node_ids = {item["id"] for item in graph["nodes"]}
    edge_ids = {item["id"] for item in graph["edges"]}
    assert {
        "skill.windows-launch-modes",
        "registry.windows-launch-modes",
        "workflow.windows-launch-mode-intake",
        "validator.windows-launch-modes",
        "artifact.windows-launch-mode-result",
        "artifact.windows-launch-mode-report",
    }.issubset(node_ids)
    assert {
        "edge.windows-launch-trigger-skill",
        "edge.windows-launch-skill-workflow",
        "edge.observe-windows-launch-registry",
        "edge.observe-windows-launch-validator",
        "edge.windows-launch-result",
        "edge.windows-launch-report",
    }.issubset(edge_ids)

    assert "Windows Profile launch-mode harness" in (
        ROOT / "CODEBASE_MAP.md"
    ).read_text(encoding="utf-8")
    assert "windows-profile-launch-mode-validation" in (
        ROOT / "SKILLS.md"
    ).read_text(encoding="utf-8")
    trigger_text = (ROOT / "TRIGGERS.md").read_text(encoding="utf-8")
    assert "profile.launch-mode-request" in trigger_text
    assert "profile.duplicate-window-observed" in trigger_text

    deployable_text = "\n".join(
        (ROOT / path).read_text(encoding="utf-8")
        for path in (
            f"{prefix}/codebase-map.json",
            f"{prefix}/launch-mode.registry.json",
            f"{prefix}/artifact-registry.json",
            ".ai/skills/windows-profile-launch-mode-validation/SKILL.md",
            "tooling/profiles/windows/Get-WindowsProfileLaunchModeStatus.ps1",
            "docs/harness/windows-profile-launch-mode-harness.md",
        )
    )
    for forbidden in (
        "Start-Process",
        "wezterm start",
        "wezterm-gui.exe start",
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "C:\\Users\\",
        "/home/cheex",
    ):
        assert forbidden not in deployable_text

    print("PASS: Windows Profile launch-mode harness contracts")


if __name__ == "__main__":
    main()
