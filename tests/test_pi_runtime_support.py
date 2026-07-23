#!/usr/bin/env python3
"""Dependency-free contracts for AgentSwitchboard Pi runtime support."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing: {relative}"
    return path.read_text(encoding="utf-8-sig")


def load(relative: str) -> dict:
    return json.loads(read(relative))


def require(text: str, token: str, label: str) -> None:
    assert token in text, f"missing {label}: {token}"


def main() -> None:
    verification = load("tooling/pi/harness/upstream-verification.json")
    registry = load("tooling/pi/harness/pi-adapter.registry.json")
    settings = load(".pi/settings.json")
    installer = read("tooling/pi/Install-AgentSwitchboardPi.ps1")
    launcher = read("tooling/pi/Start-AgentSwitchboardPi.ps1")
    install_cmd = read("Install-AgentSwitchboardPi.cmd")
    start_cmd = read("Start-AgentSwitchboardPi.cmd")
    status = read("tooling/pi/Get-PiHarnessStatus.ps1")

    assert verification["schema"] == "agentswitchboard.pi-upstream-verification.v1"
    assert verification["package"] == "@earendil-works/pi-coding-agent"
    assert verification["version"] == "0.81.1"
    assert verification["sourceRepository"] == "earendil-works/pi"
    assert verification["minimumNodeVersion"] == "22.19.0"
    assert "--ignore-scripts" in verification["installCommand"]
    assert verification["providerPolicy"].startswith("The Pi CLI is free")

    upstream = registry["upstream"]
    assert upstream["package"] == verification["package"]
    assert upstream["pinnedVersion"] == verification["version"]
    assert upstream["minimumNodeVersion"] == verification["minimumNodeVersion"]
    assert upstream["status"] == "verified-install-supported"
    assert registry["configuration"]["globalConfigurationMutationAllowed"] is False
    assert registry["configuration"]["projectTrustBypassAllowed"] is False
    assert registry["configuration"]["lifecycleScriptsAllowed"] is False
    assert registry["runtimeSurfaces"]["installer"] == "tooling/pi/Install-AgentSwitchboardPi.ps1"
    assert registry["runtimeSurfaces"]["launcher"] == "tooling/pi/Start-AgentSwitchboardPi.ps1"
    assert registry["freeAccessPolicy"]["providerAccessIsSeparate"] is True
    route_status = {route["routeId"]: route["status"] for route in registry["routes"]}
    assert route_status["pi-single-agent"] == "launcher-supported-runtime-unproved"
    assert route_status["pi-opinion-fusion"] == "contract-only"
    assert route_status["pi-autovalidate"] == "contract-only"

    assert settings["enableInstallTelemetry"] is False
    assert settings["enableSkillCommands"] is True
    assert settings["skills"] == ["../.ai/skills"]
    assert settings["packages"] == []
    assert settings["extensions"] == []

    installer_tokens = {
        "verified record": "upstream-verification.json",
        "exact package": "$packageSpec",
        "lifecycle scripts disabled": "--ignore-scripts",
        "minimum Node": "$minimumNodeVersion",
        "node version check": "Node version probe",
        "native npm": "@('npm.cmd', 'npm.exe', 'npm')",
        "Windows cmd execution": "ConvertTo-CmdToken",
        "exact Pi readback": "Pi version mismatch after operation",
        "npm package readback": "npm package readback failed",
        "install mode": "'Install'",
        "verify mode": "'Verify'",
        "uninstall mode": "'Uninstall'",
        "no auth mutation": "authenticationMutation = 'none'",
        "no config mutation": "configurationMutation = 'none'",
        "outside-repo evidence": "AgentSwitchboard/PiHarness/install",
    }
    for label, token in installer_tokens.items():
        require(installer, token, label)

    launcher_tokens = {
        "exact version": "Pi version mismatch",
        "bash resolver": "Resolve-BashCommand",
        "Git Bash path": "Git/bin/bash.exe",
        "bash version probe": "$bashPath --version",
        "telemetry opt-out": "$env:PI_TELEMETRY = '0'",
        "version check opt-out": "$env:PI_SKIP_VERSION_CHECK = '1'",
        "offline option": "$env:PI_OFFLINE = '1'",
        "external sessions": "$env:PI_CODING_AGENT_SESSION_DIR = $sessionRoot",
        "project trust visible": "Pi may ask whether to trust this repository",
        "trust not bypassed": "never bypassed by this launcher",
        "raw args excluded": "rawArgumentsRecorded = $false",
        "raw prompt excluded": "rawPromptRecorded = $false",
        "repo cwd": "Push-Location -LiteralPath $RootPath",
    }
    for label, token in launcher_tokens.items():
        require(launcher, token, label)

    for forbidden in (
        "--approve",
        "defaultProjectTrust",
        "auth.json",
        "models.json",
        "dangerously-skip-permissions",
    ):
        assert forbidden not in launcher, f"launcher contains forbidden trust/auth shortcut: {forbidden}"

    assert "Install-AgentSwitchboardPi.ps1" in install_cmd
    assert "Start-AgentSwitchboardPi.ps1" in start_cmd
    assert 'cd /d "%~dp0"' in install_cmd
    assert 'cd /d "%~dp0"' in start_cmd

    for token in (
        "runtime-ready-provider-unproved",
        "installable",
        "minimumNodeVersion",
        "tests/test_pi_runtime_support.py",
        "Start-AgentSwitchboardPi.ps1",
        "Resolve-BashCommand",
        "shell = [ordered]",
        "Node/npm/bash readiness",
    ):
        require(status, token, "runtime-aware status")

    combined = "\n".join((installer, launcher, install_cmd, start_cmd))
    for pattern in (
        r"npm\s+install\s+-g\s+@mariozechner/pi-coding-agent",
        r"npm\s+install\s+-g(?![^\n]*--ignore-scripts)",
        r"\.pi[/\\]auth\.json",
        r"\.pi[/\\]models\.json",
    ):
        assert not re.search(pattern, combined, re.IGNORECASE), f"forbidden Pi runtime pattern: {pattern}"

    print("PASS: AgentSwitchboard Pi runtime support contracts")


if __name__ == "__main__":
    main()
