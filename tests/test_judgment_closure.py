"""Adversarial structural tests: prompt length and checklist presence never prove outcomes."""
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVALUATOR_PATH = ROOT / "tooling/harness/operational/judgment-closure/evaluate.py"
spec = importlib.util.spec_from_file_location("judgment_closure", EVALUATOR_PATH)
assert spec and spec.loader
jc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jc)


def sample(requested="IMPLEMENTATION", delivered="IMPLEMENTATION", claim="COMPLETE"):
    return {
        "schema": jc.CASE_SCHEMA,
        "request": {
            "userOutcome": "Working agent scheduler continuously performs authorized repository engineering",
            "requestedStage": requested,
            "deliveredStage": delivered,
            "completionClaim": claim,
            "acceptance": ["bounded agent run produces a stored receipt"],
        },
        "evidence": [
            {"id": "E1", "source": "repo:contracts/automation",
             "revision": "sha256:test", "supports": "scheduler architecture choice",
             "proofCeiling": "SOURCE_INSPECTED", "visibility": "PUBLIC_TRACKED"},
            {"id": "E2", "source": "test:agent-live-execution",
             "revision": "receipt:test", "supports": "implementation behavior",
             "proofCeiling": "SYNTHETIC_FIXTURE", "visibility": "SANITIZED_OPAQUE"},
        ],
        "decisions": [
            {"id": "D1", "question": "How will scheduled work be claimed?",
             "owner": "Work Graph adapter", "state": "CLOSED",
             "selected": "Reuse durable lease protocol",
             "rejectedAlternatives": ["create independent lease database"],
             "rationale": "Existing shared CAS protocol avoids duplicate mutation",
             "evidenceRefs": ["E1"]},
        ],
        "workUnits": [
            {"id": "W1", "owner": "runtime adapter", "host": "CURRENT_CHAT_RUNTIME",
             "action": "Implement bound adapter using existing lease contract",
             "ownedScope": ["tooling/runtime/scheduler/**"],
             "forbiddenScope": ["provider-credentials/**"],
             "decisionIds": ["D1"], "proofGate": "focused unit suite",
             "canExecuteHere": True, "authorizedHere": True, "executedHere": True,
             "executionEvidenceRefs": ["E2"]},
        ],
        "reviewLenses": [
            {"lens": lens, "finding": "Test whether recurrence hides unresolved failures",
             "disposition": "Add negative test"}
            for lens in ("counterfactual", "second_order", "inversion", "authority_and_privacy", "opportunity_cost")
        ],
        "proof": {"state": "IMPLEMENTED", "evidenceRefs": ["E2"]},
    }


class JudgmentClosureTests(unittest.TestCase):
    def assert_rule(self, packet, rule):
        result = jc.evaluate(packet)
        self.assertEqual(result["admission"], "REJECTED", result)
        self.assertIn(rule, {r["ruleId"] for r in result["violations"]})
        return result

    def test_completed_decisions_with_declared_implementation_proof_admit_structurally(self):
        result = jc.evaluate(sample())
        self.assertEqual(result["admission"], "ADMITTED", result)
        self.assertEqual(result["decisionState"], "CLOSED")
        self.assertEqual(result["outcomeState"], "CLAIMED_COMPLETE_NOT_INDEPENDENTLY_VERIFIED")
        self.assertIn("NO LIVE", result["proofCeiling"])

    def test_plan_substituted_for_implementation_fails_even_with_long_handoff(self):
        packet = sample(delivered="PLAN")
        packet["request"]["acceptance"] = ["a thousand words of sophisticated design"]
        self.assert_rule(packet, "JC.OUTCOME.SUBSTITUTION")

    def test_premature_delegation_fails_even_with_all_architecture_decisions_closed(self):
        packet = sample(delivered="PLAN", claim="PARTIAL")
        packet["workUnits"][0]["executedHere"] = False
        self.assert_rule(packet, "JC.DELEGATION.PREMATURE")

    def test_unresolved_choice_invalidates_ready_handoff(self):
        packet = sample(claim="READY_HANDOFF")
        packet["decisions"][0]["state"] = "UNRESOLVED"
        self.assert_rule(packet, "JC.DECISION.CLOSURE")

    def test_partial_only_can_carry_real_unresolved_decision_but_cannot_claim_ready(self):
        packet = sample(requested="DESIGN", delivered="DESIGN", claim="PARTIAL")
        packet["proof"]["state"] = "DESIGNED"
        packet["decisions"][0]["state"] = "UNRESOLVED"
        self.assertEqual(jc.evaluate(packet)["admission"], "PARTIAL_ONLY")

    def test_conditional_probe_with_two_measurable_branches_is_accepted(self):
        packet = sample()
        packet["decisions"][0]["state"] = "CONDITIONAL"
        packet["decisions"][0]["probe"] = {
            "action": "run canonical adapter capabilities --json",
            "falsifier": "required mutation interface absent",
            "branches": [
                {"observation": "READY", "action": "bind live adapter", "proof": "capabilities receipt"},
                {"observation": "UNAVAILABLE", "action": "emit BLOCKED capability receipt", "proof": "error code"},
            ],
            "fallback": "fail closed and preserve work",
        }
        result = jc.evaluate(packet)
        self.assertEqual(result["admission"], "ADMITTED", result)
        self.assertEqual(result["decisionState"], "CONDITIONAL_READY")

    def test_conditional_without_falsifier_or_fallback_is_rejected(self):
        packet = sample()
        packet["decisions"][0]["state"] = "CONDITIONAL"
        packet["decisions"][0]["probe"] = {"action": "check adapter", "branches": [
            {"observation": "YES", "action": "run", "proof": "test"},
            {"observation": "NO", "action": "block", "proof": "test"},
        ]}
        self.assert_rule(packet, "JC.DECISION.CONDITIONAL_FALSIFIER")

    def test_missing_decision_reference_rejected(self):
        packet = sample()
        packet["workUnits"][0]["decisionIds"] = ["D-UNKNOWN"]
        self.assert_rule(packet, "JC.DECISION.CLOSURE")

    def test_missing_source_evidence_rejected(self):
        packet = sample()
        packet["decisions"][0]["evidenceRefs"] = ["invented-source"]
        self.assert_rule(packet, "JC.EVIDENCE.REFERENCE")

    def test_missing_proof_rejects_completion(self):
        packet = sample()
        packet["proof"]["state"] = "DESIGNED"
        self.assert_rule(packet, "JC.OUTCOME.PROOF")

    def test_execution_claim_without_receipt_reference_is_rejected(self):
        packet = sample()
        packet["workUnits"][0].pop("executionEvidenceRefs")
        self.assert_rule(packet, "JC.EVIDENCE.REFERENCE")

    def test_executable_unperformed_current_runtime_work_rejected(self):
        packet = sample()
        packet["workUnits"][0]["executedHere"] = False
        self.assert_rule(packet, "JC.DELEGATION.PREMATURE")

    def test_unavailable_runtime_requires_explanation_not_guess(self):
        packet = sample(delivered="PLAN", claim="PARTIAL")
        packet["workUnits"][0].update(canExecuteHere=False, executedHere=False)
        self.assert_rule(packet, "JC.WORK.OWNERSHIP")
        packet["workUnits"][0]["placementEvidence"] = "host lacks write API; provider readback required"
        result = jc.evaluate(packet)
        self.assertEqual(result["admission"], "ADMITTED", result)
        self.assertEqual(result["outcomeState"], "PARTIAL_DELIVERY")

    def test_unauthorized_work_requires_explicit_boundary(self):
        packet = sample(delivered="PLAN", claim="PARTIAL")
        packet["workUnits"][0].update(authorizedHere=False, executedHere=False)
        self.assert_rule(packet, "JC.WORK.OWNERSHIP")
        packet["workUnits"][0]["authorityBlocker"] = "operator approval for live prod mutation"
        self.assertEqual(jc.evaluate(packet)["admission"], "ADMITTED")

    def test_required_creative_challenge_lenses_enforced_not_assumed(self):
        packet = sample()
        packet["reviewLenses"] = []
        self.assert_rule(packet, "JC.ADVERSARIAL.LENSES")

    def test_public_contract_does_not_authorize_mutation(self):
        contract = json.loads(jc.CONTRACT_PATH.read_text(encoding="utf-8"))
        self.assertIn("cannot authorize mutation", contract["precedence"].lower())
        self.assertIn("never", contract["owner"]["role"].lower())
        self.assertIn("No validator", contract["proof_ceiling"])

    def test_cli_stdin_fail_closed_and_valid_file_roundtrip(self):
        import subprocess
        valid = sample()
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "case.json"
            path.write_text(json.dumps(valid), encoding="utf-8")
            proc = subprocess.run(["python", str(EVALUATOR_PATH), "--input", str(path)],
                                  text=True, capture_output=True, check=False)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(json.loads(proc.stdout)["admission"], "ADMITTED")
            valid["request"]["deliveredStage"] = "PLAN"
            path.write_text(json.dumps(valid), encoding="utf-8")
            proc = subprocess.run(["python", str(EVALUATOR_PATH), "--input", str(path)],
                                  text=True, capture_output=True, check=False)
            self.assertEqual(proc.returncode, 2)
            self.assertEqual(json.loads(proc.stdout)["admission"], "REJECTED")


if __name__ == "__main__":
    unittest.main()
