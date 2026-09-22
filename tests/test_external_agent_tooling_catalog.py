from __future__ import annotations

import json
import re
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
ALLOWED_MENTION_CLASSES = {"primary", "compatibility", "supporting", "comparison"}
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")


class ContractFailure(RuntimeError):
    pass


def check(condition: object, message: str) -> None:
    if not condition:
        raise ContractFailure(message)


def load_json(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def entry_matches_schema_shape(entry: dict, entry_schema: dict) -> list[str]:
    errors: list[str] = []
    required = set(entry_schema.get("required", []))
    properties = entry_schema.get("properties", {})
    if entry_schema.get("additionalProperties") is False:
        unexpected = set(entry) - set(properties)
        if unexpected:
            errors.append(f"unexpected keys: {sorted(unexpected)}")
    missing = required - set(entry)
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
    for key, rule in properties.items():
        if key not in entry:
            continue
        value = entry[key]
        if "const" in rule and value != rule["const"]:
            errors.append(f"{key}: expected const {rule['const']!r}, got {value!r}")
        if "enum" in rule and value not in rule["enum"]:
            errors.append(f"{key}: {value!r} not in enum {rule['enum']}")
        if rule.get("type") == "string" and not isinstance(value, str):
            errors.append(f"{key}: expected string")
        if "pattern" in rule and isinstance(value, str) and not re.fullmatch(rule["pattern"], value):
            errors.append(f"{key}: {value!r} does not match {rule['pattern']}")
        if "minLength" in rule and isinstance(value, str) and len(value) < rule["minLength"]:
            errors.append(f"{key}: shorter than minLength {rule['minLength']}")
        if rule.get("type") == "array" and not isinstance(value, list):
            errors.append(f"{key}: expected array")
    return errors


def validate_registry_against_schema(registry: dict, schema: dict) -> None:
    top_required = set(schema.get("required", []))
    top_properties = set(schema.get("properties", {}))
    if schema.get("additionalProperties") is False:
        unexpected = set(registry) - top_properties
        check(not unexpected, f"registry unexpected top-level keys: {sorted(unexpected)}")
    missing = top_required - set(registry)
    check(not missing, f"registry missing top-level keys: {sorted(missing)}")

    entry_schema = schema["properties"]["entries"]["items"]
    for entry in registry["entries"]:
        errors = entry_matches_schema_shape(entry, entry_schema)
        check(not errors, f"entry {entry.get('id', '?')}: {'; '.join(errors)}")

    claim_schema = schema["properties"]["reportedClaims"]["items"]
    for claim in registry.get("reportedClaims", []):
        errors = entry_matches_schema_shape(claim, claim_schema)
        check(not errors, f"claim {claim.get('claimId', '?')}: {'; '.join(errors)}")

    policy_schema = schema["properties"]["policy"]
    policy_errors = entry_matches_schema_shape(registry["policy"], policy_schema)
    check(not policy_errors, f"policy: {'; '.join(policy_errors)}")


def source_only_entry_is_valid(entry: dict) -> bool:
    return (
        set(entry) == EXPECTED_ENTRY_KEYS
        and isinstance(entry.get("id"), str)
        and bool(ID_PATTERN.fullmatch(entry["id"]))
        and entry.get("mentionClass") in ALLOWED_MENTION_CLASSES
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
        check((ROOT / relative).is_file(), f"missing required file: {relative}")

    registry = load_json(REGISTRY)
    manifest = load_json(MANIFEST)
    schema = load_json(SCHEMA)
    codebase_map = load_json(CODEBASE_MAP)
    workflow = load_json(WORKFLOW)
    valid_fixture = load_json(VALID_FIXTURE)
    invalid_fixture = load_json(INVALID_FIXTURE)

    check(registry["schemaVersion"] == 1, "registry schemaVersion must be 1")
    check(registry["catalogId"] == "agentswitchboard.external-agent-tooling.v1", "catalogId drifted")
    check(manifest["catalogCount"] == 45, "manifest catalogCount must be 45")
    check(schema["additionalProperties"] is False, "schema must be closed")

    policy = registry["policy"]
    for key in (
        "sourceClaimsAreFacts", "installationAuthorizedByCatalog", "providerCallsAuthorizedByCatalog",
        "networkExecutionAuthorizedByCatalog", "liveTargetMutationAuthorizedByCatalog",
        "catalogPresenceProvesInstalled", "catalogPresenceProvesExecutable", "catalogPresenceProvesTrusted",
        "catalogPresenceProvesPrivate", "catalogPresenceProvesRuntimeReady",
    ):
        check(policy[key] is False, f"unsafe policy flag must be false: {key}")
    check(policy["capabilityTruthOwner"] == "CAPABILITIES.md and runtime-specific canonical owners", "capabilityTruthOwner drifted")

    validate_registry_against_schema(registry, schema)

    entries = registry["entries"]
    check(len(entries) == 45, f"expected 45 entries, got {len(entries)}")
    ids = [entry["id"] for entry in entries]
    names = [entry["name"] for entry in entries]
    check(len(ids) == len(set(ids)), "entry ids must be unique")
    check(set(names) == set(EXPECTED_NAMES), f"name set mismatch: missing {sorted(set(EXPECTED_NAMES) - set(names))}")
    for entry in entries:
        check(source_only_entry_is_valid(entry), f"entry violates source-only boundary: {entry.get('id')}")
    check(set(entry["sourceBucket"] for entry in entries) == set(registry["sourceBuckets"]), "sourceBucket values must be declared")

    entry_schema = schema["properties"]["entries"]["items"]
    check(entry_schema["additionalProperties"] is False, "entry schema must be closed")
    check(set(entry_schema["required"]) == EXPECTED_ENTRY_KEYS, "entry schema required keys drifted")
    check(entry_schema["properties"]["capabilityState"]["const"] == "unknown", "schema must pin capabilityState=unknown")
    check(entry_schema["properties"]["runtimeProof"]["const"] == "unproved", "schema must pin runtimeProof=unproved")
    check(entry_schema["properties"]["trustProof"]["const"] == "unproved", "schema must pin trustProof=unproved")
    check(entry_schema["properties"]["privacyProof"]["const"] == "unproved", "schema must pin privacyProof=unproved")

    valid_errors = entry_matches_schema_shape(valid_fixture, entry_schema)
    check(not valid_errors, f"positive fixture must match entry schema: {valid_errors}")
    check(source_only_entry_is_valid(valid_fixture), "positive fixture must be source-only")
    invalid_errors = entry_matches_schema_shape(invalid_fixture, entry_schema)
    check(bool(invalid_errors), "negative fixture must fail schema shape validation")
    check(not source_only_entry_is_valid(invalid_fixture), "negative fixture must fail source-only boundary")
    check(invalid_fixture["capabilityState"] == "verified", "negative fixture must promote capabilityState")
    check("negative" in invalid_fixture["summary"].lower(), "negative fixture summary must identify itself as negative")

    aider = next(entry for entry in entries if entry["id"] == "aider")
    check("Ader" in aider["aliases"], "Ader alias must be preserved on aider")
    unresolved = {entry["id"] for entry in entries if entry["evidenceState"] == "unresolved"}
    check({"anti-gravity", "cognite"} <= unresolved, "known unresolved entries drifted")
    claim_ids = {claim["claimId"] for claim in registry["reportedClaims"]}
    check("deepseek-prefix-caching-cost" in claim_ids, "DeepSeek claim must remain recorded")
    check(all(claim["reuseAllowedWithoutVerification"] is False for claim in registry["reportedClaims"]), "claims must not allow unverified reuse")

    check(workflow["workflowId"] == "external-agent-tooling-intake", "workflowId drifted")
    step_ids = [step["id"] for step in workflow["steps"]]
    expected_steps = ["capture", "classify", "overlap", "verify-upstream", "risk-boundary", "proof-boundary", "disposition", "validate"]
    check(step_ids == expected_steps, f"workflow step order drifted: {step_ids}")

    check("skill" not in manifest["entrypoints"], "leaf must not revive skill entrypoint")
    paths = {item["path"] for item in codebase_map["paths"]}
    check(".ai/skills/external-agent-tooling-intake/SKILL.md" not in paths, "historical skill path must stay retired")
    deferred = manifest["salvage"]["deferredSharedRegistration"]
    check(deferred["manifest"]["key"] == "externalAgentToolingManifest", "deferred manifest key drifted")
    check({item["id"] for item in deferred["validators"]["entries"]} == {"external-agent-tooling-python", "external-agent-tooling-powershell"}, "deferred validator ids drifted")
    check(deferred["workflowRegistry"]["action"].startswith("no-change-in-leaf"), "deferred workflow action must stay no-change-in-leaf")
    check(deferred["workflowRegistry"]["skill"] is None, "deferred workflow skill must remain null")

    guide = (ROOT / GUIDE).read_text(encoding="utf-8")
    state = (ROOT / STATE).read_text(encoding="utf-8")
    for token in ("source-only", "capabilityState", "Shared registration is deferred", "Proof ceiling"):
        check(token.lower() in (guide + state).lower(), f"documentation missing token: {token}")

    print("PASS: external agent tooling source-only catalog (45 entries)")


if __name__ == "__main__":
    try:
        main()
    except ContractFailure as exc:
        print(f"FAIL: {exc}")
        raise SystemExit(1) from exc
