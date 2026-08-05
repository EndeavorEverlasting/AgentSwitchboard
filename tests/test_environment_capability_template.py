#!/usr/bin/env python3
"""Dependency-free child-template environment capability inheritance contract."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "templates/repository-agent-contract"


def read(relative: str) -> str:
    path = TEMPLATE / relative
    assert path.is_file(), f"missing template file: {relative}"
    return path.read_text(encoding="utf-8")


def load(relative: str) -> dict:
    return json.loads(read(relative))


def main() -> None:
    agents = read("AGENTS.md")
    capabilities = read("CAPABILITIES.md")
    skills = read("SKILLS.md")
    triggers = read("TRIGGERS.md")
    environment_doctrine = read("docs/governance/environment-capability-contract.md")
    agent_contract = load(".ai/agent-contract.json")
    environment_policy = load(".ai/harness/environment-capability.policy.json")
    harness_policy = load(".ai/harness/harness-doctrine.policy.json")
    profile_policy = load(".ai/harness/device-profile-launcher.policy.json")

    for token in (
        "docs/governance/environment-capability-contract.md",
        ".ai/harness/environment-capability.policy.json",
        "frontend -> transport -> workspace host -> orchestration runtime -> agent runtime",
        "full-runtime-host",
        "terminal-client",
        "local-shell-only",
        "same-named tmux sessions on different hosts",
        "Auto-configuration is not a universal installer",
        "Never silently substitute a lower-role topology",
    ):
        assert token in agents, token

    for token in (
        "environment.capability.read",
        "environment.topology.select",
        "environment.remote.preflight",
        "environment.role.certify",
        "Repository or package presence is not runtime readiness",
    ):
        assert token in capabilities, token

    assert "environment-capability-routing" in skills
    assert "Environment classification precedes platform installation" in skills
    for token in (
        "environment.capability-request",
        "environment.remote-request",
        "environment.false-equivalence",
        "unknown environment topology",
        "lower-role topology mismatch",
    ):
        assert token in triggers, token

    for token in (
        "frontend -> transport -> workspace host -> orchestration runtime -> agent runtime",
        "same-named tmux sessions on different hosts",
        "phone-local tmux and cross-device continuity",
        "lower-role topology",
    ):
        assert token in environment_doctrine, token

    assert agent_contract["entrypoints"]["environmentCapabilities"] == (
        "docs/governance/environment-capability-contract.md"
    )
    contract = agent_contract["environmentCapabilities"]
    assert contract["fiveLayersRequired"] is True
    assert contract["oneTopologyRequired"] is True
    assert contract["remotePreflightRequired"] is True
    assert contract["universalInstallerAllowed"] is False
    assert contract["repositoryPresenceProvesRuntime"] is False
    assert contract["sameTmuxNameAcrossHostsProvesIdentity"] is False
    assert contract["lowerRoleTopologySubstitutionAllowed"] is False
    assert contract["staticOrCiProofCanClaimLiveEnvironment"] is False

    assert environment_policy["policyId"] == "agentswitchboard.environment-capability.v1"
    assert environment_policy["canonicalRepository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert environment_policy["layers"] == [
        "frontend",
        "transport",
        "workspaceHost",
        "orchestrationRuntime",
        "agentRuntime",
    ]
    invariants = environment_policy["invariants"]
    assert invariants["oneTopologyRequired"] is True
    assert invariants["terminalClientIsNotRuntimeHost"] is True
    assert invariants["repositoryPresenceIsNotRuntimeReadiness"] is True
    assert invariants["packagePresenceIsNotVerifiedCapability"] is True
    assert invariants["sshReachabilityIsNotRemoteShellClassification"] is True
    assert invariants["sameTmuxNameAcrossHostsIsSameSession"] is False
    assert invariants["phoneLocalTmuxIsCrossDeviceContinuity"] is False
    assert invariants["commandAckIsNotBehaviorProof"] is True
    assert invariants["staticOrCiProofIsNotLiveEnvironmentProof"] is True
    assert invariants["lowerRoleTopologySubstitutionAllowed"] is False
    assert environment_policy["autoConfiguration"]["universalInstallerAllowed"] is False
    assert environment_policy["autoConfiguration"]["remotePreflightRequired"] is True
    assert environment_policy["localRulesMayWeaken"] is False

    inherited = harness_policy["environmentCapabilityContract"]
    assert inherited["policy"] == ".ai/harness/environment-capability.policy.json"
    assert inherited["fiveLayersRequired"] is True
    assert inherited["oneTopologyRequired"] is True
    assert inherited["universalInstallerForbidden"] is True
    assert inherited["remotePreflightRequired"] is True
    assert inherited["repositoryPresenceCannotProveRuntime"] is True
    assert inherited["sameTmuxNameAcrossHostsCannotProveIdentity"] is True
    assert inherited["terminalClientCannotClaimRuntimeHost"] is True
    assert inherited["lowerRoleTopologySubstitutionForbidden"] is True
    assert inherited["staticProofCannotClaimLiveEnvironment"] is True
    assert harness_policy["localRulesMayWeaken"] is False

    assert profile_policy["environmentCapabilityPolicy"] == (
        ".ai/harness/environment-capability.policy.json"
    )
    assert profile_policy["environmentTopologyRequired"] is True
    assert profile_policy["sameWorkspaceIdentityRequiresSameHostAndRuntimeOwner"] is True
    assert profile_policy["sameTmuxNameAcrossHostsProvesIdentity"] is False
    assert profile_policy["repositoryPresenceProvesLauncherOrRuntime"] is False
    assert profile_policy["crossProfileSubstitutionForbidden"] is True
    assert profile_policy["localRulesMayWeaken"] is False

    print("PASS: repository-agent template inherits environment capability floor")


if __name__ == "__main__":
    main()
