#!/usr/bin/env python3
"""Dependency-free contracts for the offline app harness validator."""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_json(relative: str) -> dict:
    path = ROOT / relative
    assert path.is_file(), f"missing JSON file: {relative}"
    return json.loads(path.read_text(encoding="utf-8"))


def reaches(start: str, target: str, edges: list[dict]) -> bool:
    queue: deque[str] = deque([start])
    seen = {start}
    while queue:
        current = queue.popleft()
        if current == target:
            return True
        for edge in edges:
            if edge["from"] != current:
                continue
            nxt = edge["to"]
            if nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)
    return False


def main() -> None:
    graph = load_json(".ai/harness/app-composition.graph.json")
    graph_schema = load_json(".ai/harness/schemas/app-composition-graph.schema.json")
    result_schema = load_json(".ai/harness/schemas/app-harness-validation.schema.json")
    manifest = load_json(".ai/harness/manifest.json")
    artifact_registry = load_json(".ai/harness/artifact-registry.json")

    assert graph["schema"] == "agentswitchboard.app-composition-graph.v1"
    assert graph_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert result_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert result_schema["properties"]["proofLevel"]["const"] == "offline-synthetic-harness"

    nodes = graph["nodes"]
    edges = graph["edges"]
    node_ids = [node["id"] for node in nodes]
    edge_ids = [edge["id"] for edge in edges]
    assert len(node_ids) == len(set(node_ids)), "composition graph has duplicate node IDs"
    assert len(edge_ids) == len(set(edge_ids)), "composition graph has duplicate edge IDs"
    assert graph["observerNodeId"] in set(node_ids), "observer node is not registered"

    node_by_id = {node["id"]: node for node in nodes}
    for edge in edges:
        assert edge["from"] in node_by_id, f"dangling source: {edge['id']}"
        assert edge["to"] in node_by_id, f"dangling target: {edge['id']}"

    for node in nodes:
        if node["required"]:
            for relative in node["paths"]:
                assert (ROOT / relative).is_file(), f"required graph path missing: {node['id']} -> {relative}"
            assert any(
                edge["required"] and (edge["from"] == node["id"] or edge["to"] == node["id"])
                for edge in edges
            ), f"required graph node has no required edge: {node['id']}"
            if node["kind"] == "validator":
                assert node["safeOffline"] is True, f"validator is not safeOffline: {node['id']}"
            if node["topologyRole"] in {"observed", "output"}:
                assert reaches(graph["observerNodeId"], node["id"], edges), (
                    f"observer cannot reach required node: {node['id']}"
                )
            elif node["topologyRole"] == "ingress":
                assert reaches(node["id"], graph["observerNodeId"], edges), (
                    f"ingress cannot reach observer: {node['id']}"
                )

    observer_edges = [edge for edge in edges if edge["from"] == graph["observerNodeId"]]
    observed_targets = {edge["to"] for edge in observer_edges}
    for required_target in {
        "contract.harness-manifest",
        "schema.run-context",
        "registry.artifacts",
        "renderer.english-matrix",
        "validator.doctrine",
        "validator.documentation",
        "validator.repository-family",
        "validator.public-plans",
        "contract.hook-policy",
        "contract.runtime-event-policy",
        "contract.runtime-event-topology",
        "validator.runtime-events",
        "schema.runtime-event-envelope",
        "schema.runtime-event-topology",
        "contract.device-profile-policy",
        "registry.device-profiles",
        "schema.device-profile-registry",
        "validator.device-profiles",
        "optional.mcp-lsp",
        "artifact.validation-json",
        "artifact.validation-report",
    }:
        assert required_target in observed_targets, f"observer edge missing: {required_target}"

    script_path = ROOT / "scripts/Test-AppHarness.ps1"
    cmd_path = ROOT / "Test-AppHarness.cmd"
    template_path = ROOT / ".ai/harness/app-harness-report.template.md"
    assert script_path.is_file()
    assert cmd_path.is_file()
    assert template_path.is_file()

    script = script_path.read_text(encoding="utf-8")
    cmd = cmd_path.read_text(encoding="utf-8")
    template = template_path.read_text(encoding="utf-8")

    for token in (
        "APP HARNESS VALIDATION",
        "app-harness-validation.json",
        "app-harness-validation.md",
        "lsp_project_not_loaded",
        "networkAllowed = $false",
        "runtimeAllowed = $false",
        "mutationAllowed = $false",
        "offline-synthetic-harness",
        "Test-GraphReachability",
        "required_validator_broken",
    ):
        assert token in script, f"validator contract token missing: {token}"

    forbidden_script_tokens = (
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "Start-Process",
        "Start-Job",
        "git push",
        "git commit",
        "git reset",
        "git clean",
        "git checkout",
        "git switch",
        "Setup-AgentSwitchboard",
        "Start-Gnhf",
        "Get-AgentSwitchboardStartupReport",
        "AgentSwitchboard.cmd",
    )
    for token in forbidden_script_tokens:
        assert token not in script, f"offline validator contains forbidden execution surface: {token}"

    assert "pwsh" in cmd.lower()
    assert "scripts\\Test-AppHarness.ps1" in cmd
    for token in ("start ", "cmd /c", "explorer", "http://", "https://", "AgentSwitchboard.cmd"):
        assert token.lower() not in cmd.lower(), f"one-command entrypoint can launch forbidden surface: {token}"

    for placeholder in (
        "{{repository}}",
        "{{branch}}",
        "{{commit}}",
        "{{matrix}}",
        "{{summary}}",
        "{{jsonPath}}",
        "{{reportPath}}",
        "{{proofCeiling}}",
    ):
        assert placeholder in template, f"report renderer placeholder missing: {placeholder}"

    entrypoints = manifest["entrypoints"]
    assert entrypoints["appCompositionGraph"] == ".ai/harness/app-composition.graph.json"
    assert entrypoints["appHarnessValidator"] == "scripts/Test-AppHarness.ps1"
    assert entrypoints["appHarnessReportTemplate"] == ".ai/harness/app-harness-report.template.md"
    assert entrypoints["deviceProfilePolicy"] == ".ai/harness/device-profile-launcher.policy.json"
    assert entrypoints["deviceProfileRegistry"] == ".ai/harness/device-profile-registry.json"
    assert entrypoints["deviceProfileValidator"] == "scripts/Test-DeviceProfileLauncherContract.ps1"
    assert ".ai/harness/schemas/app-composition-graph.schema.json" in manifest["schemas"]
    assert ".ai/harness/schemas/app-harness-validation.schema.json" in manifest["schemas"]
    assert ".ai/harness/schemas/device-profile-registry.schema.json" in manifest["schemas"]
    assert manifest["appHarnessValidation"]["readOnly"] is True
    assert manifest["appHarnessValidation"]["runtimeAllowed"] is False
    assert manifest["appHarnessValidation"]["networkAllowed"] is False
    assert manifest["appHarnessValidation"]["targetMutationAllowed"] is False
    assert manifest["deviceProfiles"]["contractOnly"] is True
    assert manifest["deviceProfiles"]["runtimeExecutionAllowed"] is False

    artifact_ids = {artifact["artifactId"]: artifact for artifact in artifact_registry["artifacts"]}
    for artifact_id in (
        "app-harness-validation-json",
        "app-harness-validation-report",
        "device-profile-launch-result",
        "device-profile-certification",
    ):
        assert artifact_id in artifact_ids, f"artifact registry entry missing: {artifact_id}"
        assert artifact_ids[artifact_id]["tracked"] is False
        assert artifact_ids[artifact_id]["sensitivity"] == "local-operational"

    print("PASS: one-command app harness validator contracts")


if __name__ == "__main__":
    main()
