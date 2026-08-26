#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_json(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))


def require(condition: bool, message: str):
    if not condition:
        raise AssertionError(message)


def require_object(value, keys, label):
    require(isinstance(value, dict), f"{label} must be an object")
    require(set(value) == set(keys), f"{label} keys changed")


def require_string_list(value, label):
    require(isinstance(value, list) and value, f"{label} must be a non-empty array")
    require(all(isinstance(item, str) and item.strip() for item in value), f"{label} must contain non-empty strings")
    require(len(value) == len(set(value)), f"{label} must not contain duplicates")


contract = load_json(".ai/harness/context-workspace-boundary.contract.json")
schema = load_json(".ai/harness/schemas/context-workspace-boundary.schema.json")
knowledge = load_json(".ai/harness/harness-doctrine.policy.json")
routes = load_json("tooling/harness/context/context.routes.json")
ledger = load_json(".ai/harness/repository-work-ledger.policy.json")
doc = (ROOT / "docs/governance/context-workspace-boundary.md").read_text(encoding="utf-8")
harness = (ROOT / "HARNESS.md").read_text(encoding="utf-8")

TOP_KEYS = {
    "schemaVersion", "contractId", "contractVersion", "canonicalRepository", "purpose",
    "owns", "composesWith", "doesNotOwn", "roles", "rules", "recommendedContextArtifacts",
    "projectionContract", "consumerRequirements", "proofCeiling",
}
require_object(contract, TOP_KEYS, "contract")
require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema draft changed")
require(schema.get("$id") == "https://agentswitchboard.local/schemas/context-workspace-boundary.schema.json", "schema id changed")
require(set(schema.get("required", [])) == TOP_KEYS, "schema required fields changed")
require(schema.get("additionalProperties") is False, "schema must reject unknown top-level fields")

require(contract["schemaVersion"] == 1, "schemaVersion must remain 1")
require(contract["contractId"] == "agentswitchboard.context-workspace-boundary.v1", "contract id changed")
require(contract["contractVersion"] == "1.0.0", "contract version changed")
require(contract["canonicalRepository"] == "EndeavorEverlasting/AgentSwitchboard", "canonical owner changed")
require(isinstance(contract["purpose"], str) and contract["purpose"].strip(), "purpose missing")
require(isinstance(contract["proofCeiling"], str) and contract["proofCeiling"].strip(), "proof ceiling missing")
for field in ("owns", "doesNotOwn", "recommendedContextArtifacts"):
    require_string_list(contract[field], field)

require_object(contract["composesWith"], {"repositoryKnowledgeReuse", "progressiveDisclosure", "workState"}, "composesWith")
require(contract["composesWith"]["repositoryKnowledgeReuse"] == ".ai/harness/harness-doctrine.policy.json#knowledgeReuse", "knowledge-reuse owner duplicated")
require(contract["composesWith"]["progressiveDisclosure"] == "tooling/harness/context/context.routes.json", "context router owner duplicated")
require(contract["composesWith"]["workState"] == ".ai/harness/repository-work-ledger.policy.json", "work-state owner duplicated")

require_object(contract["roles"], {"contextAuthority", "implementationAuthority"}, "roles")
require_object(contract["roles"]["contextAuthority"], {"owns", "mustNotClaim"}, "roles.contextAuthority")
require_object(contract["roles"]["implementationAuthority"], {"owns", "mustNotDuplicate"}, "roles.implementationAuthority")
for field in ("owns", "mustNotClaim"):
    require_string_list(contract["roles"]["contextAuthority"][field], f"roles.contextAuthority.{field}")
for field in ("owns", "mustNotDuplicate"):
    require_string_list(contract["roles"]["implementationAuthority"][field], f"roles.implementationAuthority.{field}")

RULE_KEYS = {
    "singleAuthorityPerConcern", "sameRepositoryMayHoldBothRoles", "splitRepositoriesRequireExplicitMapping",
    "authoredStatusCannotOverrideDerivedImplementationEvidence", "recencyAloneCannotResolveCrossRepositoryConflict",
    "operatorAndAgentViewsMustProjectFromSameCanonicalGraph", "agentViewMayBeMoreVerboseButNotMoreAuthoritative",
    "sessionStartHydrationMustBeBoundedAndDeterministicWhenPractical", "sessionStartHydrationCannotOverrideGovernanceOrInjectSecrets",
    "lessonsRequireProvenanceScopeAndOwner", "lessonsCannotAutoRewriteCanonicalSkillsOrPolicy",
}
require_object(contract["rules"], RULE_KEYS, "rules")
require(all(isinstance(contract["rules"][key], bool) for key in RULE_KEYS), "rules must be booleans")
for key in RULE_KEYS - {"sameRepositoryMayHoldBothRoles"}:
    require(contract["rules"][key] is True, f"required rule disabled: {key}")

require_object(contract["projectionContract"], {"operatorMode", "agentMode", "sourceRule"}, "projectionContract")
require(all(isinstance(value, str) and value.strip() for value in contract["projectionContract"].values()), "projection values must be non-empty strings")

CONSUMER_KEYS = {
    "adoptionManifest", "repositoryLocalValidator", "pairedRepositoryIdentity", "authorityMap",
    "staleReferenceHandling", "consumerOwnsItsTests", "remoteValidatorExecutionForbidden",
    "localRulesMayStrengthen", "localRulesMayWeaken",
}
require_object(contract["consumerRequirements"], CONSUMER_KEYS, "consumerRequirements")
require(all(isinstance(contract["consumerRequirements"][key], bool) for key in CONSUMER_KEYS), "consumer requirements must be booleans")
for key in CONSUMER_KEYS - {"localRulesMayWeaken"}:
    require(contract["consumerRequirements"][key] is True, f"consumer requirement disabled: {key}")
require(contract["consumerRequirements"]["localRulesMayWeaken"] is False, "consumer cannot weaken portable floor")

require("project lessons" in contract["roles"]["contextAuthority"]["owns"], "context lessons ownership missing")
require("runtime works" in contract["roles"]["contextAuthority"]["mustNotClaim"], "context proof ceiling weakened")
require("source code" in contract["roles"]["implementationAuthority"]["owns"], "implementation source ownership missing")
require("canonical project intent" in contract["roles"]["implementationAuthority"]["mustNotDuplicate"], "intent duplication guard missing")
require("same registered artifacts" in contract["projectionContract"]["sourceRule"], "operator/agent views must share one graph")

# Pin compatibility with the existing local owners that this contract composes with.
require(knowledge.get("schemaVersion") == 1, "harness doctrine schema changed")
require(knowledge.get("policyId") == "agentswitchboard.harness-doctrine.v1", "harness doctrine identity changed")
reuse = knowledge.get("knowledgeReuse")
require(isinstance(reuse, dict), "knowledgeReuse contract missing")
for field in (
    "repositoryKnowledgeIsCompiledState", "requireLocalCanonicalSearchBeforeInvention",
    "requireUnresolvedGapBeforeExternalResearch", "externalResearchCannotOverrideRepositoryAuthority",
    "preferDeterministicHydrationForRepeatedKnownState",
):
    require(reuse.get(field) is True, f"knowledgeReuse compatibility field changed: {field}")
require_string_list(reuse.get("discoveryOrder"), "knowledgeReuse.discoveryOrder")
require_string_list(reuse.get("requiredEvidenceFields"), "knowledgeReuse.requiredEvidenceFields")

require(routes.get("schemaVersion") == 1, "progressive disclosure schema changed")
require(routes.get("routerId") == "agentswitchboard.progressive-disclosure.v1", "progressive disclosure identity changed")
require(routes.get("orientation", {}).get("defaultLoad") == ["HARNESS.md"], "progressive disclosure orientation changed")
require(isinstance(routes.get("domains"), list) and routes["domains"], "progressive disclosure domains missing")
require(routes.get("validation", {}).get("command") == "Test-ProgressiveDisclosureHarness.cmd", "progressive disclosure validator changed")

require(ledger.get("schemaVersion") == 1, "repository-work-ledger schema changed")
require(ledger.get("contractId") == "agentswitchboard.repository-work-ledger.v1", "repository-work-ledger identity changed")
require(ledger.get("contractVersion") == "1.0.0", "repository-work-ledger version changed")
require_string_list(ledger.get("statusVocabulary"), "repository-work-ledger.statusVocabulary")
require_string_list(ledger.get("requiredFields"), "repository-work-ledger.requiredFields")
require(ledger.get("consumerRequirements", {}).get("repositoryLocalValidator") is True, "repository-work-ledger local-validator requirement changed")
require(ledger.get("consumerRequirements", {}).get("remoteValidatorExecutionForbidden") is True, "repository-work-ledger validation boundary changed")
require(isinstance(ledger.get("proofCeiling"), str) and ledger["proofCeiling"].strip(), "repository-work-ledger proof ceiling missing")

for token in (
    "Derived state beats authored optimism", "Operator and agent projections", "Session-start hydration",
    "Lessons and feedback memory", "promoted into universal AgentSwitchboard law", "consumer-local validator",
):
    require(token.lower() in doc.lower(), f"doctrine token missing: {token}")

require(".ai/harness/context-workspace-boundary.contract.json" in harness, "HARNESS.md must route to the contract")
require("docs/governance/context-workspace-boundary.md" in harness, "HARNESS.md must route to the doctrine")
for blocked_host in ("docs.google.com", "drive.google.com", "docs.googleusercontent.com", "drive.googleusercontent.com", "drive.usercontent.google.com"):
    require(blocked_host not in doc.lower(), f"tracked doctrine contains a private/source-specific Drive host: {blocked_host}")
require("google.com/url?" not in doc.lower(), "tracked doctrine contains a Google redirect URL")
print("PASS: context workspace boundary contract")
