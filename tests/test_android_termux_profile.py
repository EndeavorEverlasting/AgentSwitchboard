#!/usr/bin/env python3
"""Dependency-free Android/Termux profile contracts."""

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
    android = {item["profileId"]: item for item in registry["profiles"]}["android"]

    assert android["status"] == "repository-implemented"
    assert android["frontend"] == "termux"
    assert android["canonicalOperation"] == "open-or-activate"
    assert android["canonicalSourcePath"] == str(LAUNCHER.relative_to(ROOT)).replace("\\", "/")
    assert android["installedPath"] == "$PREFIX/bin/agentswitchboard-phone"
    assert android["bootstrapPath"] == BOOTSTRAP.name
    assert android["workspaceBackend"] == "tmux"
    assert android["continuityTransport"] == "ssh"
    assert android["configurationMayDiffer"] is True

    android_policy = policy["androidProfile"]
    assert android_policy["status"] == "repository-implemented"
    assert android_policy["terminalFrontend"] == "termux"
    assert android_policy["workspaceBackend"] == "tmux"
    assert android_policy["continuityTransport"] == "ssh"
    assert android_policy["liveDeviceProofRequired"] is True
    assert policy["profiles"]["android"]["frontend"] == "termux"

    for path in (LAUNCHER, BOOTSTRAP):
        assert path.is_file(), f"missing {path.relative_to(ROOT)}"
        text = path.read_text(encoding="utf-8")
        assert "wezterm" not in text.lower()

    launcher_text = LAUNCHER.read_text(encoding="utf-8")
    for token in ("local", "ssh", "--session", "--plan", "tmux", "open-or-activate"):
        assert token in launcher_text
    assert "eval " not in launcher_text
    assert "StrictHostKeyChecking=no" not in launcher_text

    # GitHub's Windows runner can resolve `bash` to the WSL compatibility shim
    # instead of Git Bash. Execute the Android shell surfaces on POSIX only;
    # Windows still enforces their tracked paths, policy, registry, and content.
    if os.name != "nt":
        for path in (LAUNCHER, BOOTSTRAP):
            parsed = run("bash", "-n", str(path))
            assert parsed.returncode == 0, parsed.stderr

        local_plan = run("bash", str(LAUNCHER), "local", "--session", "dev-1", "--plan")
        assert local_plan.returncode == 0, local_plan.stderr
        assert "mode=local" in local_plan.stdout
        assert "session=dev-1" in local_plan.stdout

        ssh_plan = run(
            "bash",
            str(LAUNCHER),
            "ssh",
            "user@example-host",
            "--session",
            "dev",
            "--plan",
        )
        assert ssh_plan.returncode == 0, ssh_plan.stderr
        assert "mode=ssh" in ssh_plan.stdout
        assert "target=user@example-host" in ssh_plan.stdout

        rejected = run("bash", str(LAUNCHER), "local", "--session", "bad session", "--plan")
        assert rejected.returncode != 0
        assert "invalid tmux session name" in rejected.stderr

        plan_env = dict(os.environ)
        plan_env["PREFIX"] = "/tmp/termux-prefix"
        bootstrap_plan = run(
            "bash",
            str(BOOTSTRAP),
            "--plan",
            "--repo",
            "/tmp/AgentSwitchboard",
            "--ref",
            "main",
            env=plan_env,
        )
        assert bootstrap_plan.returncode == 0, bootstrap_plan.stderr
        assert "profile=android" in bootstrap_plan.stdout
        assert "packages=git,openssh,tmux,curl" in bootstrap_plan.stdout
        assert "pkg install" not in bootstrap_plan.stdout

    docs = (ROOT / "docs/workstation/android-termux.md").read_text(encoding="utf-8")
    for token in (
        "termux",
        "agentswitchboard-phone local",
        "agentswitchboard-phone ssh",
        "wezterm",
        "proof ceiling",
    ):
        assert token in docs.lower()

    print("PASS: Android Termux profile contracts")


if __name__ == "__main__":
    main()
