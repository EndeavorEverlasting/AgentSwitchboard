#!/usr/bin/env python3
"""Dependency-free contracts for the AgentSwitchboard Pi harness."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(relative: str) -> dict:
    path = ROOT / relative
    assert path.is_file(), f"missing: {relative}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> None:
    codebase = load("tooling/pi/harness/codebase-map.json")
    registry = load("tooling/pi/harness/pi-adapter.registry.json")
    upstream = load("tooling/pi/harness/upstream-verification.json")
    artifacts = load("tooling/pi/harness/artifact-registry.json")
    schema = load("tooling/pi/harness/schemas/pi-harness-contracts.schema.json")
    intake = load("tooling/pi/harness/workflows/task-intake.workflow.json")
    fusion = load("tooling/pi/harness/workflows/opinion-fusion.workflow.json")
    autovalidate = load("tooling/pi/harness/workflows/autovalidate.workflow.json")

    assert codebase["schema"] == "agentswitchboard.pi-codebase-map.v1"
    assert codebase["entrypoints"]["validator"] == "scripts/Test-PiHarnessCompleteness.ps1"
    assert codebase["entrypoints"]["workstationPrereqs"] == "tooling/pi/Test-PiWorkstationPrereqs.ps1"
    assert codebase["entrypoints"]["upstreamVerification"] == "tooling/pi/harness/upstream-verification.json"
    assert any("one writer" in trap.lower() for trap in codebase["knownTraps"])
    assert any("live npm metadata" in trap.lower() for trap in codebase["knownTraps"])
    assert any("npm" in trap.lower() and "paths" in trap.lower() for trap in codebase["knownTraps"])

    assert upstream["schema"] == "agentswitchboard.pi-upstream-verification.v1"
    assert upstream["verifiedAt"] == "2026-09-03"
    assert upstream["package"] == "@earendil-works/pi-coding-agent"
    assert upstream["version"] == "0.84.4"
    assert upstream["sourceRepository"] == "earendil-works/pi"
    assert upstream["minimumNodeVersion"] == "22.19.0"
    assert upstream["nodeEngine"] == ">=22.19.0"
    assert "--ignore-scripts" in upstream["installCommand"]
    assert upstream["legacyPackage"]["package"] == "@mariozechner/pi-coding-agent"
    assert upstream["legacyPackage"]["deprecated"] is True
    assert upstream["legacyPackage"]["deprecatedMessage"]

    assert registry["schema"] == "agentswitchboard.pi-adapter-registry.v1"
    assert registry["upstream"]["package"] == upstream["package"]
    assert registry["upstream"]["sourceRepository"] == upstream["sourceRepository"]
    assert registry["upstream"]["pinnedVersion"] == upstream["version"]
    assert registry["upstream"]["status"] == "verified-prerequisite"
    assert registry["upstream"]["verificationRecord"] == "tooling/pi/harness/upstream-verification.json"
    assert registry["configuration"]["preferredScope"] == "project-local"
    assert registry["configuration"]["globalConfigurationMutationAllowed"] is False
    assert registry["configuration"]["implicitHookInstallationAllowed"] is False
    assert registry["privacyClaimPolicy"]["localhostIsSufficient"] is False
    assert all(route["writerCount"] == 1 for route in registry["routes"])
    assert all(route["status"] == "contract-only" for route in registry["routes"])

    preflight_path = ROOT / "tooling/pi/Test-PiWorkstationPrereqs.ps1"
    assert preflight_path.is_file()
    preflight = preflight_path.read_text(encoding="utf-8-sig")
    for token in (
        "agentswitchboard.pi-workstation-prereqs.v1",
        "Invoke-NpmJson",
        "Get-OptionalPropertyValue",
        "metadataShapeComplete",
        "Live npm metadata was reachable but missing one or more expected version, engine, or deprecation fields.",
        "[string]$verification.package",
        "[string]$verification.legacyPackage.package",
        "'engines'",
        "'deprecated'",
        "upstream-drift",
        "installed-version-drift",
        "ready-to-install",
        "NoNetwork",
        "AllowUnready",
        "paths = $npmPaths",
        "legacyPackage",
    ):
        assert token in preflight, f"missing preflight contract token: {token}"
    assert "npm install -g @mariozechner/pi-coding-agent" not in preflight

    status_path = ROOT / "tooling/pi/Get-PiHarnessStatus.ps1"
    status_text = status_path.read_text(encoding="utf-8-sig")
    for token in (
        "ConvertTo-PowerShellSingleQuotedLiteral",
        "$nextScriptPath = Join-Path $RootPath $nextRelativePath",
        "-RootPath $rootLiteral",
    ):
        assert token in status_text, f"missing root-bound status continuation token: {token}"

    artifacts_names = [item["fileName"] for item in artifacts["artifacts"]]
    assert artifacts["tracked"] is False
    assert len(artifacts_names) == len(set(artifacts_names)), "artifact filenames must be unique"
    assert "pi-fusion-result.json" in artifacts_names
    assert "pi-validation-ledger.json" in artifacts_names
    forbidden = " ".join(artifacts["forbiddenContent"]).lower()
    assert "credentials" in forbidden and "raw prompts" in forbidden

    assert schema["$schema"].endswith("2020-12/schema")
    for definition in ("executionIdentity", "runContext", "roleOutput", "fusionResult", "validationLedger"):
        assert definition in schema["$defs"], f"missing schema definition: {definition}"
    run_context = schema["$defs"]["runContext"]
    assert "designatedWriter" in run_context["required"]
    assert "limits" in run_context["required"]
    identity = schema["$defs"]["executionIdentity"]
    assert set(("executor", "provider", "model", "endpointClass", "role")).issubset(identity["required"])

    assert intake["workflowId"] == "pi-task-intake"
    routes = {item["route"] for item in intake["routeRules"]}
    assert routes == {"single-agent", "opinion-fusion", "autovalidate", "blocked"}

    assert fusion["workflowId"] == "pi-opinion-fusion"
    assert fusion["bounds"]["parallelAgents"] == 2
    assert fusion["bounds"]["writersPerBranch"] == 1
    assert fusion["bounds"]["rawOutputTracked"] is False
    assert fusion["bounds"]["providerCallsAllowedByContract"] is False
    role_outputs = {role: value.get("output") for role, value in fusion["roles"].items() if value.get("output")}
    assert role_outputs["architect"] != role_outputs["builder"]
    fusion_actions = " ".join(step["action"] for step in fusion["steps"]).lower()
    for term in ("consensus", "divergence", "unresolved risks", "rejected alternatives"):
        assert term in fusion_actions

    assert autovalidate["workflowId"] == "pi-autovalidate"
    bounds = autovalidate["bounds"]
    assert 1 <= bounds["maximumAttempts"] <= 10
    assert bounds["maximumWallClockMinutes"] <= 60
    assert bounds["maximumNoProgressAttempts"] <= bounds["maximumAttempts"]
    assert bounds["tokenLimitRequired"] is True
    assert bounds["cancellationRequired"] is True
    assert bounds["writersPerBranch"] == 1
    auto_actions = " ".join(step["action"] for step in autovalidate["steps"]).lower()
    assert "may not weaken" in auto_actions
    assert "no progress" in auto_actions

    all_text = "\n".join(
        (ROOT / path).read_text(encoding="utf-8-sig")
        for path in (
            "tooling/pi/harness/codebase-map.json",
            "tooling/pi/harness/pi-adapter.registry.json",
            "tooling/pi/harness/upstream-verification.json",
            "tooling/pi/harness/artifact-registry.json",
            "tooling/pi/harness/workflows/task-intake.workflow.json",
            "tooling/pi/harness/workflows/opinion-fusion.workflow.json",
            "tooling/pi/harness/workflows/autovalidate.workflow.json",
            ".ai/skills/pi-fusion-orchestration/SKILL.md",
        )
    )
    for forbidden_snippet in (
        "npm install -g @mariozechner/pi-coding-agent",
        "%USERPROFILE%\\.pi",
        "pi.llm.generate",
        "dangerously-skip-permissions",
    ):
        assert forbidden_snippet not in all_text, f"unverified executable snippet embedded: {forbidden_snippet}"

    print("PASS: AgentSwitchboard Pi operational harness contracts")


if __name__ == "__main__":
    main()
