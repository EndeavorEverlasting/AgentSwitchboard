#!/usr/bin/env python3
"""Dependency-free contracts for the profile-boundary operational harness."""

import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/harness/profile-boundary"


def load_json(path: Path):
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8"))


def require_tracked(path: str) -> Path:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    assert result.returncode == 0, f"not tracked: {path}"
    return target


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main() -> None:
    manifest = load_json(HARNESS / "manifest.json")
    registry = load_json(HARNESS / "profile-boundary.registry.json")
    artifacts = load_json(HARNESS / "artifact-registry.json")
    workflows = load_json(HARNESS / "workflow-specs.json")
    load_json(HARNESS / "command-envelope.schema.json")
    fixtures = load_json(HARNESS / "fixtures/command-envelopes.json")

    assert manifest["harnessId"] == "agentswitchboard.profile-boundary-operational-harness.v1"
    assert manifest["authority"]["deviceProfileRegistry"] == ".ai/harness/device-profile-registry.json"
    assert manifest["components"]["transitionBuilder"] == "tooling/harness/profile-boundary/Build-ProfileTransition.py"
    assert "AGENTS.md" in manifest["collisionBoundary"]["intentionallyUnchanged"]
    assert "HARNESS.md" in manifest["collisionBoundary"]["intentionallyUnchanged"]
    assert "SKILLS.md" in manifest["collisionBoundary"]["intentionallyUnchanged"]

    for path in manifest["components"].values():
        require_tracked(path)
    require_tracked("AGENTS.md")
    require_tracked(".ai/harness/device-profile-registry.json")
    require_tracked("docs/governance/device-profile-launcher-contract.md")

    device_registry = load_json(ROOT / ".ai/harness/device-profile-registry.json")
    profiles = {item["profileId"]: item for item in device_registry["profiles"]}
    assert profiles["windows"]["frontend"] == "wezterm"
    assert profiles["android"]["frontend"] == "termux"
    assert profiles["windows"]["implementationSeparate"] is True
    assert profiles["android"]["implementationSeparate"] is True

    assert registry["hostContexts"]["windows-laptop"]["forbiddenExecutionSurfaces"] == ["android-termux"]
    assert registry["hostContexts"]["android-phone"]["allowedExecutionSurfaces"] == ["android-termux"]
    wsl = registry["hostContexts"]["windows-laptop"]["bridgeRequirements"]["wsl-linux"]
    assert wsl["proofRequired"] is True
    assert set(wsl["requiredProbeTokens"]) == {"wsl.exe", "/bin/bash"}

    validator = load_module(HARNESS / "Validate-CommandEnvelope.py", "profile_boundary_validator")
    for case in fixtures["cases"]:
        result = validator.validate_envelope(case["envelope"], registry)
        assert result["status"] == case["expectedStatus"], case["id"]
        assert result["reasonCodes"] == sorted(case["expectedReasons"]), case["id"]
        assert len(result["commandSha256"]) == 64
        assert "command" not in result

    source = next(case for case in fixtures["cases"] if case["id"] == "android-command-on-windows-blocked")
    source_report = validator.validate_envelope(source["envelope"], registry)
    builder = load_module(HARNESS / "Build-ProfileTransition.py", "profile_transition_builder")
    transitioned, transition_report = builder.build_transition(source["envelope"], source_report, registry)

    assert transitioned == {
        "schema": "agentswitchboard.command-envelope.v1",
        "hostContext": "android-phone",
        "targetProfile": "android",
        "executionSurface": "android-termux",
        "command": source["envelope"]["command"],
    }
    assert validator.validate_envelope(transitioned, registry)["status"] == "PASS"
    assert transition_report["status"] == "PASS"
    assert transition_report["sourceCommandSha256"] == source_report["commandSha256"]
    assert transition_report["destinationHostContext"] == "android-phone"
    assert transition_report["executionSurface"] == "android-termux"
    assert "command" not in transition_report

    tampered = dict(source_report)
    tampered["commandSha256"] = "0" * 64
    try:
        builder.build_transition(source["envelope"], tampered, registry)
    except ValueError as exc:
        assert "source-command-digest-mismatch" in str(exc)
    else:
        raise AssertionError("tampered source digest must fail closed")

    ids = [item["id"] for item in workflows["workflows"]]
    assert ids == [
        "task-intake",
        "validate-command-handoff",
        "failure-recovery",
        "correct-profile-transition",
        "handoff",
    ]
    workflow_text = json.dumps(workflows)
    for token in ("windows-laptop", "android-phone", "wsl-linux", "android-termux", "/bin/bash", "Android-only", "Build-ProfileTransition.py", "commandSha256"):
        assert token in workflow_text

    assert artifacts["tracked"] is False
    artifact_ids = {item["artifactId"] for item in artifacts["artifacts"]}
    assert {"profile-transition-envelope", "profile-transition-report"} <= artifact_ids
    forbidden = " ".join(artifacts["forbiddenContent"])
    for token in ("passwords", "device codes", "access or refresh tokens", "private SSH keys"):
        assert token in forbidden

    skill = require_tracked(".ai/skills/profile-boundary-routing/SKILL.md").read_text(encoding="utf-8")
    guide = require_tracked("docs/harness/profile-boundary-operational-harness.md").read_text(encoding="utf-8")
    front = require_tracked("PROFILE_BOUNDARY_HARNESS.md").read_text(encoding="utf-8")
    for token in ("windows-laptop", "android-phone", "wsl.exe", "/bin/bash", "bare `bash -lc`", "Build-ProfileTransition.py"):
        assert token in skill
        assert token in guide
    assert "Test-ProfileBoundaryHarness.cmd" in front
    assert "Build-ProfileTransition.py" in front

    ci = require_tracked(".github/workflows/profile-boundary-harness.yml").read_text(encoding="utf-8")
    assert ci.count("persist-credentials: false") == 2
    for token in ("Test-ProfileBoundaryHarness.py", "test_profile_boundary_harness.py", "test_device_profile_launcher_contract.py", "test_android_termux_harness.py", "git diff --check"):
        assert token in ci

    print("PASS: profile-boundary operational harness contracts")


if __name__ == "__main__":
    main()
