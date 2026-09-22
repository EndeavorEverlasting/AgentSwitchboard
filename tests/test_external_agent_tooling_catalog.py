from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "tooling/harness/operational/external-agent-tooling"
REGISTRY = f"{BASE}/external-agent-tooling.registry.json"
MANIFEST = f"{BASE}/manifest.json"
SCHEMA = f"{BASE}/schemas/external-agent-tooling-registry.schema.json"
CODEBASE_MAP = f"{BASE}/codebase-map.json"
ARTIFACT_REGISTRY = f"{BASE}/artifact-registry.json"
WORKFLOW = f"{BASE}/workflows/tool-intake.workflow.json"
VALID_FIXTURE = f"{BASE}/fixtures/valid-source-only.fixture.json"
INVALID_FIXTURE = f"{BASE}/fixtures/invalid-proof-promotion.fixture.json"
GUIDE = "docs/harness/external-agent-tooling-catalog.md"
STATE = f"{BASE}/reports/CURRENT_STATE.md"

EXPECTED_NAMES = ['Understand Anything', 'Colibri', 'OpenCode', 'ChatGPT', 'Anti-gravity', 'Cursor', 'GitHub Copilot', 'Codex', 'Gemini CLI', 'GCC', 'Tree-sitter', 'Unsloth', 'DeepSeek Harness', 'Cordis', 'Koishi', 'Aider', 'LangChain', "Matt Pocock's Skill Suite", 'Groomi /grooming', '/twospec', '/twotickets', '/implements', '/code-review', 'Writing for Agents', 'Improved Codebase Architecture', 'GStack', 'Superpowers', 'GSD', 'Git Reverse', 'Groq', 'OpenRouter', 'Azure OpenAI', 'Google AI Studio', 'Prime Agent', 'Recursive Language Models (RLMs)', 'Schema', 'Neo4j', 'GraphRAG', 'Cypher', 'Hermes Agent', 'Goose', 'Model Context Protocol (MCP)', 'Cognite', 'pgvector', 'LanceDB']
EXPECTED_ENTRY_KEYS = {
    "id", "name", "aliases", "kind", "mentionClass", "sourceBucket", "category", "summary",
    "evidenceState", "verificationRequiredBeforeAdoption", "disposition", "integrationAuthority",
    "capabilityState", "runtimeProof", "trustProof", "privacyProof",
}
ALLOWED_EVIDENCE = {"reported", "partially-verified", "verified", "unresolved"}
ALLOWED_DISPOSITIONS = {"existing-reference", "evaluate", "compatibility", "supporting", "comparison", "watchlist"}


def load_json(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def source_only_entry_is_valid(entry: dict) -> bool:
    return (
        set(entry) == EXPECTED_ENTRY_KEYS
        and entry.get("evidenceState") in ALLOWED_EVIDENCE
        and entry.get("verificationRequiredBeforeAdoption") is True
        and entry.get("disposition") in ALLOWED_DISPOSITIONS
        and entry.get("integrationAuthority") == "none"
        and entry.get("capabilityState") == "unknown"
        and entry.get("runtimeProof") == "unproved"
        and entry.get("trustProof") == "unproved"
        and entry.get("privacyProof") == "unproved"
    )


def main() -> None:
    required = (REGISTRY, MANIFEST, SCHEMA, CODEBASE_MAP, ARTIFACT_REGISTRY, WORKFLOW, VALID_FIXTURE, INVALID_FIXTURE, GUIDE, STATE)
    for relative in required:
        assert (ROOT / relative).is_file(), relative

    registry = load_json(REGISTRY)
    manifest = load_json(MANIFEST)
    schema = load_json(SCHEMA)
    codebase_map = load_json(CODEBASE_MAP)
    workflow = load_json(WORKFLOW)
    valid_fixture = load_json(VALID_FIXTURE)
    invalid_fixture = load_json(INVALID_FIXTURE)

    assert registry["schemaVersion"] == 1
    assert registry["catalogId"] == "agentswitchboard.external-agent-tooling.v1"
    assert manifest["catalogCount"] == 45
    assert schema["additionalProperties"] is False

    policy = registry["policy"]
    for key in (
        "sourceClaimsAreFacts", "installationAuthorizedByCatalog", "providerCallsAuthorizedByCatalog",
        "networkExecutionAuthorizedByCatalog", "liveTargetMutationAuthorizedByCatalog",
        "catalogPresenceProvesInstalled", "catalogPresenceProvesExecutable", "catalogPresenceProvesTrusted",
        "catalogPresenceProvesPrivate", "catalogPresenceProvesRuntimeReady",
    ):
        assert policy[key] is False, key
    assert policy["capabilityTruthOwner"] == "CAPABILITIES.md and runtime-specific canonical owners"

    entries = registry["entries"]
    assert len(entries) == 45
    ids = [entry["id"] for entry in entries]
    names = [entry["name"] for entry in entries]
    assert len(ids) == len(set(ids)), "entry ids must be unique"
    assert set(names) == set(EXPECTED_NAMES), sorted(set(EXPECTED_NAMES) - set(names))
    assert all(source_only_entry_is_valid(entry) for entry in entries)
    assert set(entry["sourceBucket"] for entry in entries) == set(registry["sourceBuckets"])

    entry_schema = schema["properties"]["entries"]["items"]
    assert entry_schema["additionalProperties"] is False
    assert set(entry_schema["required"]) == EXPECTED_ENTRY_KEYS
    assert entry_schema["properties"]["capabilityState"]["const"] == "unknown"
    assert entry_schema["properties"]["runtimeProof"]["const"] == "unproved"
    assert entry_schema["properties"]["trustProof"]["const"] == "unproved"
    assert entry_schema["properties"]["privacyProof"]["const"] == "unproved"

    assert source_only_entry_is_valid(valid_fixture)
    assert not source_only_entry_is_valid(invalid_fixture)
    assert invalid_fixture["capabilityState"] == "verified"

    aider = next(entry for entry in entries if entry["id"] == "aider")
    assert "Ader" in aider["aliases"]
    unresolved = {entry["id"] for entry in entries if entry["evidenceState"] == "unresolved"}
    assert {"anti-gravity", "cognite"} <= unresolved
    claim_ids = {claim["claimId"] for claim in registry["reportedClaims"]}
    assert "deepseek-prefix-caching-cost" in claim_ids
    assert all(claim["reuseAllowedWithoutVerification"] is False for claim in registry["reportedClaims"])

    assert workflow["workflowId"] == "external-agent-tooling-intake"
    step_ids = [step["id"] for step in workflow["steps"]]
    assert step_ids == ["capture", "classify", "overlap", "verify-upstream", "risk-boundary", "proof-boundary", "disposition", "validate"]

    assert "skill" not in manifest["entrypoints"]
    paths = {item["path"] for item in codebase_map["paths"]}
    assert ".ai/skills/external-agent-tooling-intake/SKILL.md" not in paths
    deferred = manifest["salvage"]["deferredSharedRegistration"]
    assert deferred["manifest"]["key"] == "externalAgentToolingManifest"
    assert {item["id"] for item in deferred["validators"]["entries"]} == {"external-agent-tooling-python", "external-agent-tooling-powershell"}
    assert deferred["workflowRegistry"]["action"].startswith("no-change-in-leaf")
    assert deferred["workflowRegistry"]["skill"] is None

    guide = (ROOT / GUIDE).read_text(encoding="utf-8")
    state = (ROOT / STATE).read_text(encoding="utf-8")
    for token in ("source-only", "capabilityState", "Shared registration is deferred", "Proof ceiling"):
        assert token.lower() in (guide + state).lower(), token

    print("PASS: external agent tooling source-only catalog (45 entries)")


if __name__ == "__main__":
    main()
