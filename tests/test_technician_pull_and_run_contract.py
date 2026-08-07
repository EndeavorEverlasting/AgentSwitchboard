from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOP_BOOTSTRAP = ROOT / "AgentSwitchboard-Technician-Bootstrap.cmd"
PARENT_CMD = ROOT / "Pull-Repo-And-Setup-AgentSwitchboard.cmd"
PULL_RUN_CMD = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"
READY_CMD = ROOT / "Technician-AgentSwitchboard-Ready.cmd"
COMPAT_SETUP = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
READY_ENGINE = ROOT / "tooling" / "profiles" / "windows" / "Invoke-TechnicianAgentSwitchboardReady.ps1"
PROFILE_LAUNCHER = ROOT / "tooling" / "profiles" / "windows" / "Invoke-AgentSwitchboardOpenOrActivate.ps1"
LIVE_CERT_FIXTURE = ROOT / "tooling" / "profiles" / "windows" / "harness" / "live-certification" / "fixtures" / "technician-quickstart-2026-07-22-fail.fixture.json"
LIVE_CERT_SKILL = ROOT / ".ai" / "skills" / "windows-profile-live-certification" / "SKILL.md"
DOCTRINE = ROOT / "docs" / "governance" / "live-cert-failure-doctrine.md"
TOOLCHAIN_PREFLIGHT = ROOT / "scripts" / "Test-WindowsToolchainLaunch.ps1"


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        raise AssertionError(f"missing {label}: {token}")


def reject_bare_git(text: str, label: str) -> None:
    if re.search(r"(?im)^\s*git(?:\.exe)?\s", text):
        raise AssertionError(f"{label} must not invoke bare Git from a command line")
    if re.search(r"`\s*git(?:\.exe)?\s", text, re.IGNORECASE):
        raise AssertionError(f"{label} must not invoke bare Git from command substitution")
    if re.search(r"(?im)^\s*where\s+git\.exe\b", text):
        raise AssertionError(f"{label} must not treat PATH discovery as Git launch proof")


def main() -> None:
    for path in (TOP_BOOTSTRAP, PARENT_CMD, PULL_RUN_CMD, READY_CMD, COMPAT_SETUP, READY_ENGINE, PROFILE_LAUNCHER, LIVE_CERT_FIXTURE, LIVE_CERT_SKILL, DOCTRINE, TOOLCHAIN_PREFLIGHT):
        if not path.is_file():
            raise AssertionError(f"missing technician contract file: {path}")

    top = TOP_BOOTSTRAP.read_text(encoding="utf-8")
    parent = PARENT_CMD.read_text(encoding="utf-8")
    pull_run = PULL_RUN_CMD.read_text(encoding="utf-8")
    ready_cmd = READY_CMD.read_text(encoding="utf-8")
    compat = COMPAT_SETUP.read_text(encoding="utf-8")
    ready = READY_ENGINE.read_text(encoding="utf-8")
    launcher = PROFILE_LAUNCHER.read_text(encoding="utf-8")
    fixture = LIVE_CERT_FIXTURE.read_text(encoding="utf-8")
    skill = LIVE_CERT_SKILL.read_text(encoding="utf-8")
    doctrine = DOCTRINE.read_text(encoding="utf-8")
    toolchain_preflight = TOOLCHAIN_PREFLIGHT.read_text(encoding="utf-8")

    for token in ("This is the first technician repository-acquisition command.", "Pull-And-Run-AgentSwitchboard.cmd", 'call "%BOOTSTRAP_PATH%" acquire', "%USERPROFILE%\\dev\\AgentSwitchBoard-Live", "Workstation setup is intentionally deferred"):
        require(parent, token, "parent acquisition contract")

    for token in (
        "https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
        "%USERPROFILE%\\dev\\AgentSwitchBoard-Live",
        "TOOLCHAIN_PREFLIGHT_REF=19c671837c51c2893e9eade92c340bb67e970cee",
        "EXPECTED_TOOLCHAIN_PREFLIGHT_BLOB=7110b9c6141971d93987cdb07f1ffc397e2e9f2e",
        "Test-WindowsToolchainLaunch.ps1",
        "windows-toolchain-launch-preflight.json",
        "AGENT_SWITCHBOARD_GIT_EXE",
        '"%AGENT_SWITCHBOARD_GIT_EXE%" clone --branch',
        '"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" fetch origin --prune',
        '"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" pull --ff-only',
        '"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" status --porcelain=v1 --untracked-files=normal',
        '"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" symbolic-ref --quiet --short HEAD',
        "No fetch, pull, switch, status, origin lookup, or clone was attempted.",
        "--repo-ready",
        "Setup-TechnicianAgentSwitchboard.ps1",
    ):
        require(pull_run, token, "portable pull/run contract")

    for token in ("UseShellExecute = $false", "git --version", "selectedGit", "windows-toolchain-launch-preflight.json", "exit 31"):
        require(toolchain_preflight, token, "concrete Git launch preflight")

    reject_bare_git(pull_run, "portable pull/run acquisition")
    if pull_run.index("call :resolve_git") > pull_run.index('"%AGENT_SWITCHBOARD_GIT_EXE%" -C "%REPO_ROOT%" remote get-url origin'):
        raise AssertionError("Git launch preflight must run before the first repository Git command")
    if pull_run.index("ACTUAL_TOOLCHAIN_PREFLIGHT_BLOB") > pull_run.index('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%TOOLCHAIN_PREFLIGHT_PATH%"'):
        raise AssertionError("downloaded Git-launch preflight identity must be checked before execution")

    for token in ("repo-path.txt", "AGENT_SWITCHBOARD_REPO", "Repair-Technician-WSL-Ubuntu.cmd", 'if "%REPAIR_EXIT%"=="3010"', 'call "%REPO_ROOT%\\Pull-And-Run-AgentSwitchboard.cmd" setup', 'call "%REPO_ROOT%\\Run-Technician-LiveCert.cmd"'):
        require(top, token, "first-machine bootstrap")

    acquire_index = top.index('call "%PARENT_TEMP%"')
    repair_index = top.index('call "%REPO_ROOT%\\Repair-Technician-WSL-Ubuntu.cmd"')
    setup_index = top.index('call "%REPO_ROOT%\\Pull-And-Run-AgentSwitchboard.cmd" setup')
    cert_index = top.index('call "%REPO_ROOT%\\Run-Technician-LiveCert.cmd"')
    if not (acquire_index < repair_index < setup_index < cert_index):
        raise AssertionError("bootstrap order must remain acquire -> WSL repair -> setup -> live cert")

    for text in (top, parent, pull_run, ready_cmd, ready):
        for forbidden in (r"\bgit\s+reset\b", r"\bgit\s+clean\b", r"\bgit\s+stash\b", r"push\s+--force"):
            if re.search(forbidden, text, re.IGNORECASE):
                raise AssertionError(f"destructive Git behavior is forbidden: {forbidden}")

    for token in ("Invoke-TechnicianAgentSwitchboardReady.ps1", "AgentSwitchboard technician readiness", "AgentSwitchboard -ListAgents"):
        require(ready_cmd, token, "one-command readiness CMD")

    require(compat, "Invoke-TechnicianAgentSwitchboardReady.ps1", "compatibility delegation")
    if ".Replace([char]0, '')" in compat:
        raise AssertionError("compatibility setup must not retain ambiguous NUL replacement")

    for token in ("Setup-AgentSwitchboard.ps1", "Get-AgentSwitchboardStartupReport.ps1", "AgentSwitchboard\\GnhfFleet", "state.json", "Write-CommandShim -Name 'AgentSwitchboard'", "AgentSwitchboard.lnk", "-ListAgents", "fresh-shell-agentswitchboard", "stateObserved", "proofCeiling"):
        require(ready, token, "real AgentSwitchboard readiness engine")

    if ".Replace([char]0, '')" in ready:
        raise AssertionError("readiness engine must force string/string NUL normalization")
    require(ready, ".Replace(([char]0).ToString(), [string]::Empty)", "explicit string/string NUL normalization")

    if "$PSScriptRoot" in launcher.split("Set-StrictMode", 1)[0]:
        raise AssertionError("profile launcher must not evaluate PSScriptRoot in parameter defaults")
    if ".Replace([char]0, '')" in launcher:
        raise AssertionError("profile launcher must not use ambiguous NUL replacement")

    for token in ("windows-profile-launch-plan.v2", "windows-profile-launch-result.v2", "Local\\AgentSwitchboard.TmuxNewInstance", "tmux kill-session"):
        require(launcher, token, "profile launcher safety")

    for token in ('"expectedOutcome": "failed"', '"passedStage": "opencode-installation"', '"failedStage": "hermes-browser-handoff"', '"failedStage": "agy-installation"', '"failedStage": "wezterm-command-resolution"', '"failedStage": "tmux-command-resolution"', '"observedAt": "2026-07-22"'):
        require(fixture, token, "sanitized field-failure fixture")

    require(skill, "Observed live failure outranks static and CI success", "live failure precedence")
    require(doctrine, "Observed live failure outranks static, synthetic, and CI success", "governance precedence")
    require(doctrine, "Optional agent installation or browser authentication may not block", "optional isolation")

    print("PASS: concrete Git launch proof -> portable acquisition -> prerequisite repair -> real AgentSwitchboard readiness -> live-cert contract")


if __name__ == "__main__":
    main()
