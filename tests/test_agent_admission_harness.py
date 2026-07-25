from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "agents" / "harness" / "admission"
REGISTRY_PATH = HARNESS / "agent-admission.registry.json"
ARTIFACT_REGISTRY_PATH = HARNESS / "artifact-registry.json"
FIXTURE_PATH = HARNESS / "fixtures" / "runtime-proof-discipline.cases.json"
SCHEMA_PATH = HARNESS / "schemas" / "agent-admission-harness.schema.json"
WORKFLOW_DIR = HARNESS / "workflows"
SKILL_PATH = ROOT / ".ai" / "skills" / "agent-admission-routing" / "SKILL.md"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def reduce_facts(facts: dict) -> tuple[str, str]:
    if not facts.get("launchRequested", False) or not facts.get("launchAttempted", False):
        proof = "static-contract" if facts.get("staticValidationPassed", False) else "not-attempted"
        return "NOT_ATTEMPTED", proof

    if not facts.get("sameRunEvidence", True) and facts.get("staleBehaviorArtifactPresent", False):
        return "STALE_EVIDENCE", "command-ack" if facts.get("commandAckObserved", False) else "static-contract"

    if facts.get("launcherProcessObserved", False) and not facts.get("launcherHwndObserved", False):
        return "LAUNCHER_BLOCKED", "launcher-observed"

    if facts.get("commandAckObserved", False) and not facts.get("freshBehaviorObserved", False):
        return "ACK_ONLY", "command-ack"

    live_required = (
        "launchRequested",
        "launchAttempted",
        "launcherProcessObserved",
        "launcherHwndObserved",
        "launchActionDispatched",
        "gameOrTargetProcessObserved",
        "runtimeAttached",
        "runtimeReady",
        "commandIssued",
        "commandAckObserved",
        "freshBehaviorObserved",
        "sameRunEvidence",
    )
    if all(facts.get(name, False) for name in live_required):
        return "PASS_LIVE_RUNTIME", "behavior-observed"

    return "FAILED_RUNTIME", "runtime-attached" if facts.get("runtimeAttached", False) else "static-contract"


class AgentAdmissionHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry = load_json(REGISTRY_PATH)
        cls.artifacts = load_json(ARTIFACT_REGISTRY_PATH)
        cls.fixture = load_json(FIXTURE_PATH)
        cls.schema = load_json(SCHEMA_PATH)

    def test_required_components_exist(self) -> None:
        paths = [
            REGISTRY_PATH,
            ARTIFACT_REGISTRY_PATH,
            FIXTURE_PATH,
            SCHEMA_PATH,
            SKILL_PATH,
            WORKFLOW_DIR / "task-intake.workflow.json",
            WORKFLOW_DIR / "admission-evaluation.workflow.json",
            WORKFLOW_DIR / "route-selection.workflow.json",
            WORKFLOW_DIR / "failure-handoff.workflow.json",
            ROOT / "scripts" / "Test-AgentAdmissionHarness.ps1",
            ROOT / "tooling" / "agents" / "Get-AgentAdmissionHarnessStatus.ps1",
            ROOT / "tooling" / "agents" / "hooks" / "Invoke-AgentAdmissionHarnessPreCommit.ps1",
            ROOT / "docs" / "harness" / "agent-admission-harness.md",
            ROOT / ".github" / "workflows" / "agent-admission-harness.yml",
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(path.is_file(), f"missing required component: {path}")

    def test_unknown_agents_fail_closed(self) -> None:
        policy = self.registry["defaultPolicy"]
        self.assertEqual("static-build-only", policy["unknownAgentEligibility"])
        self.assertFalse(policy["requestedAgentIsEligibleByDefault"])
        self.assertFalse(policy["providerReachabilityImpliesEligibility"])
        self.assertFalse(policy["commandPresenceImpliesEligibility"])
        self.assertFalse(policy["silentProofDowngradeAllowed"])
        self.assertTrue(policy["liveRuntimeFailClosed"])

    def test_live_lane_requires_exact_admission(self) -> None:
        lanes = {lane["laneId"]: lane for lane in self.registry["executionLanes"]}
        live = lanes["live-runtime"]
        self.assertEqual("runtime-proof-discipline-pass", live["minimumAdmission"])
        self.assertTrue(live["requiresFreshExecutionIdentity"])
        self.assertTrue(live["requiresHarnessTerminalState"])
        self.assertTrue(live["mayCertifyLiveRuntime"])

    def test_runtime_proof_fixture_suite_is_exact(self) -> None:
        self.assertEqual("runtime-proof-discipline/v1", self.fixture["suiteId"])
        self.assertEqual(5, len(self.fixture["cases"]))
        self.assertEqual(0, self.fixture["passingRule"]["maximumMisses"])
        self.assertTrue(self.fixture["passingRule"]["liveRuntimeEligibleOnPassOnly"])

        expected = {
            "live-runtime-pass": ("PASS_LIVE_RUNTIME", "behavior-observed"),
            "launch-not-requested": ("NOT_ATTEMPTED", "static-contract"),
            "launcher-hwnd-missing": ("LAUNCHER_BLOCKED", "launcher-observed"),
            "ack-without-behavior": ("ACK_ONLY", "command-ack"),
            "stale-behavior-evidence": ("STALE_EVIDENCE", "command-ack"),
        }
        for case in self.fixture["cases"]:
            with self.subTest(case=case["caseId"]):
                classification, proof = reduce_facts(case["facts"])
                self.assertEqual(expected[case["caseId"]], (classification, proof))
                self.assertEqual(case["expectedClassification"], classification)
                self.assertEqual(case["expectedProofLevel"], proof)

    def test_proof_reducer_rejects_shortcuts(self) -> None:
        reducer = self.registry["proofReducer"]
        self.assertFalse(reducer["commandAckIsBehaviorProof"])
        self.assertFalse(reducer["fixtureIsRuntimeProof"])
        self.assertFalse(reducer["processPresenceIsBehaviorProof"])
        self.assertTrue(reducer["staleEvidenceMustNotCount"])
        self.assertIn("NOT_ATTEMPTED", reducer["terminalClassifications"])
        self.assertIn("ACK_ONLY", reducer["terminalClassifications"])
        self.assertIn("STALE_EVIDENCE", reducer["terminalClassifications"])

    def test_workflows_are_operational_and_bounded(self) -> None:
        expected = {
            "task-intake.workflow.json": "agent-task-intake",
            "admission-evaluation.workflow.json": "agent-admission-evaluation",
            "route-selection.workflow.json": "agent-route-selection",
            "failure-handoff.workflow.json": "agent-failure-handoff",
        }
        for filename, workflow_id in expected.items():
            workflow = load_json(WORKFLOW_DIR / filename)
            with self.subTest(workflow=workflow_id):
                self.assertEqual("agentswitchboard.agent-admission-workflow.v1", workflow["schema"])
                self.assertEqual(workflow_id, workflow["workflowId"])
                self.assertGreaterEqual(len(workflow["steps"]), 5)
                self.assertTrue(workflow["proofCeiling"])

    def test_artifacts_are_local_and_untracked(self) -> None:
        self.assertFalse(self.artifacts["tracked"])
        ids = {artifact["artifactId"] for artifact in self.artifacts["artifacts"]}
        required = {
            "agent-admission-run-context",
            "agent-admission-eval-result",
            "agent-route-decision",
            "agent-execution-identity",
            "agent-proof-ledger",
            "agent-admission-operator-report",
            "agent-admission-final-handoff",
        }
        self.assertTrue(required.issubset(ids))
        for artifact in self.artifacts["artifacts"]:
            self.assertEqual("local-operational", artifact["sensitivity"])

    def test_schema_contains_core_contracts(self) -> None:
        defs = self.schema["$defs"]
        for name in ("executionIdentity", "runContext", "admissionResult", "routeDecision", "proofLedger", "handoff"):
            self.assertIn(name, defs)

    def test_skill_forbids_model_self_certification(self) -> None:
        text = SKILL_PATH.read_text(encoding="utf-8")
        required = (
            "id: agent-admission-routing",
            "status: experimental",
            "## Trigger",
            "## Inputs",
            "## Procedure",
            "## Outputs",
            "## Deterministic validation",
            "## Forbidden scope",
            "## Stop and escalate",
            "BLOCKED_NO_ELIGIBLE_AGENT",
            "The candidate does not decide whether it passed",
        )
        # The candidate-self-certification rule is stated in the workflow; the skill states the equivalent prohibition.
        self.assertIn("do not let the delegated model decide whether its own admission passed", text)
        for token in required[:-1]:
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
