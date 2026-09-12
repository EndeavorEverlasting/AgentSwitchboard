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
    system_bootstrap = load("tooling/pi/harness/system-bootstrap.contract.json")
    child = load("tooling/pi/harness/child-agent-invocation.contract.json")
    artifacts = load("tooling/pi/harness/artifact-registry.json")
    schema = load("tooling/pi/harness/schemas/pi-harness-contracts.schema.json")
    intake = load("tooling/pi/harness/workflows/task-intake.workflow.json")
    fusion = load("tooling/pi/harness/workflows/opinion-fusion.workflow.json")
    autovalidate = load("tooling/pi/harness/workflows/autovalidate.workflow.json")

    assert codebase["schema"] == "agentswitchboard.pi-codebase-map.v1"
    assert codebase["entrypoints"]["validator"] == "scripts/Test-PiHarnessCompleteness.ps1"
    assert codebase["entrypoints"]["workstationPrereqs"] == "tooling/pi/Test-PiWorkstationPrereqs.ps1"
    assert codebase["entrypoints"]["systemBootstrap"] == "tooling/pi/Install-AgentSwitchboardPiSystem.ps1"
    assert codebase["entrypoints"]["childInvocation"] == "tooling/pi/Invoke-AgentSwitchboardPiChild.ps1"
    assert codebase["entrypoints"]["upstreamVerification"] == "tooling/pi/harness/upstream-verification.json"
    assert any("one writer" in trap.lower() for trap in codebase["knownTraps"])
    assert any("npm" in trap.lower() and "compatibility" in trap.lower() for trap in codebase["knownTraps"])
    assert any("pair" in trap.lower() and "agent" in trap.lower() for trap in codebase["knownTraps"])
    assert any("raw pi json" in trap.lower() for trap in codebase["knownTraps"])

    assert upstream["schema"] == "agentswitchboard.pi-upstream-verification.v1"
    assert upstream["verifiedAt"] == "2026-09-11"
    assert upstream["package"] == "@earendil-works/pi-coding-agent"
    assert upstream["version"] == "0.85.1"
    assert upstream["versionTag"] == "v0.85.1"
    assert upstream["sourceRepository"] == "earendil-works/pi"
    assert upstream["sourceUrl"] == "https://github.com/earendil-works/pi"
    assert upstream["minimumNodeVersion"] == "22.19.0"
    assert upstream["nodeEngine"] == ">=22.19.0"
    assert "--ignore-scripts" in upstream["installCommand"]
    assert upstream["rollbackCommand"] == "npm uninstall -g @earendil-works/pi-coding-agent"
    assert "Windows" in upstream["supportedOperatingSystems"]
    assert upstream["expectedExecutableMapping"]["command"] == "pi"
    assert upstream["expectedExecutableMapping"]["packageRelativePath"] == "dist/bundle/cli.js"
    assert len(upstream["officialEvidence"]) >= 5
    assert upstream["legacyPackage"]["package"] == "@mariozechner/pi-coding-agent"
    assert upstream["legacyPackage"]["deprecated"] is True
    native = upstream["nativeRelease"]
    assert native["preferredWindowsDistribution"] == "standalone-release"
    assert native["windows"]["x64"]["assetName"] == "pi-windows-x64.zip"
    assert native["windows"]["x64"]["sha256"] == "002fa95b90d521245b9985d8f168caebc237ad56e7e30b319807dee1b2e17e1c"
    assert native["windows"]["arm64"]["assetName"] == "pi-windows-arm64.zip"
    assert native["windows"]["arm64"]["sha256"] == "b25e96fe64c9f41f75a924c0d36f395abb98d6c6fec0b78aaa0b86926f938bb4"
    assert native["systemBootstrap"]["packageManagerRequired"] is False
    assert native["systemBootstrap"]["nodeRuntimeRequired"] is False
    assert upstream["programmaticModes"]["json"] is True
    assert upstream["programmaticModes"]["rpc"] is True
    assert upstream["programmaticModes"]["rpcFraming"] == "strict LF-delimited JSONL"

    assert system_bootstrap["contractId"] == "agentswitchboard.pi-system-bootstrap.v1"
    assert system_bootstrap["owner"] == "tooling/pi/Install-AgentSwitchboardPiSystem.ps1"
    assert system_bootstrap["preflight"]["packageManagersAssumed"] == []
    assert system_bootstrap["preflight"]["nodeRuntimeRequired"] is False
    assert system_bootstrap["safety"]["globalPiConfigurationMutationAllowed"] is False
    assert system_bootstrap["safety"]["providerAuthenticationMutationAllowed"] is False
    assert system_bootstrap["safety"]["projectTrustMutationAllowed"] is False
    assert system_bootstrap["safety"]["wholeScriptPowerShellRequired"] is True

    assert registry["schema"] == "agentswitchboard.pi-adapter-registry.v1"
    assert registry["upstream"]["package"] == upstream["package"]
    assert registry["upstream"]["sourceRepository"] == upstream["sourceRepository"]
    assert registry["upstream"]["pinnedVersion"] == upstream["version"]
    assert registry["upstream"]["status"] == "verified-prerequisite"
    assert registry["configuration"]["preferredScope"] == "project-local"
    assert registry["configuration"]["globalConfigurationMutationAllowed"] is False
    assert registry["configuration"]["implicitHookInstallationAllowed"] is False
    assert registry["systemRuntime"]["packageManagerRequired"] is False
    assert registry["systemRuntime"]["nodeRuntimeRequired"] is False
    assert registry["childInvocation"]["pairwiseAgentConfigurationRequired"] is False
    assert registry["childInvocation"]["separateChildContext"] is True
    assert registry["childInvocation"]["boundedResultEnvelope"] is True
    assert registry["privacyClaimPolicy"]["localhostIsSufficient"] is False
    assert all(route["writerCount"] == 1 for route in registry["routes"])
    assert all(route["status"] == "contract-only" for route in registry["routes"])

    assert child["contractId"] == "agentswitchboard.pi-child-agent.v1"
    assert child["architecture"]["pairwiseAgentConfigurationRequired"] is False
    assert child["piTransport"]["mode"] == "json-subprocess"
    assert child["piTransport"]["upstreamRpcAvailable"] is True
    assert child["writeModes"]["writer"]["isolatedWorktreeRequired"] is True
    assert child["writeModes"]["writer"]["mainOrDefaultBranchAllowed"] is False
    assert child["writeModes"]["writer"]["writersPerMutationSurface"] == 1
    assert child["resultEnvelope"]["rawPromptIncludedInResultEnvelope"] is False
    assert child["resultEnvelope"]["rawEventMayContainPrompt"] is True
    assert child["resultEnvelope"]["rawEventsTracked"] is False
    assert child["parallelism"]["coordinatorOwnsRejoin"] is True
    assert child["parallelism"]["childMayMergeDefaultBranch"] is False

    preflight_path = ROOT / "tooling/pi/Test-PiWorkstationPrereqs.ps1"
    assert preflight_path.is_file()
    preflight = preflight_path.read_text(encoding="utf-8-sig")
    for token in (
        "agentswitchboard.pi-workstation-prereqs.v1",
        "Invoke-NpmJson",
        "Invoke-BoundedProbe",
        "Get-OptionalPropertyValue",
        "Get-ProjectShellPath",
        "Get-BoundedPathEvidence",
        "Test-PathInsideRoot",
        "Normalize-RepositoryUrl",
        "ProbeTimeoutSeconds",
        "OUTPUT_DIRECTORY_INSIDE_REPOSITORY",
        "UPSTREAM_VERIFICATION_MISSING",
        "UPSTREAM_VERIFICATION_INCOMPLETE",
        "upstream-drift",
        "installed-version-drift",
        "ready-to-install",
        "NoNetwork",
        "AllowUnready",
    ):
        assert token in preflight, f"missing preflight contract token: {token}"
    assert "npm install -g @mariozechner/pi-coding-agent" not in preflight
    assert "Read-only local prerequisite and bounded live npm metadata proof" in preflight

    executable_contract = ROOT / "tests/Test-PiWorkstationPrereqsContracts.ps1"
    assert executable_contract.is_file()
    executable_text = executable_contract.read_text(encoding="utf-8-sig")
    for token in ("UPSTREAM_VERIFICATION_MISSING", "pathsOmitted", "configured-shell/precedence", "shellPath"):
        assert token in executable_text, f"missing executable prerequisite contract token: {token}"

    bootstrap_text = (ROOT / "tooling/pi/Install-AgentSwitchboardPiSystem.ps1").read_text(encoding="utf-8-sig")
    for token in (
        "agentswitchboard.pi-system-bootstrap.v1",
        "Get-FileHash",
        "Expand-Archive",
        "PI_RELEASE_SHA256_MISMATCH",
        "PI_LAUNCHER_PATH_ALREADY_OWNED",
        "PI_INSTALL_DIRECTORY_ALREADY_OWNED",
        "AgentSwitchboard\\agents\\pi",
        "AgentSwitchboard\\bin",
        "GIT_BASH_REQUIRED",
    ):
        assert token in bootstrap_text, f"missing system bootstrap token: {token}"
    for forbidden in ("npm install", "choco install", "scoop install", "winget install", "Invoke-Expression"):
        assert forbidden.lower() not in bootstrap_text.lower()

    child_text = (ROOT / "tooling/pi/Invoke-AgentSwitchboardPiChild.ps1").read_text(encoding="utf-8-sig")
    for token in (
        "--mode','json",
        "--no-session",
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "--no-approve",
        "agent_end",
        "completed-unvalidated",
        "Writer child requires an isolated linked Git worktree",
        "PI_CHILD_READ_ONLY_MUTATION",
    ):
        assert token in child_text, f"missing child adapter token: {token}"
    assert "Get-Command pi" not in child_text
    assert "ApiKey" not in child_text

    hook_path = ROOT / "tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1"
    hook_text = hook_path.read_text(encoding="utf-8-sig")
    for token in ("pi-workstation-prereqs.json", "pi-workstation-prereqs.md", "pi-harness-status.json"):
        assert token in hook_text, f"pre-commit missing blocked evidence token: {token}"

    status_path = ROOT / "tooling/pi/Get-PiHarnessStatus.ps1"
    status_text = status_path.read_text(encoding="utf-8-sig")
    for token in ("ConvertTo-PowerShellSingleQuotedLiteral", "$nextScriptPath = Join-Path $RootPath $nextRelativePath", "-RootPath $rootLiteral"):
        assert token in status_text, f"missing root-bound status continuation token: {token}"

    artifact_names = [item["fileName"] for item in artifacts["artifacts"]]
    assert artifacts["tracked"] is False
    assert len(artifact_names) == len(set(artifact_names)), "artifact filenames must be unique"
    assert "pi-fusion-result.json" in artifact_names
    assert "pi-validation-ledger.json" in artifact_names
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
            "tooling/pi/harness/system-bootstrap.contract.json",
            "tooling/pi/harness/child-agent-invocation.contract.json",
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
