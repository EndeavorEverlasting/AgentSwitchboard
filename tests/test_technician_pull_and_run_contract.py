from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CMD_PATH = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"
SETUP_PATH = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        raise AssertionError(f"missing {label}: {token}")


def main() -> None:
    if not CMD_PATH.is_file():
        raise AssertionError(f"missing technician CMD: {CMD_PATH}")
    if not SETUP_PATH.is_file():
        raise AssertionError(f"missing technician setup script: {SETUP_PATH}")

    cmd = CMD_PATH.read_text(encoding="utf-8")
    setup = SETUP_PATH.read_text(encoding="utf-8")

    cmd_requirements = {
        "canonical repository": "https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
        "user-relative default": "%USERPROFILE%\\Desktop\\dev\\AgentSwitchboard",
        "clone": "git clone --branch",
        "fetch": "fetch --all --prune",
        "fast-forward pull": "pull --ff-only",
        "dirty checkout detection": "status --porcelain=v1 --untracked-files=normal",
        "detached checkout detection": "symbolic-ref --quiet --short HEAD",
        "freshly pulled handoff": "--repo-ready",
        "shell mode": '"shell"',
        "AGY mode": '"agy"',
        "OpenCode mode": '"opencode"',
        "setup mode": '"setup"',
        "PowerShell helper": "Setup-TechnicianAgentSwitchboard.ps1",
    }
    for label, token in cmd_requirements.items():
        require(cmd, token, label)

    for forbidden in (
        r"\bgit\s+reset\b",
        r"\bgit\s+clean\b",
        r"\bgit\s+stash\b",
        r"push\s+--force",
        r"force-push",
    ):
        if re.search(forbidden, cmd, re.IGNORECASE):
            raise AssertionError(f"destructive Git behavior is forbidden: {forbidden}")

    setup_requirements = {
        "Windows guard": "The technician Windows Profile setup must run on Windows.",
        "official WezTerm package": "wez.wezterm",
        "official AGY installer": "https://antigravity.google/cli/install.sh",
        "official OpenCode installer": "https://opencode.ai/install",
        "Ubuntu distribution": "[string]$Distribution = 'Ubuntu'",
        "tmux verification": "tmux -V",
        "AGY verification": "agy --version",
        "OpenCode verification": "opencode --version",
        "tmux environment refresh": "tmux set-environment -g PATH",
        "canonical launcher": "Invoke-AgentSwitchboardOpenOrActivate.ps1",
        "canonical mode": "-Mode open-or-activate",
        "canonical operation": "-Operation Launch",
        "shell mode": "'shell'",
        "AGY mode": "'agy'",
        "OpenCode mode": "'opencode'",
        "setup-only mode": "'setup'",
        "untracked local evidence": "AgentSwitchboard\\technician-quickstart\\runs",
        "proof ceiling": "proofCeiling",
    }
    for label, token in setup_requirements.items():
        require(setup, token, label)

    forbidden_setup_patterns = (
        r"git\s+reset",
        r"git\s+clean",
        r"git\s+stash",
        r"wezterm(?:\.exe)?\s+start",
        r"Remove-Item\s+.*\.tmux",
        r"Remove-Item\s+.*\.wezterm",
    )
    for forbidden in forbidden_setup_patterns:
        if re.search(forbidden, setup, re.IGNORECASE):
            raise AssertionError(f"setup bypasses an ownership or safety boundary: {forbidden}")

    print("PASS: technician pull-and-run CMD contract")


if __name__ == "__main__":
    main()
