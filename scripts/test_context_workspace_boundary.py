#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_json(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))


def require(condition: bool, message: str):
    if not condition:
        raise AssertionError(message)


contract = load_json(".ai/harness/context-workspace-boundary.contract.json")
knowledge = load_json(".ai/harness/harness-doctrine.policy.json")
routes = load_json("tooling/harness/context/context.routes.json")
ledger = load_json(".ai/harness/repository-work-ledger.policy.json")
doc = (ROOT / "docs/governance/context-workspace-boundary.md").read_text(encoding="utf-8")
harness = (ROOT / "HARNESS.md").read_text(encoding="utf-8")

require(contract["schemaVersion"] == 1, "schemaVersion must remain 1")
require(contract["contractId"] == "agentswitchboard.context-workspace-boundary.v1", "contract id changed")
require(contract["contractVersion"] == "1.0.0", "contract version changed")
require(contract["canonicalRepository"] == "EndeavorEverlasting/AgentSwitchboard", "canonical owner changed")
require(contract["composesWith"]["repositoryKnowledgeReuse"] == ".ai/harness/harness-doctrine.policy.json#knowledgeReuse", "knowledge-reuse owner duplicated")
require(contract["composesWith"]["progressiveDisclosure"] == "tooling/harness/context/context.routes.json", "context router owner duplicated")
require(contract["composesWith"]["workState"] == ".ai/harness/repository-work-ledger.policy.json", "work-state owner duplicated")

for rule in (
    "singleAuthorityPerConcern",
    "splitRepositoriesRequireExplicitMapping",
    "authoredStatusCannotOverrideDerivedImplementationEvidence",
    "recencyAloneCannotResolveCrossRepositoryConflict",
    "operatorAndAgentViewsMustProjectFromSameCanonicalGraph",
    "agentViewMayBeMoreVerboseButNotMoreAuthoritative",
    "sessionStartHydrationMustBeBoundedAndDeterministicWhenPractical",
    "sessionStartHydrationCannotOverrideGovernanceOrInjectSecrets",
    "lessonsRequireProvenanceScopeAndOwner",
    "lessonsCannotAutoRewriteCanonicalSkillsOrPolicy",
):
    require(contract["rules"].get(rule) is True, f"required rule missing: {rule}")

for field in (
    "adoptionManifest",
    "repositoryLocalValidator",
    "pairedRepositoryIdentity",
    "authorityMap",
    "staleReferenceHandling",
    "consumerOwnsItsTests",
):
    require(contract["consumerRequirements"].get(field) is True, f"consumer requirement missing: {field}")

require(contract["consumerRequirements"]["remoteValidatorExecutionForbidden"] is True, "consumer validation must stay local")
require(contract["consumerRequirements"]["localRulesMayWeaken"] is False, "consumer cannot weaken portable floor")
require("project lessons" in contract["roles"]["contextAuthority"]["owns"], "context lessons ownership missing")
require("runtime works" in contract["roles"]["contextAuthority"]["mustNotClaim"], "context proof ceiling weakened")
require("source code" in contract["roles"]["implementationAuthority"]["owns"], "implementation source ownership missing")
require("canonical project intent" in contract["roles"]["implementationAuthority"]["mustNotDuplicate"], "intent duplication guard missing")
require("same registered artifacts" in contract["projectionContract"]["sourceRule"], "operator/agent views must share one graph")

require(knowledge["knowledgeReuse"]["repositoryKnowledgeIsCompiledState"] is True, "anti-rediscovery dependency missing")
require(routes["routerId"] == "agentswitchboard.progressive-disclosure.v1", "progressive disclosure dependency changed")
require(ledger["contractId"] == "agentswitchboard.repository-work-ledger.v1", "work-ledger dependency changed")

for token in (
    "Derived state beats authored optimism",
    "Operator and agent projections",
    "Session-start hydration",
    "Lessons and feedback memory",
    "promoted into universal AgentSwitchboard law",
    "consumer-local validator",
):
    require(token.lower() in doc.lower(), f"doctrine token missing: {token}")

require(".ai/harness/context-workspace-boundary.contract.json" in harness, "HARNESS.md must route split context/implementation work to the contract")
require("docs/governance/context-workspace-boundary.md" in harness, "HARNESS.md must route to the human doctrine")
require("docs.google.com/" not in doc.lower(), "tracked doctrine must not embed private Drive links")
print("PASS: context workspace boundary contract")
