#!/usr/bin/env python3
"""Dependency-free environment capability and continuity contracts."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/profiles/harness/environment-capability"


def load(relative: str) -> dict:
    path = ROOT / relative
    assert path.is_file(), f"missing: {relative}"
    return json.loads(path.read_text(encoding="utf-8"))


def text(relative: str) -> str:
    path = ROOT / relative
    assert path.is_file(), f"missing: {relative}"
    return path.read_text(encoding="utf-8")


def classify_fixture(fixture: dict) -> tuple[str | None, str, str]:
    data = fixture["input"]

    if data.get("frontendHost") == "android-termux" and data.get("transport") == "local-process-boundary":
        topology = "android-termux-local-shell"
        role = "local-shell-only"
        if data.get("claimedRole") == "full-runtime-host" or data.get("claimedContinuity") == "same-workspace":
            return topology, role, "REJECTED_FALSE_PROOF_PROMOTION"
        return topology, role, "PASS_ROLE_CERTIFIED"

    if data.get("frontendHost") == "android-termux" and data.get("transport") == "ssh":
        if data.get("remoteShellClass") != "posix":
            return None, "transport-only", "BLOCKED_CAPABILITY_GAP"
        if not data.get("workspaceHostIdentityObserved") or not data.get("tmuxServerIdentityObserved"):
            return None, "transport-only", "BLOCKED_CAPABILITY_GAP"
        return "android-termux-ssh-posix-workspace-client", "terminal-client", "PASS_ROLE_CERTIFIED"

    if data.get("frontendHost") == "windows" and data.get("workspaceHost") == "wsl-linux":
        required = (
            data.get("workspaceHostIdentityObserved"),
            data.get("tmuxServerIdentityObserved"),
            data.get("repositoryIdentityObserved"),
            data.get("repositoryClean"),
            data.get("orchestrationRuntimeVerified"),
            data.get("agentRuntimeVerified"),
            data.get("operatorVisibleResultObserved"),
        )
        if all(required):
            return "windows-wezterm-wsl-control-plane", "full-runtime-host", "PASS_ROLE_CERTIFIED"
        return "windows-wezterm-wsl-control-plane", "workspace-host", "BLOCKED_CAPABILITY_GAP"

    return None, "unsupported", "BLOCKED_NO_MATCHING_TOPOLOGY"


def main() -> None:
    policy = load(".ai/harness/environment-capability.policy.json")
    registry = load(
        "tooling/profiles/harness/environment-capability/environment-capability.registry.json"
    )
    schema = load(
        "tooling/profiles/harness/environment-capability/schemas/environment-capability.schema.json"
    )
    codebase_map = load(
        "tooling/profiles/harness/environment-capability/codebase-map.json"
    )
    artifact_registry = load(
        "tooling/profiles/harness/environment-capability/artifact-registry.json"
    )

    assert policy["policyId"] == "agentswitchboard.environment-capability.v1"
    assert policy["layers"] == [
        "frontend",
        "transport",
        "workspaceHost",
        "orchestrationRuntime",
        "agentRuntime",
    ]
    assert policy["forbiddenStatuses"] == ["repository-implemented"]
    invariants = policy["invariants"]
    assert invariants["terminalClientIsNotRuntimeHost"] is True
    assert invariants["repositoryPresenceIsNotRuntimeReadiness"] is True
    assert invariants["sshReachabilityIsNotRemoteShellClassification"] is True
    assert invariants["sameTmuxNameAcrossHostsIsSameSession"] is False
    assert invariants["phoneLocalTmuxIsCrossDeviceContinuity"] is False
    assert invariants["androidIsGenericLinux"] is False
    assert invariants["androidWezTermMayBeAssumed"] is False
    assert policy["autoConfiguration"]["universalInstallerAllowed"] is False
    assert policy["android"]["currentStatus"] == "terminal-client-implemented"
    assert policy["android"]["currentRole"] == "terminal-client"
    assert policy["android"]["localTmuxScope"] == "device-local-only"
    assert policy["android"]["fullRuntimeClaimAllowed"] is False

    assert schema["additionalProperties"] is False
    assert schema["properties"]["schema"]["const"] == registry["schema"]
    assert registry["canonicalOwner"] == "EndeavorEverlasting/AgentSwitchboard"
    topologies = {item["topologyId"]: item for item in registry["topologies"]}
    assert set(topologies) == {
        "windows-wezterm-wsl-control-plane",
        "android-termux-local-shell",
        "android-termux-ssh-posix-workspace-client",
        "android-native-agentswitchboard-full-runtime",
    }
    assert topologies["android-termux-local-shell"]["implementedRoleCeiling"] == "local-shell-only"
    assert (
        topologies["android-termux-ssh-posix-workspace-client"]["implementedRoleCeiling"]
        == "terminal-client"
    )
    native_android = topologies["android-native-agentswitchboard-full-runtime"]
    assert native_android["implementationStatus"] == "reserved"
    assert native_android["implementedRoleCeiling"] == "unsupported"
    assert native_android["orchestrationRuntime"]["status"] == "unimplemented"

    assert codebase_map["canonicalSources"]["policy"] == ".ai/harness/environment-capability.policy.json"
    assert codebase_map["implementationSurfaces"]["androidBootstrap"] == "Bootstrap-AgentSwitchboard-Termux.sh"
    assert artifact_registry["trackedGeneratedEvidence"] is False
    assert {item["artifactId"] for item in artifact_registry["artifacts"]} == {
        "environment-observation",
        "topology-selection",
        "remote-host-preflight",
        "capability-certification",
        "operator-report",
        "final-handoff",
    }

    workflows = [
        load("tooling/profiles/harness/environment-capability/workflows/environment-intake.workflow.json"),
        load("tooling/profiles/harness/environment-capability/workflows/topology-selection.workflow.json"),
        load("tooling/profiles/harness/environment-capability/workflows/certification.workflow.json"),
    ]
    assert [item["workflowId"] for item in workflows] == [
        "environment-intake",
        "topology-selection",
        "environment-capability-certification",
    ]
    assert workflows[0]["mutationAllowed"] is False
    assert "REJECTED_FALSE_PROOF_PROMOTION" in workflows[1]["steps"][-1]["terminalStates"]
    assert "command acknowledgement to attachment" in workflows[2]["forbiddenPromotions"]

    fixture_paths = [
        "valid-windows-control-plane.fixture.json",
        "valid-android-terminal-client.fixture.json",
        "invalid-android-full-runtime-claim.fixture.json",
        "invalid-local-tmux-continuity-claim.fixture.json",
        "invalid-unclassified-ssh-target.fixture.json",
    ]
    for name in fixture_paths:
        fixture = load(f"tooling/profiles/harness/environment-capability/fixtures/{name}")
        topology, role, terminal = classify_fixture(fixture)
        expected = fixture["expected"]
        assert topology == expected.get("topologyId"), name
        assert role == expected.get("role", expected.get("roleCeiling")), name
        assert terminal == expected["terminalState"], name

    device_registry = load(".ai/harness/device-profile-registry.json")
    android = {item["profileId"]: item for item in device_registry["profiles"]}["android"]
    assert android["status"] == "terminal-client-implemented"
    assert android["capabilityRole"] == "terminal-client"
    assert android["localTmuxScope"] == "device-local-only"
    assert android["nativeOrchestrationRuntime"] == "unimplemented"
    assert android["crossDeviceContinuityRequiresRemoteWorkspaceHost"] is True

    device_policy = load(".ai/harness/device-profile-launcher.policy.json")
    android_policy = device_policy["androidProfile"]
    assert android_policy["status"] == "terminal-client-implemented"
    assert android_policy["capabilityRole"] == "terminal-client"
    assert android_policy["localTmuxScope"] == "device-local-only"
    assert android_policy["nativeOrchestrationRuntime"] == "unimplemented"
    assert android_policy["fullRuntimeClaimAllowed"] is False

    launcher = text("tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh")
    bootstrap = text("Bootstrap-AgentSwitchboard-Termux.sh")
    for token in (
        "role=terminal-client",
        "continuity_scope=device-local-only",
        "local-shell",
        "--host-profile",
        "posix-tmux",
        "remote-preflight.env",
    ):
        assert token in launcher, token
    for forbidden in (
        "StrictHostKeyChecking=no",
        "role=full-runtime-host",
        "continuity_scope=cross-device",
    ):
        assert forbidden not in launcher
    assert "Android terminal client installed" in bootstrap
    assert "Full AgentSwitchboard runtime is not configured" in bootstrap
    assert "proof=terminal-client-installed-command-probes" in bootstrap

    doctrine = text("docs/governance/environment-capability-contract.md")
    skill = text(".ai/skills/environment-capability-routing/SKILL.md")
    guide = text("docs/harness/environment-capability-harness.md")
    for token in (
        "Five-layer topology",
        "tmux identity is host-scoped",
        "repository-implemented",
        "Auto-configuration rule",
        "Remote-host preflight",
    ):
        assert token in doctrine
    for section in (
        "## Trigger",
        "## Inputs",
        "## Procedure",
        "## Outputs",
        "## Deterministic validation",
        "## Forbidden scope",
        "## Stop and escalate",
    ):
        assert section in skill
    assert "Why the previous Android implementation was insufficient" in guide

    skills = text("SKILLS.md")
    capabilities = text("CAPABILITIES.md")
    triggers = text("TRIGGERS.md")
    agents = text("AGENTS.md")
    codebase = text("CODEBASE_MAP.md")
    manifest = load(".ai/harness/manifest.json")
    contract = load(".ai/agent-contract.json")
    for surface in (skills, capabilities, triggers, agents, codebase):
        assert "environment-capability" in surface
    assert "environment-capability-routing" in contract["canonicalSkills"]
    assert contract["entrypoints"]["environmentCapabilities"] == "docs/governance/environment-capability-contract.md"
    assert manifest["entrypoints"]["environmentCapabilityPolicy"] == ".ai/harness/environment-capability.policy.json"
    assert manifest["environmentCapabilities"]["androidRoleCeiling"] == "terminal-client"

    print("PASS: environment capability and continuity harness")


if __name__ == "__main__":
    main()
