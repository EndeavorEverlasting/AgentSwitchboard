from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REGISTRY = "tooling/harness/operational/external-agent-tooling/external-agent-tooling.registry.json"
MANIFEST = "tooling/harness/operational/external-agent-tooling/manifest.json"
SCHEMA = "tooling/harness/operational/external-agent-tooling/schemas/external-agent-tooling-registry.schema.json"
CODEBASE_MAP = "tooling/harness/operational/external-agent-tooling/codebase-map.json"
ARTIFACT_REGISTRY = "tooling/harness/operational/external-agent-tooling/artifact-registry.json"
WORKFLOW = "tooling/harness/operational/external-agent-tooling/workflows/tool-intake.workflow.json"
SKILL = ".ai/skills/external-agent-tooling-intake/SKILL.md"
GUIDE = "docs/harness/external-agent-tooling-catalog.md"
STATE = "tooling/harness/operational/external-agent-tooling/reports/CURRENT_STATE.md"

EXPECTED_NAMES = ['Understand Anything', 'Colibri', 'OpenCode', 'ChatGPT', 'Anti-gravity', 'Cursor', 'GitHub Copilot', 'Codex', 'Gemini CLI', 'GCC', 'Tree-sitter', 'Unsloth', 'DeepSeek Harness', 'Cordis', 'Koishi', 'Aider', 'LangChain', "Matt Pocock's Skill Suite", 'Groomi /grooming', '/twospec', '/twotickets', '/implements', '/code-review', 'Writing for Agents', 'Improved Codebase Architecture', 'GStack', 'Superpowers', 'GSD', 'Git Reverse', 'Groq', 'OpenRouter', 'Azure OpenAI', 'Google AI Studio', 'Prime Agent', 'Recursive Language Models (RLMs)', 'Schema', 'Neo4j', 'GraphRAG', 'Cypher', 'Hermes Agent', 'Goose', 'Model Context Protocol (MCP)', 'Cognite', 'pgvector', 'LanceDB']

def load_json(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))

def main() -> None:
    for relative in (REGISTRY, MANIFEST, SCHEMA, CODEBASE_MAP, ARTIFACT_REGISTRY, WORKFLOW, SKILL, GUIDE, STATE):
        assert (ROOT / relative).is_file(), relative

    registry = load_json(REGISTRY)
    manifest = load_json(MANIFEST)
    schema = load_json(SCHEMA)
    workflow = load_json(WORKFLOW)

    assert registry["schemaVersion"] == 1
    assert registry["catalogId"] == "agentswitchboard.external-agent-tooling.v1"
    assert manifest["catalogCount"] == 45
    assert schema["additionalProperties"] is False

    policy = registry["policy"]
    for key in (
        "sourceClaimsAreFacts",
        "installationAuthorizedByCatalog",
        "providerCallsAuthorizedByCatalog",
        "networkExecutionAuthorizedByCatalog",
        "liveTargetMutationAuthorizedByCatalog",
    ):
        assert policy[key] is False, key

    entries = registry["entries"]
    assert len(entries) == 45
    ids = [entry["id"] for entry in entries]
    names = [entry["name"] for entry in entries]
    assert len(ids) == len(set(ids)), "entry ids must be unique"
    assert set(names) == set(EXPECTED_NAMES), sorted(set(EXPECTED_NAMES) - set(names))
    assert all(entry["verificationRequiredBeforeAdoption"] is True for entry in entries)
    assert all(entry["integrationAuthority"] == "none" for entry in entries)
    assert set(entry["sourceBucket"] for entry in entries) == set(registry["sourceBuckets"])

    aider = next(entry for entry in entries if entry["id"] == "aider")
    assert "Ader" in aider["aliases"]
    assert aider["evidenceState"] == "partially-verified"

    unresolved = {entry["id"] for entry in entries if entry["evidenceState"] == "unresolved"}
    assert {"anti-gravity", "cognite"} <= unresolved

    claim_ids = {claim["claimId"] for claim in registry["reportedClaims"]}
    assert "deepseek-prefix-caching-cost" in claim_ids
    assert all(claim["reuseAllowedWithoutVerification"] is False for claim in registry["reportedClaims"])

    assert workflow["workflowId"] == "external-agent-tooling-intake"
    step_ids = [step["id"] for step in workflow["steps"]]
    assert step_ids == ["capture", "classify", "overlap", "verify-upstream", "risk-boundary", "disposition", "validate"]

    skill = (ROOT / SKILL).read_text(encoding="utf-8")
    for token in (
        "id: external-agent-tooling-intake",
        "status: canonical",
        "## Trigger",
        "## Inputs",
        "## Procedure",
        "## Outputs",
        "## Deterministic validation",
        "## Forbidden scope",
        "## Stop and escalate",
    ):
        assert token in skill, token

    operational_manifest = load_json("tooling/harness/operational/manifest.json")
    assert operational_manifest["entrypoints"]["externalAgentToolingManifest"] == MANIFEST

    validator_registry = load_json("tooling/harness/operational/validator-registry.json")
    validator_ids = {item["id"] for item in validator_registry["validators"]}
    assert {"external-agent-tooling-python", "external-agent-tooling-powershell"} <= validator_ids

    workflow_registry = load_json("tooling/harness/operational/workflow-registry.json")
    routes = workflow_registry["specializedRouting"]
    assert any(route.get("skill") == SKILL for route in routes)

    print("PASS: external agent tooling catalog (45 entries)")

if __name__ == "__main__":
    main()
