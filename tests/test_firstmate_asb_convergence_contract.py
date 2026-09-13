#!/usr/bin/env python3
"""Dependency-free FirstMate ↔ AgentSwitchboard convergence contract tests."""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "tooling" / "firstmate" / "harness" / "convergence-contract.json"
UPSTREAM_PIN = ROOT / "tooling" / "firstmate" / "harness" / "upstream-pin.json"
DOCS = ROOT / "docs" / "harness" / "firstmate-asb-convergence.md"
EXPECTED_SHA = "833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409"
SECRET_PATTERNS = [
    re.compile(r"ghp_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"BEGIN (?:RSA|OPENSSH) PRIVATE KEY"),
    re.compile(r"(?i)api[_-]?key\s*[:=]\s*['\"][^'\"]+['\"]"),
    re.compile(r"(?i)password\s*[:=]\s*['\"][^'\"]+['\"]"),
    re.compile(r"(?i)secret\s*[:=]\s*['\"][^'\"]+['\"]"),
    re.compile(r"/Users/[A-Za-z0-9._-]+"),
    re.compile(r"/home/[A-Za-z0-9._-]+"),
    re.compile(r"[A-Za-z]:\\Users\\"),
]


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def joined_text(*paths: Path) -> str:
    return "\n".join(path.read_text(encoding="utf-8-sig") for path in paths)


class FirstMateAsbConvergenceContractTests(unittest.TestCase):
    def test_owned_files_exist_and_json_parses(self) -> None:
        self.assertTrue(CONTRACT.is_file(), "missing convergence-contract.json")
        self.assertTrue(UPSTREAM_PIN.is_file(), "missing upstream-pin.json")
        self.assertTrue(DOCS.is_file(), "missing firstmate-asb-convergence.md")
        contract = load_json(CONTRACT)
        pin = load_json(UPSTREAM_PIN)
        self.assertEqual(1, contract["schemaVersion"])
        self.assertEqual(
            "agentswitchboard.firstmate-asb-convergence.v1",
            contract["contractId"],
        )
        self.assertEqual(1, pin["schemaVersion"])
        self.assertEqual("agentswitchboard.firstmate-upstream-pin.v1", pin["pinId"])

    def test_role_boundaries(self) -> None:
        roles = load_json(CONTRACT)["roles"]
        self.assertIn("control plane", roles["AgentSwitchboard"].lower())
        self.assertIn("crew chief", roles["FirstMate"].lower())
        self.assertIn("worker", roles["codingAgents"].lower())
        self.assertIn("session", roles["tmux"].lower())

    def test_runtime_is_wsl_ubuntu_and_native_windows_out_of_scope(self) -> None:
        runtime = load_json(CONTRACT)["runtime"]
        pin = load_json(UPSTREAM_PIN)
        self.assertEqual("WSL/Ubuntu", runtime["target"])
        self.assertEqual("out_of_scope", runtime["nativeWindows"])
        self.assertEqual("bridge_only", runtime["windowsHostRole"])
        self.assertEqual("tmux", runtime["referenceSessionBackend"])
        self.assertTrue(pin["outOfScope"]["nativeWindows"])
        self.assertEqual("WSL/Ubuntu", pin["platforms"]["agentswitchboardTarget"])
        docs = DOCS.read_text(encoding="utf-8-sig")
        self.assertIn("WSL/Ubuntu", docs)
        self.assertIn("bridge only", docs.lower())
        self.assertIn("out of scope", docs.lower())

    def test_upstream_pin_matches_audited_commit_and_rebase_note(self) -> None:
        contract = load_json(CONTRACT)
        pin = load_json(UPSTREAM_PIN)
        upstream = contract["upstream"]
        self.assertEqual("kunchenguid/firstmate", upstream["repository"])
        self.assertEqual(EXPECTED_SHA, upstream["auditedCommit"])
        self.assertRegex(upstream["auditedCommit"], r"^[0-9a-f]{40}$")
        self.assertTrue(upstream["rebaseRequiredBeforePr96StackMerge"])
        self.assertEqual(pin["repository"], upstream["repository"])
        self.assertEqual(pin["commit"], EXPECTED_SHA)
        self.assertFalse(pin["vendor"])
        self.assertTrue(pin["rebaseRequiredBeforePr96StackMerge"])
        self.assertIn("rebase", upstream["rebaseNote"].lower())

    def test_first_safe_sprint_local_only_yolo_false_no_cred_or_deps(self) -> None:
        sprint = load_json(CONTRACT)["firstSafeSprint"]
        self.assertEqual("local-only", sprint["projectDeliveryMode"])
        self.assertIs(sprint["yoloEnabled"], False)
        self.assertIs(sprint["credentialMutation"], False)
        self.assertIs(sprint["dependencyInstallationByAsbHarness"], False)
        self.assertIs(sprint["remoteWrites"], False)

    def test_herdr_deferred_and_excluded_from_windows_admin_box(self) -> None:
        herdr = load_json(CONTRACT)["herdr"]
        self.assertEqual("deferred", herdr["status"])
        self.assertEqual("experimental-unproved", herdr["runtimeProof"])
        self.assertIs(herdr["automaticSelection"], False)
        self.assertIs(herdr["windowsAdminBoxBootstrap"], False)
        covers = " ".join(herdr["covers"]).lower()
        self.assertIn("session", covers)
        self.assertIn("android", covers)
        docs = DOCS.read_text(encoding="utf-8-sig").lower()
        self.assertIn("herdr is deferred", docs)
        self.assertIn("not part of windows admin box", docs)

    def test_stale_pr_stack_order_and_no_merge_as_is(self) -> None:
        stack = load_json(CONTRACT)["stalePrStack"]
        self.assertTrue(stack["doNotMergeAsIs"])
        self.assertEqual("current origin/main", stack["rebaseOnto"])
        order = [item["pr"] for item in stack["dependencyOrder"]]
        self.assertEqual([96, 98, 101, 99, 100], order)
        docs = DOCS.read_text(encoding="utf-8-sig")
        for pr in (96, 98, 101, 99, 100):
            self.assertIn(f"#{pr}", docs)
        self.assertIn("Do **not** merge", docs)

    def test_proof_ceiling_and_operator_next_probe_command(self) -> None:
        contract = load_json(CONTRACT)
        ceiling = contract["proofCeiling"]
        self.assertEqual("contract+docs+static-tests", ceiling["level"])
        denied = " ".join(ceiling["doesNotClaim"]).lower()
        self.assertIn("live firstmate crew dispatch", denied)
        self.assertIn("native windows", denied)
        self.assertIn("herdr", denied)
        operator_next = contract["operatorNext"]
        self.assertEqual(["bash tooling/firstmate/Test-FirstMateInterop.sh"], operator_next["commands"])
        self.assertEqual("WSL/Ubuntu", operator_next["platform"])
        docs = DOCS.read_text(encoding="utf-8-sig")
        self.assertIn("bash tooling/firstmate/Test-FirstMateInterop.sh", docs)
        self.assertIn("Proof ceiling", docs)
        self.assertIn("OpenCode", docs)
        self.assertIn("Pi", docs)

    def test_no_secrets_or_local_identity_patterns(self) -> None:
        blob = joined_text(CONTRACT, UPSTREAM_PIN, DOCS)
        for pattern in SECRET_PATTERNS:
            match = pattern.search(blob)
            self.assertIsNone(match, f"forbidden pattern matched: {pattern.pattern}")


if __name__ == "__main__":
    unittest.main()
