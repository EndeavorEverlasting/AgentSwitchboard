#!/usr/bin/env python3
"""Dependency-free device profile launcher contracts."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path: str) -> dict:
    target = ROOT / path
    assert target.is_file(), f"missing: {path}"
    return json.loads(target.read_text(encoding="utf-8"))


def main() -> None:
    policy = load(".ai/harness/device-profile-launcher.policy.json")
    registry = load(".ai/harness/device-profile-registry.json")
    environment_policy = load(".ai/harness/environment-capability.policy.json")
    schema = load(".ai/harness/schemas/device-profile-registry.schema.json")
    valid = load(".ai/harness/fixtures/device-profiles/valid-sysadminsuite-consumer.json")
    invalid = load(".ai/harness/fixtures/device-profiles/invalid-competing-consumer.json")

    assert policy["policyId"] == "agentswitchboard.device-profile-launcher.v1"
    assert policy["environmentCapabilityPolicy"] == ".ai/harness/environment-capability.policy.json"
    assert policy["ownership"]["canonicalOwnerRepository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert policy["ownership"]["oneCanonicalLauncherPerProfile"] is True
    assert policy["ownership"]["consumerIndependentLaunchLogicForbidden"] is True
    assert policy["ownership"]["desktopShortcutsDelegateOnly"] is True
    assert policy["ownership"]["rawFallbackForbidden"] is True

    windows_policy = policy["windowsProfile"]
    assert windows_policy["displayName"] == "Windows Profile"
    assert windows_policy["status"] == "contract-only"
    assert windows_policy["terminalFrontend"] == "wezterm"
    assert windows_policy["canonicalOperation"] == "open-or-activate"
    assert windows_policy["consumerCertifier"] == "EndeavorEverlasting/SysAdminSuite"

    android_policy = policy["androidProfile"]
    assert android_policy["displayName"] == "Android Profile"
    assert android_policy["status"] == "terminal-client-implemented"
    assert android_policy["capabilityRole"] == "terminal-client"
    assert android_policy["terminalFrontend"] == "termux"
    assert android_policy["canonicalOperation"] == "open-or-activate"
    assert android_policy["workspaceBackend"] == "tmux"
    assert android_policy["localTmuxRole"] == "local-shell-only"
    assert android_policy["localTmuxScope"] == "device-local-only"
    assert android_policy["continuityTransport"] == "ssh"
    assert android_policy["crossDeviceContinuityRequiresRemoteWorkspaceHost"] is True
    assert android_policy["remoteShellClassificationRequired"] is True
    assert android_policy["supportedRemoteHostProfiles"] == ["posix-tmux"]
    assert android_policy["remotePreflightRequired"] is True
    assert android_policy["nativeOrchestrationRuntime"] == "unimplemented"
    assert android_policy["nativeAgentRuntime"] == "unproved"
    assert android_policy["fullRuntimeClaimAllowed"] is False
    assert android_policy["liveDeviceProofRequired"] is True

    assert policy["idempotence"]["sameIdentityConverges"] is True
    assert policy["idempotence"]["sameIdentityRequiresSameHostAndTmuxServer"] is True
    assert policy["idempotence"]["duplicateLogicalWorkspaceForbidden"] is True
    assert policy["delegation"]["consumerMayFallbackToRawFrontend"] is False
    assert policy["profiles"]["android"]["configurationMayDiffer"] is True
    assert policy["profiles"]["android"]["frontend"] == "termux"
    assert policy["profiles"]["android"]["roleCeiling"] == "terminal-client"

    assert schema["additionalProperties"] is False
    assert registry["environmentCapabilityPolicy"] == ".ai/harness/environment-capability.policy.json"
    profiles = registry["profiles"]
    by_id = {item["profileId"]: item for item in profiles}
    assert set(by_id) == {"windows", "linux", "android"}
    assert len(by_id) == len(profiles)
    assert all(item["ownerRepository"] == "EndeavorEverlasting/AgentSwitchboard" for item in profiles)
    assert all(item["implementationSeparate"] is True for item in profiles)
    assert all(item["canonicalOperation"] == "open-or-activate" for item in profiles)

    windows = by_id["windows"]
    assert windows["displayName"] == "Windows Profile"
    assert windows["frontend"] == "wezterm"
    assert windows["status"] == "contract-only"
    assert windows["consumers"][0]["repository"] == "EndeavorEverlasting/SysAdminSuite"
    assert windows["consumers"][0]["delegateOnly"] is True
    assert windows["consumers"][0]["rawFallbackAllowed"] is False

    assert by_id["linux"]["status"] == "reserved"

    android = by_id["android"]
    assert android["displayName"] == "Android Profile"
    assert android["status"] == "terminal-client-implemented"
    assert android["capabilityRole"] == "terminal-client"
    assert android["frontend"] == "termux"
    assert android["configurationMayDiffer"] is True
    assert android["canonicalSourcePath"] == "tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh"
    assert android["installedPath"] == "$PREFIX/bin/agentswitchboard-phone"
    assert android["bootstrapPath"] == "Bootstrap-AgentSwitchboard-Termux.sh"
    assert android["workspaceBackend"] == "tmux"
    assert android["localTmuxRole"] == "local-shell-only"
    assert android["localTmuxScope"] == "device-local-only"
    assert android["continuityTransport"] == "ssh"
    assert android["crossDeviceContinuityRequiresRemoteWorkspaceHost"] is True
    assert android["remoteShellClassificationRequired"] is True
    assert android["nativeOrchestrationRuntime"] == "unimplemented"
    assert android["nativeAgentRuntime"] == "unproved"
    assert android["fullRuntimeClaimAllowed"] is False

    assert environment_policy["android"]["currentStatus"] == "terminal-client-implemented"
    assert environment_policy["android"]["localTmuxScope"] == "device-local-only"
    assert environment_policy["invariants"]["sameTmuxNameAcrossHostsIsSameSession"] is False

    assert valid["ownerRepository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert valid["operation"] == "open-or-activate"
    assert valid["delegateOnly"] is True
    assert invalid["ownerRepository"] != "EndeavorEverlasting/AgentSwitchboard"
    assert invalid["operation"] != "open-or-activate"

    doctrine = (ROOT / "docs/governance/device-profile-launcher-contract.md").read_text(encoding="utf-8")
    environment_doctrine = (ROOT / "docs/governance/environment-capability-contract.md").read_text(encoding="utf-8")
    android_docs = (ROOT / "docs/workstation/android-termux.md").read_text(encoding="utf-8")
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/governance/harness-doctrine.md").read_text(encoding="utf-8")
    capabilities = (ROOT / "CAPABILITIES.md").read_text(encoding="utf-8")
    triggers = (ROOT / "TRIGGERS.md").read_text(encoding="utf-8")
    for token in (
        "Windows Profile",
        "Linux Profile",
        "Android Profile",
        "open-or-activate",
        "EndeavorEverlasting/SysAdminSuite",
        "contract-only",
        "terminal-client-implemented",
    ):
        assert token in doctrine
    for token in (
        "Termux",
        "local-shell-only",
        "device-local-only",
        "remote workspace host",
        "Proof ceiling",
    ):
        assert token in android_docs
    assert "tmux identity is host-scoped" in environment_doctrine
    assert "device-profile-launcher-contract.md" in agents
    assert "environment-capability-contract.md" in agents
    assert "device-profile-launcher-contract.md" in harness
    assert "profile.launcher.contract.validate" in capabilities
    assert "environment.capability.validate" in capabilities
    assert "profile.launcher-request" in triggers
    assert "environment.capability-request" in triggers

    print("PASS: canonical device profile launcher contracts")


if __name__ == "__main__":
    main()
