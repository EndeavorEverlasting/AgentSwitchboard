#!/usr/bin/env python3
"""Dependency-free contracts for the tmux + GNHF workstation integration."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WSL = ROOT / "tooling" / "wsl"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_manifest(data: dict, *, valid: bool) -> None:
    conditions = [
        data.get("schemaVersion") == 1,
        isinstance(data.get("distribution"), str) and bool(data["distribution"]),
        data.get("workspace", {}).get("sessionName") == "dev",
        data.get("node", {}).get("minimumMajor", 0) >= 20,
        data.get("gnhf", {}).get("upstreamRepository")
        == "https://github.com/kunchenguid/gnhf.git",
        data.get("gnhf", {}).get("npmPackage") == "gnhf",
        data.get("gnhf", {}).get("defaultAgent") == "opencode",
        data.get("gnhf", {}).get("safeWrapper", {}).get("worktree") is True,
        data.get("gnhf", {}).get("safeWrapper", {}).get("push") is False,
        data.get("gnhf", {}).get("safeWrapper", {}).get("maxIterations", 0) > 0,
        data.get("gnhf", {}).get("safeWrapper", {}).get("maxTokens", 0) > 0,
    ]
    require(all(conditions) is valid, f"manifest validity mismatch: expected {valid}")


def main() -> int:
    required = [
        WSL / "Install-TmuxGnhfWorkspace.ps1",
        WSL / "tmux-gnhf-workstation.example.json",
        WSL / "wsl-tmux-gnhf-base.example.json",
        WSL / "scripts" / "configure-gnhf-workspace.sh",
        WSL / "templates" / "wezterm-tmux.lua",
        WSL / "fixtures" / "tmux-gnhf-manifest.valid.json",
        WSL / "fixtures" / "tmux-gnhf-manifest.invalid.json",
        ROOT / "docs" / "workstation" / "tmux-gnhf-other-computer.md",
    ]
    for path in required:
        require(path.is_file(), f"missing required file: {path.relative_to(ROOT)}")

    validate_manifest(load_json(WSL / "tmux-gnhf-workstation.example.json"), valid=True)
    base_manifest = load_json(WSL / "wsl-tmux-gnhf-base.example.json")
    require("tmux" in base_manifest.get("packages", []), "base manifest must install tmux")
    require("xz-utils" in base_manifest.get("packages", []), "base manifest must support verified Node archives")
    require(base_manifest.get("agents") == [], "GNHF integration owns agent installation order")
    validate_manifest(load_json(WSL / "fixtures" / "tmux-gnhf-manifest.valid.json"), valid=True)
    validate_manifest(load_json(WSL / "fixtures" / "tmux-gnhf-manifest.invalid.json"), valid=False)

    bash_script = (WSL / "scripts" / "configure-gnhf-workspace.sh").read_text(encoding="utf-8")
    require("set -euo pipefail" in bash_script, "bootstrap must use strict Bash mode")
    require("https://nodejs.org/dist/index.json" in bash_script, "Node source must be official")
    require("SHASUMS256.txt" in bash_script and "sha256sum" in bash_script, "Node archive must be checksum verified")
    require("npm install --global --prefix" in bash_script, "GNHF must install into a user-owned prefix")
    require("GNHF_TELEMETRY=0" in bash_script, "telemetry-off posture must be explicit")
    require("--worktree" in bash_script and "--max-iterations" in bash_script and "--max-tokens" in bash_script, "safe wrapper must be bounded and isolated")
    require("curl |" not in bash_script and "curl -fsSL |" not in bash_script, "pipe-to-shell installation is forbidden")
    require("login" not in bash_script.lower() and "oauth" not in bash_script.lower(), "bootstrap must not authenticate")

    # Windows exposes a WSL-forwarding bash.exe that is not the Git Bash used by
    # the workflow shell. The Windows workflow performs its own explicit Bash
    # syntax step, so avoid selecting the wrong execution domain here.
    if sys.platform != "win32":
        bash_script_path = (WSL / "scripts" / "configure-gnhf-workspace.sh").as_posix()
        subprocess.run(
            ["bash", "-n", bash_script_path],
            check=True,
        )

    ps_script = (WSL / "Install-TmuxGnhfWorkspace.ps1").read_text(encoding="utf-8")
    require("[switch]$Apply" in ps_script, "apply must be explicit")
    require("$planMode = -not $Apply" in ps_script, "plan must be the default")
    require("Install-AgentSwitchboardWsl.ps1" in ps_script, "existing WSL bootstrap must be reused")
    require("wezterm-gui.exe" in ps_script, "daily launcher must target the GUI executable")
    require("keepAliveProcessName" in ps_script and "sleep infinity" in ps_script, "persistent WSL lifecycle must be owned")
    require("Get-CimInstance Win32_Process" in ps_script, "PID ownership must verify the command line")
    require("ConfirmImpact = 'High'" in ps_script, "Stop must be explicitly destructive")
    require("--unregister" not in ps_script and "reset --hard" not in ps_script, "destructive reset is forbidden")

    lua = (WSL / "templates" / "wezterm-tmux.lua").read_text(encoding="utf-8")
    require("__DISTRO__" in lua and "__SESSION__" in lua, "template placeholders are required")
    require("tmux has-session" in lua and "tmux attach-session" in lua, "WezTerm must attach to the managed session")
    require("config.font =" not in lua, "template must not require an unavailable font family")
    require("PowerShell 7" in lua, "native PowerShell fallback must remain available")

    guide = (ROOT / "docs" / "workstation" / "tmux-gnhf-other-computer.md").read_text(encoding="utf-8")
    for label in ("WINDOWS POWERSHELL 7", "WEZTERM / TMUX BASH", "FILE CONTENT", "What is automated", "Known gaps"):
        require(label in guide, f"guide is missing execution-context label: {label}")

    print("PASS: tmux + GNHF workstation contracts")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
