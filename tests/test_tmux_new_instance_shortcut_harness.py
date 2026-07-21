#!/usr/bin/env python3
"""Dependency-free contracts for the tmux new-instance desktop shortcut."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
PREFIX = "tooling/profiles/windows/harness/tmux-new-instance-shortcut"


def text(path: str) -> str:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    return target.read_text(encoding="utf-8-sig")


def load(path: str) -> dict:
    return json.loads(text(path))


def allocate(prefix: str, existing: list[str], requested: str, maximum: int) -> str:
    present = set(existing)
    if requested != "auto":
        candidate = f"{prefix}-{requested}"
        if candidate in present:
            raise ValueError("already exists")
        return requested
    for index in range(1, maximum + 1):
        if f"{prefix}-{index}" not in present:
            return str(index)
    raise ValueError("No free tmux instance")


def main() -> None:
    manifest = load("tooling/profiles/windows/tmux-new-instance-shortcut.example.json")
    registry = load(f"{PREFIX}/shortcut-profile.registry.json")
    artifacts = load(f"{PREFIX}/artifact-registry.json")
    graph = load(f"{PREFIX}/composition.graph.json")
    schema = load(f"{PREFIX}/schemas/tmux-new-instance-shortcut.schema.json")

    assert manifest["schema"] == "agentswitchboard.tmux-new-instance-shortcut-manifest.v1"
    assert manifest["profileId"] == "windows"
    assert manifest["runtimeMode"] == "new-instance"
    assert manifest["instanceId"] == "auto"
    assert manifest["sessionPrefix"] == "dev"
    assert manifest["allocationPolicy"] == "smallest-positive-integer"
    assert manifest["openOrActivateImplementation"] == (
        "blocked-until-separate-runtime-sprint"
    )
    assert manifest["generatedEvidenceTracked"] is False

    assert registry["canonicalOwner"] == "EndeavorEverlasting/AgentSwitchboard"
    assert registry["canonicalLauncher"] == (
        "tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1"
    )
    assert registry["shortcut"]["delegatesToCanonicalLauncher"] is True
    assert registry["shortcut"]["mode"] == "new-instance"
    assert registry["shortcut"]["instanceId"] == "auto"
    assert registry["shortcut"]["foreignShortcutOverwriteAllowed"] is False
    assert registry["shortcut"]["installationLaunchesRuntime"] is False
    assert registry["sessionAllocation"]["bareSessionReservedForDefaultMode"] == "dev"
    assert registry["sessionAllocation"]["newInstancePattern"] == (
        "dev-<positive-integer>"
    )
    assert registry["sessionAllocation"]["reuseExistingNamedInstanceAllowed"] is False
    assert registry["sessionAllocation"]["mutexRequired"] is True
    assert registry["wezterm"]["alwaysNewProcessRequired"] is True
    assert registry["wezterm"]["rawShortcutInvocationAllowed"] is False
    assert registry["tmux"]["sameSessionMultipleWindowsIsNewInstance"] is False
    assert registry["tmux"]["packageInstallationOwned"] is False

    assert artifacts["tracked"] is False
    assert artifacts["sensitivity"] == "local-operational"
    artifact_ids = {item["artifactId"] for item in artifacts["artifacts"]}
    assert artifact_ids == {
        "tmux-new-instance-shortcut-install-plan",
        "tmux-new-instance-shortcut-install-receipt",
        "tmux-new-instance-shortcut-operator-report",
        "tmux-new-instance-launch-plan",
        "tmux-new-instance-launch-result",
        "tmux-new-instance-final-handoff",
    }
    assert schema["$defs"]["manifest"]["additionalProperties"] is False

    workflows = {
        "install-shortcut.workflow.json": "install-tmux-new-instance-shortcut",
        "launch-new-instance.workflow.json": "launch-tmux-new-instance",
        "handle-failure.workflow.json": "handle-tmux-new-instance-shortcut-failure",
    }
    for filename, workflow_id in workflows.items():
        workflow = load(f"{PREFIX}/workflows/{filename}")
        assert workflow["schema"] == (
            "agentswitchboard.tmux-new-instance-shortcut-workflow.v1"
        )
        assert workflow["workflowId"] == workflow_id
        assert len(workflow["steps"]) >= 7
        assert workflow["proofCeiling"]

    fixtures = [
        load(f"{PREFIX}/fixtures/valid-empty-session-inventory.fixture.json"),
        load(f"{PREFIX}/fixtures/valid-existing-sessions.fixture.json"),
        load(f"{PREFIX}/fixtures/invalid-existing-explicit-instance.fixture.json"),
    ]
    for fixture in fixtures:
        try:
            instance_id = allocate(
                manifest["sessionPrefix"],
                fixture["existingSessions"],
                fixture["requestedInstanceId"],
                manifest["maximumInstances"],
            )
        except ValueError as exc:
            assert fixture["expectedValid"] is False
            assert fixture["expectedError"] in str(exc)
        else:
            assert fixture["expectedValid"] is True
            assert instance_id == fixture["expectedInstanceId"]
            assert f"{manifest['sessionPrefix']}-{instance_id}" == (
                fixture["expectedSessionName"]
            )

    assert allocate("dev", [], "auto", 64) == "1"
    assert allocate("dev", ["dev", "dev-1", "dev-3"], "auto", 64) == "2"
    assert allocate("dev", ["dev-1", "dev-2"], "3", 64) == "3"
    try:
        allocate("dev", ["dev-2"], "2", 64)
    except ValueError as exc:
        assert "already exists" in str(exc)
    else:
        raise AssertionError("existing explicit instance was reused")

    installer_cmd = text("Install-TmuxNewInstanceShortcut.cmd")
    assert 'cd /d "%~dp0"' in installer_cmd
    assert 'set "MODE=Apply"' in installer_cmd
    assert "Install-TmuxNewInstanceShortcut.ps1" in installer_cmd
    assert "pwsh.exe -NoLogo -NoProfile" in installer_cmd
    assert "wezterm.exe start" not in installer_cmd.lower()
    assert "tmux new-session" not in installer_cmd.lower()

    installer = text("tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1")
    for token in (
        "Invoke-AgentSwitchboardOpenOrActivate.ps1",
        "New-Object -ComObject WScript.Shell",
        "Existing foreign shortcut was preserved",
        "-Mode new-instance",
        "-InstanceId auto",
        "runtimeExecuted = $false",
        "launchesDuringInstall = $false",
    ):
        assert token in installer
    assert "Start-Process" not in installer
    assert "tmux new-session" not in installer

    launcher = text(
        "tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1"
    )
    for token in (
        "--always-new-process",
        "tmux new-session -d",
        "tmux attach-session",
        "Local\\AgentSwitchboard.TmuxNewInstance",
        "smallest unused positive",
        "The default open-or-activate path remains blocked",
        "visibleWindowObserved = $false",
        "proofLevel = 'command-ack'",
    ):
        assert token in launcher
    assert "tmux new-session -A" not in launcher
    assert "tmux new -A" not in launcher
    assert "C:\\Users\\" not in launcher
    assert "/home/cheex" not in launcher

    node_ids = {item["id"] for item in graph["nodes"]}
    edge_ids = {item["id"] for item in graph["edges"]}
    assert {
        "cmd.tmux-shortcut-installer",
        "installer.tmux-shortcut",
        "launcher.windows-profile",
        "workflow.tmux-shortcut-install",
        "workflow.tmux-new-instance-launch",
        "validator.tmux-shortcut",
        "artifact.tmux-launch-result",
    }.issubset(node_ids)
    assert {
        "edge.tmux-cmd-installer",
        "edge.tmux-shortcut-launcher",
        "edge.tmux-launcher-workflow",
        "edge.tmux-launch-result",
        "edge.tmux-validator-launcher",
    }.issubset(edge_ids)

    skill = text(".ai/skills/tmux-new-instance-shortcut/SKILL.md")
    for heading in (
        "## Trigger",
        "## Required inputs",
        "## Procedure",
        "## Expected outputs",
        "## Deterministic validation",
        "## Proof promotion",
        "## Forbidden scope",
        "## Stop and escalate",
    ):
        assert heading in skill

    central = load(".ai/harness/manifest.json")
    entrypoints = central["entrypoints"]
    assert entrypoints["tmuxNewInstanceShortcutCommand"] == (
        "Install-TmuxNewInstanceShortcut.cmd"
    )
    assert entrypoints["tmuxNewInstanceShortcutInstaller"] == (
        "tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1"
    )
    assert entrypoints["windowsProfileCanonicalLauncher"] == (
        "tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1"
    )
    shortcut_manifest = central["tmuxNewInstanceShortcut"]
    assert shortcut_manifest["status"] == "tracked-unproven-runtime"
    assert shortcut_manifest["defaultInstallerMode"] == "Apply"
    assert shortcut_manifest["runtimeMode"] == "new-instance"
    assert shortcut_manifest["generatedEvidenceTracked"] is False

    assert "tmux new-instance desktop shortcut harness" in text("CODEBASE_MAP.md").lower()
    assert "tmux-new-instance-shortcut" in text("SKILLS.md")
    triggers = text("TRIGGERS.md")
    assert "profile.tmux-new-instance-shortcut.install" in triggers
    assert "profile.tmux-new-instance-shortcut.double-click" in triggers

    forbidden = (
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "git push",
        "gh pr merge",
        "Remove-Item -Recurse",
    )
    deployable = "\n".join(
        (
            installer_cmd,
            installer,
            launcher,
            text("tooling/profiles/windows/tmux-new-instance-shortcut.example.json"),
        )
    )
    for token in forbidden:
        assert token not in deployable

    print("PASS: tmux new-instance shortcut harness contracts")


if __name__ == "__main__":
    main()
