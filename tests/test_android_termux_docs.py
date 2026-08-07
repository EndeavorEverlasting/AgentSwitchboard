#!/usr/bin/env python3
"""Dependency-free operator-documentation contracts for Android/Termux."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "docs/workstation/android-termux.md"
LIVE = ROOT / "docs/workstation/android-ssh-tmux-live-cert.md"
INDEX = ROOT / "docs/workstation/README.md"
LAUNCHER = ROOT / "tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh"
BOOTSTRAP = ROOT / "Bootstrap-AgentSwitchboard-Termux.sh"
WORKFLOW = ROOT / ".github/workflows/android-termux-shell-contract.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_tokens(text: str, tokens: tuple[str, ...], label: str) -> None:
    for token in tokens:
        require(token in text, f"{label}: missing {token!r}")


def main() -> None:
    for path in (MAIN, LIVE, INDEX, LAUNCHER, BOOTSTRAP, WORKFLOW):
        require(path.is_file(), f"missing {path.relative_to(ROOT)}")

    main_doc = MAIN.read_text(encoding="utf-8")
    live_doc = LIVE.read_text(encoding="utf-8")
    index_doc = INDEX.read_text(encoding="utf-8")
    launcher = LAUNCHER.read_text(encoding="utf-8")
    bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    require_tokens(
        main_doc,
        (
            "F-Droid",
            "com.termux",
            "command -v pkg",
            'pkg install -y git',
            'git clone https://github.com/EndeavorEverlasting/AgentSwitchboard.git',
            "Bootstrap-AgentSwitchboard-Termux.sh",
            "--plan",
            "Execution hold",
            "agentswitchboard-phone status",
            "agentswitchboard-phone local-shell --session phone-code",
            "continuity_scope=device-local-only",
            "git diff --cached --check",
            'git commit -m "docs: describe the change"',
            "native Android AgentSwitchboard orchestration: `unimplemented`",
            "Push boundary",
            "Rollback",
            "Troubleshooting",
            "Evidence and proof ceiling",
            "android-ssh-tmux-live-cert.md",
        ),
        "android-termux-guide",
    )

    require_tokens(
        live_doc,
        (
            "Manual phone → Windows laptop SSH transport certificate",
            "Get-Service -Name sshd -ErrorAction SilentlyContinue",
            "Get-NetTCPConnection -LocalPort 22 -State Listen",
            "ssh WINDOWS_USER@WINDOWS_LAN_IP",
            "Manual Windows → WSL → tmux continuity certificate",
            "wsl",
            "tmux new-session -A -s dev",
            "socket=#{socket_path}",
            "Repo-owned Android remote launcher to a POSIX/tmux endpoint",
            "agentswitchboard-phone remote HOST",
            "--host-profile posix-tmux",
            "--expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
            "--create",
            "remote-preflight.env",
            "tmux_status=ready",
            "working_tree_status=clean",
            "attachment_observed=false",
            "Proof ceiling",
        ),
        "android-live-cert-guide",
    )

    # The operator guide must keep Windows OpenSSH distinct from the current
    # POSIX remote adapter so users are not handed a command that cannot work.
    require(
        "Windows OpenSSH endpoint is **not** the same thing as this POSIX adapter" in main_doc,
        "main guide must distinguish Windows SSH from posix-tmux adapter",
    )
    require(
        "A normal Windows OpenSSH endpoint" in live_doc
        and "not a supported `--host-profile posix-tmux` target" in live_doc,
        "live guide must distinguish Windows SSH transport from launcher support",
    )

    # Current CLI examples in the docs must correspond to implemented surfaces.
    for token in (
        "status",
        "local-shell",
        "remote",
        "--session",
        "--host-profile",
        "posix-tmux",
        "--repo",
        "--expected-origin",
        "--create",
        "--plan",
    ):
        require(token in launcher, f"documented launcher token is not implemented: {token}")

    for token in ("--repo", "--ref", "--plan", "git", "openssh", "tmux", "curl"):
        require(token in bootstrap, f"documented bootstrap token is not implemented: {token}")

    # Safety/proof wording must remain explicit.
    for text, label in ((main_doc, "main"), (live_doc, "live")):
        lowered = text.lower()
        require("host-key" in lowered, f"{label}: host-key safety guidance missing")
        require("password" in lowered or "credential" in lowered, f"{label}: secret boundary missing")
        require("proof" in lowered, f"{label}: proof boundary missing")

    require_tokens(
        index_doc,
        (
            "android-termux.md",
            "android-ssh-tmux-live-cert.md",
            "frontend -> transport -> workspace host -> orchestration runtime -> agent runtime",
        ),
        "workstation-index",
    )

    # Documentation changes must trigger the focused CI gate and the doc test
    # must actually execute there.
    require_tokens(
        workflow,
        (
            '"docs/workstation/android-termux.md"',
            '"docs/workstation/android-ssh-tmux-live-cert.md"',
            '"docs/workstation/README.md"',
            '"tests/test_android_termux_docs.py"',
            "python3 tests/test_android_termux_docs.py",
        ),
        "android-workflow",
    )

    print("PASS: Android Termux operator documentation contracts")


if __name__ == "__main__":
    main()
