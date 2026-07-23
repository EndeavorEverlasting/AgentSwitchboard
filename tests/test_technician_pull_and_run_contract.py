from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CMD_PATH = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"
SETUP_PATH = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
LIVE_CERT_FIXTURE = (
    ROOT
    / "tooling"
    / "profiles"
    / "windows"
    / "harness"
    / "live-certification"
    / "fixtures"
    / "technician-quickstart-2026-07-22-fail.fixture.json"
)
LIVE_CERT_SKILL = ROOT / ".ai" / "skills" / "windows-profile-live-certification" / "SKILL.md"
AGENTS_PATH = ROOT / "AGENTS.md"


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        raise AssertionError(f"missing {label}: {token}")


def main() -> None:
    for path in (CMD_PATH, SETUP_PATH, LIVE_CERT_FIXTURE, LIVE_CERT_SKILL, AGENTS_PATH):
        if not path.is_file():
            raise AssertionError(f"missing technician contract file: {path}")

    cmd = CMD_PATH.read_text(encoding="utf-8")
    setup = SETUP_PATH.read_text(encoding="utf-8")
    fixture = LIVE_CERT_FIXTURE.read_text(encoding="utf-8")
    skill = LIVE_CERT_SKILL.read_text(encoding="utf-8")
    agents = AGENTS_PATH.read_text(encoding="utf-8")

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
        "explicit Hermes mode": '"hermes"',
        "PowerShell helper": "Setup-TechnicianAgentSwitchboard.ps1",
        "fresh-shell command guidance": "wezterm, tmux, agy, and opencode",
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
        "WinGet link resolution": "Microsoft\\WinGet\\Links",
        "WinGet package resolution": "Microsoft\\WinGet\\Packages",
        "official AGY installer": "curl -fsSL https://antigravity.google/cli/install.sh | bash",
        "official OpenCode installer": "curl -fsSL https://opencode.ai/install | bash",
        "official Hermes installer": "https://hermes-agent.nousresearch.com/install.ps1",
        "Ubuntu distribution": "[string]$Distribution = 'Ubuntu'",
        "tmux verification": "tmux -V",
        "AGY verification": "agy --version",
        "OpenCode verification": "opencode --version",
        "absolute WSL resolution": "Get-WslCommandPath",
        "tmux environment refresh": "tmux set-environment -g PATH",
        "PowerShell command shims": "Write-CommandShim",
        "shim root": "AgentSwitchboard\\bin",
        "user PATH registration": "SetEnvironmentVariable('Path'",
        "WezTerm shim": "-Name 'wezterm'",
        "tmux shim": "-Name 'tmux'",
        "AGY shim": "-Name 'agy'",
        "OpenCode shim": "-Name 'opencode'",
        "Hermes newline injection": "$process.StandardInput.WriteLine()",
        "Hermes portal mode": "setup --portal",
        "Hermes isolated from core": "Hermes is isolated from the core WezTerm/tmux/AGY/OpenCode path",
        "canonical launcher": "Invoke-AgentSwitchboardOpenOrActivate.ps1",
        "canonical mode": "-Mode open-or-activate",
        "canonical operation": "-Operation Launch",
        "shell mode": "'shell'",
        "AGY mode": "'agy'",
        "OpenCode mode": "'opencode'",
        "setup-only mode": "'setup'",
        "Hermes mode": "'hermes'",
        "untracked local evidence": "AgentSwitchboard\\technician-quickstart\\runs",
        "proof ceiling": "proofCeiling",
    }
    for label, token in setup_requirements.items():
        require(setup, token, label)

    if "--skip-aliases" in setup:
        raise AssertionError("AGY installer must use the verified official Linux invocation without unsupported flags")

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

    fixture_requirements = (
        '"expectedOutcome": "failed"',
        '"passedStage": "opencode-installation"',
        '"failedStage": "hermes-browser-handoff"',
        '"failedStage": "agy-installation"',
        '"failedStage": "wezterm-command-resolution"',
        '"failedStage": "tmux-command-resolution"',
        '"observedAt": "2026-07-22"',
    )
    for token in fixture_requirements:
        require(fixture, token, "sanitized failed live-cert fixture")

    for text, token, label in (
        (skill, "Observed live failure outranks static and CI success", "live-cert failure precedence"),
        (skill, "exact operator shell", "shell-specific command resolution"),
        (skill, "browser handoff", "interactive browser boundary"),
        (agents, "Observed live failure outranks static, synthetic, and CI success", "governance failure precedence"),
        (agents, "Optional agent installation or browser authentication may not block", "optional-stage isolation"),
        (agents, "repo-owned shim", "cross-shell shim doctrine"),
    ):
        require(text, token, label)

    print("PASS: technician pull-and-run CMD and failed live-cert repair contract")


if __name__ == "__main__":
    main()
