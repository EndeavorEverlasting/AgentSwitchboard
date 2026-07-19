#!/usr/bin/env python3
"""Dependency-free static contracts for the Windows workstation live-proof lane."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WSL = ROOT / "tooling" / "wsl"
DEFAULT_FREE_MODEL = "opencode/deepseek-v4-flash-free"


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
        "free_installer": WSL / "Set-OpenCodeFreeDefaults.ps1",
        "free_configurator": WSL / "scripts" / "configure-opencode-free-defaults.sh",
        "validator": WSL / "Test-WindowsWorkstationLiveProofContracts.ps1",
        "manifest": WSL / "tmux-gnhf-workstation.example.json",
        "schema": WSL / "schemas" / "windows-workstation-live-proof.schema.json",
        "guide": ROOT / "docs" / "workstation" / "windows-workstation-live-proof.md",
        "free_guide": ROOT / "docs" / "workstation" / "opencode-free-model-defaults.md",
        "workflow": ROOT / ".github" / "workflows" / "windows-workstation-live-proof-contracts.yml",
    }
    for name, path in paths.items():
        require(path.is_file(), f"missing {name}: {path.relative_to(ROOT)}")

    manifest = json.loads(text(paths["manifest"]))
    schema = json.loads(text(paths["schema"]))
    require(manifest["schemaVersion"] == 1, "workstation manifest schema must remain version 1")
    require(manifest["workspace"]["sessionName"] == "dev", "managed session must remain dev")
    require(manifest["opencode"]["defaultModel"] == DEFAULT_FREE_MODEL, "workstation default must be the reviewed free OpenCode model")
    require(manifest["opencode"]["smallModel"] == DEFAULT_FREE_MODEL, "workstation small model must remain free")
    require(manifest["opencode"]["share"] == "disabled", "OpenCode sharing must remain disabled")
    require(manifest["opencode"]["restrictZenToFreeModels"] is True, "OpenCode Zen must be restricted to the free allowlist")
    require("deepseek-v4-pro" not in " ".join(manifest["opencode"]["freeModelIds"]), "paid DeepSeek V4 Pro must not enter the free allowlist")
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
        "opencode auth list",
        "opencode models --refresh",
        "Resolve-ProofOpenCodeModel",
        DEFAULT_FREE_MODEL,
        "No verified free OpenCode model was reported",
        "OPENCODE_CONFIG_CONTENT",
        "share = 'disabled'",
        "provider.opencode",
        "whitelist",
        "CostClass",
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
    require("Resolve-ProofDeepSeekModel" not in proof, "runtime proof must not use the paid-DeepSeek-first resolver")
    require("deepseek/deepseek-v4-pro" not in proof, "runtime proof must not silently prefer paid DeepSeek V4 Pro")
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

    free_installer = text(paths["free_installer"])
    for token in (
        'Join-Path $PSScriptRoot "tmux-gnhf-workstation.example.json"',
        "configure-opencode-free-defaults.sh",
        "$process.Kill($true)",
        "Installed OpenCode configuration does not match the manifest",
        "paidDefaultAllowed = $false",
    ):
        require(token in free_installer, f"free-default installer missing contract token: {token}")

    free_configurator = text(paths["free_configurator"])
    for token in (
        "~/.config/opencode/opencode.json",
        ".model = $model",
        ".small_model = $smallModel",
        ".provider.opencode.whitelist = $freeModels",
        "chmod 0600",
        "credentialsChanged: false",
    ):
        require(token in free_configurator, f"free-default configurator missing contract token: {token}")
    require("deepseek/deepseek-v4-pro" not in free_configurator, "free-default configurator must not select a paid model")

    cmd = text(paths["root_cmd"])
    require("Setup-TmuxGnhfWorkspace.cmd" in cmd and " apply" in cmd, "root CMD must deploy/reuse the core workspace first")
    require("Install-WindowsWorkstationLiveProof.ps1" in cmd, "root CMD must install the proof lane")
    require('if "%_setup_code%"=="30"' in cmd, "root CMD must preserve reboot/resume handling")
    require("pause >nul" in cmd, "root CMD must keep failures visible")

    scanned = "\n".join(text(paths[name]) for name in ("root_cmd", "proof", "common", "session", "gnhf", "installer", "free_installer", "free_configurator", "manifest", "schema"))
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

    free_guide = text(paths["free_guide"])
    for token in (
        '$RepoPath = Join-Path $HOME "Desktop\\dev\\AgentSwitchboard"',
        "Set-Location -LiteralPath $RepoPath",
        "Set-OpenCodeFreeDefaults.ps1",
        "~/.config/opencode/opencode.json",
        DEFAULT_FREE_MODEL,
        "OPENCODE_CONFIG_CONTENT",
        "--model",
        "limited-time",
    ):
        require(token in free_guide, f"free-default guide missing contract token: {token}")

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
