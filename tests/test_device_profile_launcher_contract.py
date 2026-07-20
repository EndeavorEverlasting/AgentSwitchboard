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
    schema = load(".ai/harness/schemas/device-profile-registry.schema.json")
    valid = load(".ai/harness/fixtures/device-profiles/valid-sysadminsuite-consumer.json")
    invalid = load(".ai/harness/fixtures/device-profiles/invalid-competing-consumer.json")

    assert policy["policyId"] == "agentswitchboard.device-profile-launcher.v1"
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
    assert policy["idempotence"]["sameIdentityConverges"] is True
    assert policy["idempotence"]["duplicateLogicalWorkspaceForbidden"] is True
    assert policy["delegation"]["consumerMayFallbackToRawFrontend"] is False
    assert policy["profiles"]["android"]["configurationMayDiffer"] is True

    assert schema["additionalProperties"] is False
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
    assert by_id["android"]["status"] == "reserved"
    assert by_id["android"]["configurationMayDiffer"] is True

    assert valid["ownerRepository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert valid["operation"] == "open-or-activate"
    assert valid["delegateOnly"] is True
    assert invalid["ownerRepository"] != "EndeavorEverlasting/AgentSwitchboard"
    assert invalid["operation"] != "open-or-activate"

    doctrine = (ROOT / "docs/governance/device-profile-launcher-contract.md").read_text(encoding="utf-8")
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    harness = (ROOT / "docs/governance/harness-doctrine.md").read_text(encoding="utf-8")
    capabilities = (ROOT / "CAPABILITIES.md").read_text(encoding="utf-8")
    triggers = (ROOT / "TRIGGERS.md").read_text(encoding="utf-8")
    for token in ("Windows Profile", "Linux Profile", "Android Profile", "open-or-activate", "EndeavorEverlasting/SysAdminSuite", "contract-only"):
        assert token in doctrine
    assert "device-profile-launcher-contract.md" in agents
    assert "device-profile-launcher-contract.md" in harness
    assert "profile.launcher.contract.validate" in capabilities
    assert "profile.launcher-request" in triggers

    print("PASS: canonical device profile launcher contracts")


if __name__ == "__main__":
    main()
