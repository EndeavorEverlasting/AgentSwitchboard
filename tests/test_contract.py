#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from agentswitchboard import contract

REQUESTS = ROOT / "fixtures/requests"
INVOCATION_SCHEMA = ROOT / "schemas/agentswitchboard-invocation/v2.json"
RESULT_SCHEMA = ROOT / "schemas/agentswitchboard-result/v2.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def validate(data, schema_path):
    jsonschema.validate(data, load(schema_path))


def test_v2_requests_and_results_validate():
    for name in (
        "v2-native.json",
        "v2-bridge.json",
        "v2-missing.json",
        "v2-auth-required.json",
    ):
        request = load(REQUESTS / name)
        assert contract.validate_request(request) == []
        validate(request, INVOCATION_SCHEMA)
        result = contract.run_fixture(request)
        validate(result, RESULT_SCHEMA)
        assert result["schema_version"] == "agentswitchboard-result/v2"
        assert result["proof"]["provider_response_observed"] is False


def test_non_object_and_secret_requests_fail_cleanly():
    assert "JSON object" in contract.validate_request([])[0]
    request = load(REQUESTS / "v2-native.json")
    request["secret_token"] = "do-not-accept"
    errors = contract.validate_request(request)
    assert any("unknown" in item for item in errors)
    assert any("secret" in item for item in errors)


def test_domain_distro_bridge_and_unsupported_invariants():
    request = load(REQUESTS / "v2-native.json")
    request["distro"] = "docker-desktop"
    assert any("Docker" in item for item in contract.validate_request(request))

    request = load(REQUESTS / "v2-bridge.json")
    request["bridge_permission"] = False
    result = contract.run_fixture(request)
    assert result["overall_status"] == "action-required"
    assert all(item["selected_backend"] == "missing" for item in result["agents"].values())

    invalid = load(REQUESTS / "v2-native.json")
    invalid["execution_domain"] = "unsupported"
    assert contract.validate_request(invalid)
    try:
        validate(invalid, INVOCATION_SCHEMA)
    except jsonschema.ValidationError:
        pass
    else:
        raise AssertionError("unsupported execution_domain must be limited to macOS")


def test_fixture_resolution_policy_and_authentication_posture():
    native = contract.run_fixture(load(REQUESTS / "v2-native.json"))
    bridge = contract.run_fixture(load(REQUESTS / "v2-bridge.json"))
    auth = contract.run_fixture(load(REQUESTS / "v2-auth-required.json"))
    assert all(item["selected_backend"] == "native" for item in native["agents"].values())
    assert all(item["selected_backend"] == "bridge" for item in bridge["agents"].values())
    assert auth["agents"]["opencode"]["authentication_readiness"] == "required"
    assert auth["proof"]["authentication_observed"] is False


def test_cli_returns_normalized_unsupported_and_invalid_codes():
    unsupported = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", str(REQUESTS / "v2-macos-unsupported.json")],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert unsupported.returncode == 3
    assert json.loads(unsupported.stdout)["overall_status"] == "unsupported"

    invalid = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--validate"],
        cwd=ROOT,
        input="[]",
        capture_output=True,
        text=True,
    )
    assert invalid.returncode == 2
    assert "JSON object" in invalid.stderr

    missing_path = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--pretty"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert missing_path.returncode == 2
    assert "Missing REQUEST.json" in missing_path.stderr


def test_wrapper_manifest_and_installation_shell_loop():
    if not shutil.which("bash"):
        return
    manifest = load(ROOT / "tooling/wsl/wrapper-manifest.json")
    assert set(manifest["agents"]) == {"opencode", "agy", "goose"}
    installer = "tooling/wsl/scripts/install-agent-wrappers.sh"
    subprocess.run(["bash", "-n", installer], cwd=ROOT, check=True)
    subprocess.run(
        ["bash", "-n", "tooling/wsl/scripts/bootstrap-agent-workstation.sh"],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(["bash", "-n", "tooling/wsl/templates/agent-wrapper.sh"], cwd=ROOT, check=True)
    if os.name == "nt":
        return

    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        managed = root / "managed"
        native = root / "native"
        native.mkdir()
        subprocess.run(
            ["bash", installer, "--destination", str(managed)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        expected = {
            name
            for agent in ("opencode", "agy", "goose")
            for name in (agent, f"{agent}_native", f"{agent}_win")
        } | {"policy.env"}
        assert {path.name for path in managed.iterdir()} == expected

        custom = managed / "opencode"
        custom.write_text("#!/usr/bin/env bash\necho custom\n", encoding="utf-8")
        custom.chmod(0o755)
        subprocess.run(
            ["bash", installer, "--destination", str(managed)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        assert "echo custom" in custom.read_text(encoding="utf-8")
        assert not custom.with_suffix(".backup").exists()

        subprocess.run(
            ["bash", installer, "--destination", str(managed), "--force"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        assert "echo custom" in Path(f"{custom}.backup").read_text(encoding="utf-8")
        assert "echo custom" not in custom.read_text(encoding="utf-8")

        for agent in ("opencode", "agy", "goose"):
            fake = native / agent
            fake.write_text(
                "#!/usr/bin/env bash\nprintf '%s native fixture\\n' \"$(basename \"$0\")\"\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
        env = {**os.environ, "PATH": f"{managed}:{native}:{os.environ['PATH']}"}
        for agent in ("opencode", "agy", "goose"):
            result = subprocess.run(
                [str(managed / agent), "--agent-switchboard-probe"],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0
            assert "native fixture" in result.stdout


def test_windows_wsl_live_install_and_bridge_probe_stay_in_selected_distro():
    request = load(REQUESTS / "v2-bridge.json")
    request["operation"] = "install-missing"
    observed = []
    original = contract.subprocess.run

    def fake_run(command, **kwargs):
        observed.append(command)
        assert kwargs.get("capture_output") is True
        assert kwargs.get("text") is True
        assert kwargs.get("check") is False
        joined = " ".join(command)
        if "install-agent-wrappers.sh" in joined:
            assert kwargs.get("timeout") == 30
            return subprocess.CompletedProcess(command, 0, "installed\n", "")
        assert kwargs.get("timeout") == 10
        if "_native" in joined:
            return subprocess.CompletedProcess(command, 127, "", "native missing")
        if "_win" in joined:
            return subprocess.CompletedProcess(command, 0, "bridge fixture 1.0\n", "")
        if "AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=1" in joined:
            return subprocess.CompletedProcess(command, 0, "bridge fixture 1.0\n", "")
        raise AssertionError(f"unexpected subprocess command: {command!r}")

    contract.subprocess.run = fake_run
    try:
        result = contract.run_live(request, ROOT)
    finally:
        contract.subprocess.run = original
    assert result["overall_status"] == "pass"
    assert result["proof"]["installation_observed"] is True
    assert all(row["selected_backend"] == "bridge" for row in result["agents"].values())
    assert observed
    assert all(command[:4] == ["wsl.exe", "-d", "Ubuntu", "--exec"] for command in observed)
    assert any("--allow-windows-bridge" in " ".join(command) for command in observed)


def test_bootstrap_review_defects_are_repaired():
    ps = (ROOT / "tooling/wsl/Install-AgentSwitchboardWsl.ps1").read_text(encoding="utf-8-sig")
    bootstrap = (ROOT / "tooling/wsl/scripts/bootstrap-agent-workstation.sh").read_text(
        encoding="utf-8"
    )
    manifest = load(ROOT / "tooling/wsl/wsl-workstation.example.json")
    assert 'return "/mnt/$drive/$rest"' in ps
    assert 'if ($wslCommand) { & $WslExe --list --verbose' in ps
    assert "$HOME/" in ps and "tmuxDestination" in ps
    assert 'CONFIG_JSON=$(cat)' in bootstrap
    assert "eval " not in bootstrap
    assert "install_agent" in bootstrap and "FAILURES=0" in bootstrap
    assert "exit 1" in bootstrap
    assert '.branch // "main"' in bootstrap
    assert {"nodejs", "npm"} <= set(manifest["packages"])


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} AgentSwitchboard multi-domain contract groups")
