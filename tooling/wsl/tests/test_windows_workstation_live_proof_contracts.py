#!/usr/bin/env python3
"""Dependency-free static contracts for the Windows workstation live-proof lane."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WSL = ROOT / "tooling" / "wsl"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    paths = {
        "root_cmd": ROOT / "Run-WindowsWorkstationLiveProof.cmd",
        "proof": WSL / "Invoke-WindowsWorkstationLiveProof.ps1",
        "common": WSL / "WindowsWorkstationLiveProof.Common.psm1",
        "session": WSL / "Invoke-WindowsWorkstationSessionProof.ps1",
        "gnhf": WSL / "Invoke-WindowsWorkstationGnhfProof.ps1",
        "installer": WSL / "Install-WindowsWorkstationLiveProof.ps1",
        "validator": WSL / "Test-WindowsWorkstationLiveProofContracts.ps1",
        "manifest": WSL / "tmux-gnhf-workstation.example.json",
        "schema": WSL / "schemas" / "windows-workstation-live-proof.schema.json",
        "guide": ROOT / "docs" / "workstation" / "windows-workstation-live-proof.md",
        "workflow": ROOT / ".github" / "workflows" / "windows-workstation-live-proof-contracts.yml",
    }
    for name, path in paths.items():
        require(path.is_file(), f"missing {name}: {path.relative_to(ROOT)}")

    manifest = json.loads(text(paths["manifest"]))
    schema = json.loads(text(paths["schema"]))
    require(manifest["schemaVersion"] == 1, "workstation manifest schema must remain version 1")
    require(manifest["workspace"]["sessionName"] == "dev", "managed session must remain dev")
    require(schema["properties"]["schemaVersion"]["const"] == "agentswitchboard-windows-workstation-live-proof/v1", "proof schema version mismatch")
    for field in ("proofLevel", "proof", "handoff", "failureReason"):
        require(field in schema["required"], f"proof schema must require {field}")

    proof = "\n".join(text(paths[name]) for name in ("proof", "common", "session", "gnhf"))
    for token in (
        "'status','--short'",
        "'diff','--check'",
        "Start-TmuxGnhfWorkspace.ps1",
        "Get-TmuxGnhfWorkspaceStatus.ps1",
        "tmux new-session",
        "tmux send-keys",
        "tmux capture-pane",
        "tmux detach-client",
        "--always-new-process",
        "tmux capture-pane",
        "opencode auth list",
        "opencode models --refresh",
        "WSL OpenCode did not report authenticated DeepSeek credentials",
        "deepseek/deepseek-v4-pro",
        "OPENCODE_CONFIG_CONTENT",
        "share='disabled'",
        "GNHF_TELEMETRY=0",
        "--worktree",
        "--max-iterations",
        "--max-tokens",
        "--prevent-sleep",
        "disposable-repo",
        "agent-runtime-proof.json",
        "AGENTSWITCHBOARD_GNHF_STARTED",
        "AGENTSWITCHBOARD_GNHF_EXIT",
        "AGENTSWITCHBOARD_GNHF_FINISHED",
        "live-windows-wsl-tmux-gnhf-behavior-observed",
        "live-wezterm-wsl-tmux-session-persistence",
        "readyForAutomatedAgents",
        "readyForSysAdminSuiteTandem",
        "destructive_stop_skipped_persistent_session_reuse_is_repo_doctrine",
        "no pixel-level GUI rendering claim",
    ):
        require(token in proof, f"runtime proof missing contract token: {token}")
    for forbidden in ("Read-Host", "System.Windows.Forms.SendKeys", "--push", "reset --hard", "wsl --unregister"):
        require(forbidden not in proof, f"runtime proof contains forbidden behavior: {forbidden}")

    installer = text(paths["installer"])
    for token in (
        "[switch]$Apply",
        "[switch]$RunAfterInstall",
        "status --short",
        "Core workstation dependency is missing",
        "Start-TmuxGnhfWorkspace.ps1",
        "Get-TmuxGnhfWorkspaceStatus.ps1",
        "state\\setup-summary.json",
        "windows-workstation-live-proof.config.json",
        "Run-WindowsWorkstationLiveProof.cmd",
        "-PlanOnly",
        "detached-plan-only",
        "Detached source checkout is not allowed when applying",
        "sourceAttached = $sourceAttached",
        "automaticAuthentication = $false",
        "automaticPush = $false",
    ):
        require(token in installer, f"installer missing contract token: {token}")

    cmd = text(paths["root_cmd"])
    require("Setup-TmuxGnhfWorkspace.cmd" in cmd and " apply" in cmd, "root CMD must deploy/reuse the core workspace first")
    require("Install-WindowsWorkstationLiveProof.ps1" in cmd, "root CMD must install the proof lane")
    require('if "%_setup_code%"=="30"' in cmd, "root CMD must preserve reboot/resume handling")
    require("pause >nul" in cmd, "root CMD must keep failures visible")

    scanned = "\n".join(text(paths[name]) for name in ("root_cmd", "proof", "common", "session", "gnhf", "installer", "manifest", "schema"))
    for token in ("DEEPSEEK_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "access_token", "refresh_token"):
        require(token not in scanned, f"credential token must not be present: {token}")

    guide = text(paths["guide"])
    for token in (
        "Proof levels",
        "One-click deployment and proof",
        "SysAdminSuite handoff",
        "No terminal focus",
        "Exact artifacts",
        "Reboot and resume",
    ):
        require(token in guide, f"operator guide missing section/token: {token}")

    for path in paths.values():
        raw = path.read_bytes()
        require(b"\r\n" not in raw, f"CRLF detected in tracked source: {path.relative_to(ROOT)}")
        require(all(not line.endswith(b" ") and not line.endswith(b"\t") for line in raw.splitlines()), f"trailing whitespace: {path.relative_to(ROOT)}")

    print("PASS: Windows workstation live-proof static contracts")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
