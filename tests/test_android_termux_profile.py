#!/usr/bin/env python3
"""Dependency-free Android/Termux terminal-client contracts."""

import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh"
BOOTSTRAP = ROOT / "Bootstrap-AgentSwitchboard-Termux.sh"


def load(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def main() -> None:
    policy = load(".ai/harness/device-profile-launcher.policy.json")
    registry = load(".ai/harness/device-profile-registry.json")
    environment_policy = load(".ai/harness/environment-capability.policy.json")
    android = {item["profileId"]: item for item in registry["profiles"]}["android"]

    assert android["status"] == "terminal-client-implemented"
    assert android["capabilityRole"] == "terminal-client"
    assert android["frontend"] == "termux"
    assert android["canonicalOperation"] == "open-or-activate"
    assert android["canonicalSourcePath"] == str(LAUNCHER.relative_to(ROOT)).replace("\\", "/")
    assert android["installedPath"] == "$PREFIX/bin/agentswitchboard-phone"
    assert android["bootstrapPath"] == BOOTSTRAP.name
    assert android["workspaceBackend"] == "tmux"
    assert android["localTmuxRole"] == "local-shell-only"
    assert android["localTmuxScope"] == "device-local-only"
    assert android["continuityTransport"] == "ssh"
    assert android["crossDeviceContinuityRequiresRemoteWorkspaceHost"] is True
    assert android["remoteShellClassificationRequired"] is True
    assert android["nativeOrchestrationRuntime"] == "unimplemented"
    assert android["nativeAgentRuntime"] == "unproved"
    assert android["fullRuntimeClaimAllowed"] is False
    assert android["configurationMayDiffer"] is True

    android_policy = policy["androidProfile"]
    assert android_policy["status"] == "terminal-client-implemented"
    assert android_policy["capabilityRole"] == "terminal-client"
    assert android_policy["terminalFrontend"] == "termux"
    assert android_policy["workspaceBackend"] == "tmux"
    assert android_policy["localTmuxScope"] == "device-local-only"
    assert android_policy["continuityTransport"] == "ssh"
    assert android_policy["supportedRemoteHostProfiles"] == ["posix-tmux"]
    assert android_policy["remotePreflightRequired"] is True
    assert android_policy["nativeOrchestrationRuntime"] == "unimplemented"
    assert android_policy["fullRuntimeClaimAllowed"] is False
    assert android_policy["liveDeviceProofRequired"] is True
    assert policy["profiles"]["android"]["frontend"] == "termux"
    assert policy["profiles"]["android"]["roleCeiling"] == "terminal-client"
    assert environment_policy["android"]["currentStatus"] == "terminal-client-implemented"

    for path in (LAUNCHER, BOOTSTRAP):
        assert path.is_file(), f"missing {path.relative_to(ROOT)}"
        script = path.read_text(encoding="utf-8")
        assert "wezterm" not in script.lower()
        assert "StrictHostKeyChecking=no" not in script

    launcher_text = LAUNCHER.read_text(encoding="utf-8")
    for token in (
        "local-shell",
        "remote",
        "--host-profile",
        "posix-tmux",
        "--repo",
        "--expected-origin",
        "--create",
        "--plan",
        "role=terminal-client",
        "continuity_scope=device-local-only",
        "remote-preflight.env",
        "printf 'attachment_observed=%s",
        "''|-*|*[!A-Za-z0-9_.@:%-]*",
        "elif tmux has-session -t \"$session\"",
        "create_outcome=existing-after-race",
        "git -C \"$repo_path\" rev-parse --git-dir",
        "failed-remote-session-create",
    ):
        assert token in launcher_text, token
    assert launcher_text.count('"false"') >= 4
    assert launcher_text.count("tmux has-session -t") >= 6
    assert "eval " not in launcher_text
    assert "role=full-runtime-host" not in launcher_text

    bootstrap_text = BOOTSTRAP.read_text(encoding="utf-8")
    for token in (
        "Android terminal client installed",
        "Full AgentSwitchboard runtime is not configured",
        "proof=terminal-client-installed-command-probes",
        "repo_purpose=source-and-terminal-client-files-not-runtime-proof",
        "run_logged()",
        "git -C \"$REPO_ROOT\" rev-parse --git-dir",
        "tail -n 20",
        "run_logged package-install 61",
        "run_logged repository-clone 62",
        "run_logged repository-fetch 63",
        "run_logged repository-fast-forward 64",
        "bootstrap-logs",
    ):
        assert token in bootstrap_text, token
    assert 'if [ -d "$REPO_ROOT/.git" ]' not in bootstrap_text
    assert "pkg install -y git openssh tmux curl\n" not in bootstrap_text.replace(
        "run_logged package-install 61 pkg install -y git openssh tmux curl\n", ""
    )

    # Windows runners may resolve `bash` to the WSL compatibility shim. Execute
    # Android shell behavior on POSIX; Windows enforces tracked content and JSON.
    if os.name != "nt":
        for path in (LAUNCHER, BOOTSTRAP):
            parsed = run("bash", "-n", str(path))
            assert parsed.returncode == 0, f"{path.relative_to(ROOT)}: {parsed.stderr}"

        status = run("bash", str(LAUNCHER), "status")
        assert status.returncode == 0, status.stderr
        assert "role=terminal-client" in status.stdout
        assert "local_tmux_role=local-shell-only" in status.stdout
        assert "continuity_scope=device-local-only" in status.stdout
        assert "native_orchestration_runtime=unimplemented" in status.stdout

        local_plan = run(
            "bash", str(LAUNCHER), "local-shell", "--session", "dev-1", "--plan"
        )
        assert local_plan.returncode == 0, local_plan.stderr
        assert "role=local-shell-only" in local_plan.stdout
        assert "mode=local-shell" in local_plan.stdout
        assert "continuity_scope=device-local-only" in local_plan.stdout
        assert "session=dev-1" in local_plan.stdout

        remote_plan = run(
            "bash",
            str(LAUNCHER),
            "remote",
            "user@example-host",
            "--host-profile",
            "posix-tmux",
            "--repo",
            "/srv/AgentSwitchboard",
            "--expected-origin",
            "https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
            "--session",
            "dev",
            "--plan",
        )
        assert remote_plan.returncode == 0, remote_plan.stderr
        assert "role=terminal-client" in remote_plan.stdout
        assert "topology=android-termux-ssh-posix-workspace-client" in remote_plan.stdout
        assert "host_profile=posix-tmux" in remote_plan.stdout
        assert "target=user@example-host" in remote_plan.stdout

        option_target = run(
            "bash",
            str(LAUNCHER),
            "remote",
            "-V",
            "--host-profile",
            "posix-tmux",
            "--repo",
            "/srv/AgentSwitchboard",
            "--expected-origin",
            "https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
            "--plan",
        )
        assert option_target.returncode != 0
        assert "invalid SSH target: -V" in option_target.stderr

        unclassified = run(
            "bash",
            str(LAUNCHER),
            "remote",
            "user@example-host",
            "--repo",
            "/srv/AgentSwitchboard",
            "--expected-origin",
            "https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
            "--plan",
        )
        assert unclassified.returncode != 0
        assert "requires --host-profile posix-tmux" in unclassified.stderr

        rejected = run(
            "bash", str(LAUNCHER), "local-shell", "--session", "bad session", "--plan"
        )
        assert rejected.returncode != 0
        assert "invalid tmux session name" in rejected.stderr

        bootstrap_plan_env = dict(os.environ)
        bootstrap_plan_env["PREFIX"] = "/tmp/termux-prefix"
        bootstrap_plan = run(
            "bash",
            str(BOOTSTRAP),
            "--plan",
            "--repo",
            "/tmp/AgentSwitchboard",
            "--ref",
            "main",
            env=bootstrap_plan_env,
        )
        assert bootstrap_plan.returncode == 0, bootstrap_plan.stderr
        assert "capability_status=terminal-client-implemented" in bootstrap_plan.stdout
        assert "role=terminal-client" in bootstrap_plan.stdout
        assert "packages=git,openssh,tmux,curl" in bootstrap_plan.stdout
        assert "native_orchestration_runtime=unimplemented" in bootstrap_plan.stdout
        assert "pkg install" not in bootstrap_plan.stdout

    docs = (ROOT / "docs/workstation/android-termux.md").read_text(encoding="utf-8").lower()
    for token in (
        "terminal-client-implemented",
        "local-shell-only",
        "device-local-only",
        "agentswitchboard-phone local-shell",
        "--host-profile posix-tmux",
        "execution hold",
        "proof ceiling",
    ):
        assert token in docs
    assert "the shared continuity boundary is the named" not in docs

    print("PASS: Android Termux terminal-client contracts")


if __name__ == "__main__":
    main()
