#!/usr/bin/env python3
"""Deterministic judgment-closure / outcome-integrity admission.

Structural evidence gate only. It does NOT infer correct architecture or prove
that a model experienced judgment, performed work, or satisfied a user.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "contract.v1.json"
CASE_SCHEMA = "agentswitchboard.judgment-closure-case/v1"
ORDER = ("DESIGN", "PLAN", "IMPLEMENTATION", "DEPLOYMENT")
PROOF_RANK = {
    "DESIGNED": 0, "IMPLEMENTED": 1, "LOCALLY_VALIDATED": 2,
    "CI_VALIDATED": 3, "INTEGRATED": 4, "DEPLOYED": 5,
    "PRODUCTION_OBSERVED": 6,
}
MIN_PROOF = {"DESIGN": 0, "PLAN": 0, "IMPLEMENTATION": 1, "DEPLOYMENT": 5}


def _nonblank(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _items(value: Any) -> list:
    return value if isinstance(value, list) else []


def evaluate(case: dict[str, Any], contract: dict[str, Any] | None = None) -> dict[str, Any]:
    """Admit a deterministic handoff only after bounded decision closure."""
    policy = contract if contract is not None else json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    errors: list[dict[str, str]] = []
    def fail(rule: str, detail: str) -> None:
        errors.append({"ruleId": rule, "detail": detail})

    if not isinstance(case, dict) or case.get("schema") != CASE_SCHEMA:
        fail("JC.INPUT.INTEGRITY", "incorrect or missing judgment-closure case schema")
        return {"schema": "agentswitchboard.judgment-closure-result/v1",
                "admission": "REJECTED", "decisionState": "NEEDS_JUDGMENT",
                "outcomeState": "NOT_PROVEN", "violations": errors}

    req = case.get("request")
    req = req if isinstance(req, dict) else {}
    requested = req.get("requestedStage")
    delivered = req.get("deliveredStage")
    claim = req.get("completionClaim")
    if requested not in ORDER or delivered not in ORDER or claim not in ("COMPLETE", "READY_HANDOFF", "PARTIAL"):
        fail("JC.INPUT.INTEGRITY", "request needs typed requestedStage, deliveredStage and completionClaim")
    if not _nonblank(req.get("userOutcome")) or not _items(req.get("acceptance")):
        fail("JC.INPUT.INTEGRITY", "nonempty user outcome and acceptance criteria required")

    evidence_by_id: dict[str, dict] = {}
    for item in _items(case.get("evidence")):
        if not isinstance(item, dict) or not _nonblank(item.get("id")):
            fail("JC.EVIDENCE.REFERENCE", "each evidence item needs a stable id")
            continue
        eid = item["id"]
        if eid in evidence_by_id:
            fail("JC.EVIDENCE.REFERENCE", f"duplicate evidence id {eid}")
        if not all(_nonblank(item.get(k)) for k in ("source", "revision", "supports", "proofCeiling")):
            fail("JC.EVIDENCE.REFERENCE", f"evidence {eid} lacks source/revision/supports/proof ceiling")
        if item.get("visibility") not in policy["evidence_policy"]["permitted_visibility"]:
            fail("JC.EVIDENCE.REFERENCE", f"evidence {eid} visibility invalid")
        evidence_by_id[eid] = item

    def refs_ok(refs: Any, label: str) -> bool:
        if not isinstance(refs, list) or not refs:
            fail("JC.EVIDENCE.REFERENCE", f"{label} needs evidence references")
            return False
        valid = True
        for ref in refs:
            if ref not in evidence_by_id:
                fail("JC.EVIDENCE.REFERENCE", f"{label} has missing evidence ref {ref}")
                valid = False
        return valid

    decisions_by_id: dict[str, dict] = {}
    unresolved = 0
    conditional = 0
    for d in _items(case.get("decisions")):
        if not isinstance(d, dict) or not _nonblank(d.get("id")):
            fail("JC.DECISION.CLOSURE", "each material decision needs a stable id")
            continue
        did = d["id"]
        if did in decisions_by_id:
            fail("JC.DECISION.CLOSURE", f"duplicate decision id {did}")
        decisions_by_id[did] = d
        refs_ok(d.get("evidenceRefs"), f"decision {did}")
        if not _nonblank(d.get("question")) or not _nonblank(d.get("owner")):
            fail("JC.DECISION.CLOSURE", f"decision {did} needs question and owner")
        state = d.get("state")
        if state == "CLOSED":
            if not all(_nonblank(d.get(k)) for k in ("selected", "rationale")):
                fail("JC.DECISION.CLOSURE", f"closed {did} lacks selected mechanism or rationale")
            if not any(_nonblank(x) for x in _items(d.get("rejectedAlternatives"))):
                fail("JC.DECISION.CLOSURE", f"closed {did} needs a rejected alternative")
        elif state == "CONDITIONAL":
            conditional += 1
            probe = d.get("probe")
            probe = probe if isinstance(probe, dict) else {}
            branches = _items(probe.get("branches"))
            if not _nonblank(probe.get("action")) or not _nonblank(probe.get("falsifier")):
                fail("JC.DECISION.CONDITIONAL_FALSIFIER", f"{did} needs executable probe and falsifier")
            labels = []
            for branch in branches:
                if not isinstance(branch, dict) or not all(_nonblank(branch.get(k)) for k in ("observation", "action", "proof")):
                    fail("JC.DECISION.CONDITIONAL_FALSIFIER", f"{did} branch must map observation to action and proof")
                else:
                    labels.append(branch["observation"])
            if len(set(labels)) < 2 or len(set(labels)) != len(labels):
                fail("JC.DECISION.CONDITIONAL_FALSIFIER", f"{did} needs at least two distinguishable outcomes")
            if not _nonblank(probe.get("fallback")):
                fail("JC.DECISION.CONDITIONAL_FALSIFIER", f"{did} missing bounded failure fallback")
        elif state == "UNRESOLVED":
            unresolved += 1
        else:
            fail("JC.DECISION.CLOSURE", f"decision {did} has invalid state")

    if not decisions_by_id:
        fail("JC.DECISION.CLOSURE", "no material decisions enumerated")

    units = _items(case.get("workUnits"))
    if not units:
        fail("JC.WORK.OWNERSHIP", "no bounded work units")
    for u in units:
        if not isinstance(u, dict):
            fail("JC.WORK.OWNERSHIP", "work unit must be an object")
            continue
        uid = u.get("id", "<missing>")
        if not all(_nonblank(u.get(k)) for k in ("id", "owner", "host", "action", "proofGate")):
            fail("JC.WORK.OWNERSHIP", f"work unit {uid} missing identity/owner/host/action/proof")
        if not _items(u.get("ownedScope")) or not _items(u.get("forbiddenScope")):
            fail("JC.WORK.OWNERSHIP", f"work unit {uid} requires owned and forbidden scope")
        if not _items(u.get("decisionIds")):
            fail("JC.WORK.OWNERSHIP", f"work unit {uid} needs bound decisions")
        for did in _items(u.get("decisionIds")):
            if did not in decisions_by_id:
                fail("JC.DECISION.CLOSURE", f"work unit {uid} depends on absent decision {did}")
        if not isinstance(u.get("canExecuteHere"), bool) or not isinstance(u.get("authorizedHere"), bool) or not isinstance(u.get("executedHere"), bool):
            fail("JC.WORK.OWNERSHIP", f"work unit {uid} needs explicit observed booleans")
        elif (requested in ("IMPLEMENTATION", "DEPLOYMENT")
              and u["canExecuteHere"] and u["authorizedHere"] and not u["executedHere"]):
            fail("JC.DELEGATION.PREMATURE", f"authorized executable work remains here: {uid}")
        if u.get("canExecuteHere") is False and not _nonblank(u.get("placementEvidence")):
            fail("JC.WORK.OWNERSHIP", f"nonlocal work unit {uid} needs placement evidence")
        if u.get("authorizedHere") is False and not _nonblank(u.get("authorityBlocker")):
            fail("JC.WORK.OWNERSHIP", f"non-authorized work unit {uid} needs explicit boundary")

    if unresolved and claim in ("COMPLETE", "READY_HANDOFF"):
        fail("JC.DECISION.CLOSURE", f"{unresolved} unresolved decisions in completion/handoff claim")

    lens_names = set()
    for lens in _items(case.get("reviewLenses")):
        if isinstance(lens, dict) and _nonblank(lens.get("lens")) and _nonblank(lens.get("finding")) and _nonblank(lens.get("disposition")):
            lens_names.add(lens["lens"])
    if requested in ("IMPLEMENTATION", "DEPLOYMENT"):
        required = {"counterfactual", "second_order", "inversion"}
        if not required.issubset(lens_names):
            fail("JC.ADVERSARIAL.LENSES", "missing counterfactual, second-order or inversion challenge")

    if requested in ORDER and delivered in ORDER and claim == "COMPLETE" and ORDER.index(delivered) < ORDER.index(requested):
        fail("JC.OUTCOME.SUBSTITUTION", f"{delivered} delivered while {requested} requested")
    proof = case.get("proof")
    proof = proof if isinstance(proof, dict) else {}
    state = proof.get("state")
    if state not in PROOF_RANK:
        fail("JC.OUTCOME.PROOF", "proof.state is missing or invalid")
    else:
        if delivered in ORDER and PROOF_RANK[state] < MIN_PROOF[delivered]:
            fail("JC.OUTCOME.PROOF", f"{state} cannot prove delivery stage {delivered}")
        if claim == "COMPLETE" and requested in ORDER and PROOF_RANK[state] < MIN_PROOF[requested]:
            fail("JC.OUTCOME.PROOF", f"{state} cannot prove requested outcome {requested}")
    refs_ok(proof.get("evidenceRefs"), "proof")

    valid = not errors
    if errors:
        admission = "REJECTED"
    elif unresolved:
        admission = "PARTIAL_ONLY"
    else:
        admission = "ADMITTED"
    outcome = ("CLAIMED_COMPLETE_NOT_INDEPENDENTLY_VERIFIED" if valid and claim == "COMPLETE"
               else "PARTIAL_DELIVERY" if valid else "NOT_PROVEN")
    return {
        "schema": "agentswitchboard.judgment-closure-result/v1",
        "admission": admission,
        "decisionState": "NEEDS_JUDGMENT" if unresolved or errors else ("CONDITIONAL_READY" if conditional else "CLOSED"),
        "outcomeState": outcome,
        "decisionsEnumerated": len(decisions_by_id),
        "conditionalDecisions": conditional,
        "unresolvedDecisions": unresolved,
        "violations": errors,
        "proofCeiling": "STRUCTURAL_ADMISSION_ONLY; NO LIVE/SEMANTIC/OUTCOME VERIFICATION",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="case JSON path, or - for stdin")
    parser.add_argument("--output", help="write result JSON to path")
    args = parser.parse_args()
    try:
        raw = sys.stdin.read() if args.input == "-" else Path(args.input).read_text(encoding="utf-8")
        value = json.loads(raw)
        result = evaluate(value)
        serialized = json.dumps(result, sort_keys=True, indent=2) + "\n"
        if args.output:
            Path(args.output).write_text(serialized, encoding="utf-8")
        else:
            sys.stdout.write(serialized)
        return 0 if result["admission"] != "REJECTED" else 2
    except (OSError, json.JSONDecodeError, ValueError, TypeError, KeyError) as exc:
        print(f"JUDGMENT_CLOSURE_INPUT_ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
