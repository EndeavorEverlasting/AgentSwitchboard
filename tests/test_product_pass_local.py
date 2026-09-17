#!/usr/bin/env python3
"""
AgentSwitchboard product-pass-local meta contracts

Fail closed on zero tests.
"""

import json
import os
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


class ProductPassLocalMetaContract(unittest.TestCase):
    """Meta contracts for product-pass-local proof system"""

    def setUp(self):
        self.prove_script = REPO_ROOT / 'scripts' / 'Prove-ProductPassLocal.ps1'
        self.floor_script = REPO_ROOT / 'scripts' / 'Prove-AutomatedTestFloorLocal.ps1'
        self.merge_gate_script = REPO_ROOT / 'scripts' / 'Prove-MergeGateLocal.ps1'

    def test_prove_script_exists(self):
        """Prove-ProductPassLocal.ps1 must exist"""
        self.assertTrue(
            self.prove_script.exists(),
            f"Prove script not found: {self.prove_script}"
        )

    def test_orchestrated_scripts_exist(self):
        """Orchestrated floor and merge-gate scripts must exist"""
        self.assertTrue(
            self.floor_script.exists(),
            f"Floor script not found: {self.floor_script}"
        )
        self.assertTrue(
            self.merge_gate_script.exists(),
            f"Merge-gate script not found: {self.merge_gate_script}"
        )

    def test_references_floor_script(self):
        """Prove script must reference floor script"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'Prove-AutomatedTestFloorLocal.ps1',
            content,
            "Prove script must reference floor script"
        )

    def test_references_merge_gate_script(self):
        """Prove script must reference merge-gate script"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'Prove-MergeGateLocal.ps1',
            content,
            "Prove script must reference merge-gate script"
        )

    def test_floor_always_runs(self):
        """Floor script must always run (not path-selected)"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        # Should indicate floor is always-on
        self.assertIn(
            'always',
            content.lower(),
            "Floor should be documented as always-on"
        )

    def test_merge_gate_path_selected(self):
        """Merge-gate script must be path-selected"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        # Should indicate merge-gate is path-selected
        self.assertIn(
            'path',
            content.lower(),
            "Merge-gate should be documented as path-selected"
        )

    def test_has_posture_semantics(self):
        """Prove script must use PROVEN/UNPROVEN/BLOCKED_HOST/FLAGGED semantics"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        required_states = ['PROVEN', 'UNPROVEN', 'BLOCKED_HOST', 'FLAGGED']
        for state in required_states:
            self.assertIn(
                state,
                content,
                f"Prove script must reference posture state: {state}"
            )

    def test_proof_ceiling_forbids_merge_authority(self):
        """Proof ceiling must explicitly forbid merge/release/deploy authority"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        ceiling = content.lower()

        # Must not claim merge authority
        self.assertNotIn('grant', ceiling)
        self.assertNotIn('permits merge', ceiling)
        self.assertNotIn('allows merge', ceiling)

        # Must explicitly state what it does NOT prove
        forbidden_keywords = ['merge', 'release', 'deploy']
        ceiling_contains_forbidden = any(kw in ceiling for kw in forbidden_keywords)
        self.assertTrue(
            ceiling_contains_forbidden,
            "Proof ceiling must explicitly state what it does NOT prove (merge/release/deploy)"
        )

    def test_no_logic_duplication(self):
        """Prove script must not duplicate floor or merge-gate logic"""
        content = self.prove_script.read_text(encoding='utf-8-sig')

        # Should call scripts, not duplicate their logic
        self.assertIn(
            'Invoke-ProveScript',
            content,
            "Should use delegation pattern"
        )

        # Should NOT duplicate manifest loading or gate execution
        self.assertNotIn(
            'merge-gate-local.manifest.json',
            content,
            "Should not duplicate merge-gate manifest loading"
        )
        self.assertNotIn(
            'automated-test-floor.manifest.json',
            content,
            "Should not duplicate floor manifest loading"
        )

    def test_fail_closed_on_missing_pwsh(self):
        """Prove script must fail closed when pwsh is not found"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'FAIL_CLOSED',
            content,
            "Prove script must have FAIL_CLOSED behavior"
        )

    def test_has_blocked_host_detection(self):
        """Prove script must detect BLOCKED_HOST from merge-gate"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'BLOCKED_HOST',
            content,
            "Prove script must detect BLOCKED_HOST conditions"
        )

    def test_has_flag_checks(self):
        """Prove script must include flag checks (git diff --check)"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'git diff --check',
            content,
            "Prove script must include git diff --check flag"
        )
        self.assertIn(
            'flags',
            content.lower(),
            "Prove script must track flags"
        )

    def test_exits_non_zero_on_failure(self):
        """Prove script must exit non-zero when posture is not PROVEN"""
        content = self.prove_script.read_text(encoding='utf-8-sig')

        # Should exit 1 when not PROVEN
        self.assertIn(
            'exit 1',
            content,
            "Prove script must exit non-zero on failure"
        )

        # Should check posture before exit
        self.assertIn(
            'posture',
            content.lower(),
            "Prove script must check posture"
        )

    def test_generates_proof_packet(self):
        """Prove script must generate proof packet artifacts"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'product-pass-local-proof-packet',
            content,
            "Prove script must generate product-pass-local proof packet"
        )
        self.assertIn(
            '.json',
            content,
            "Prove script must generate JSON proof packet"
        )
        self.assertIn(
            '.md',
            content,
            "Prove script must generate markdown proof packet"
        )

    def test_has_schema_version(self):
        """Proof packet must have schema version"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'schema',
            content.lower(),
            "Proof packet must include schema field"
        )
        self.assertIn(
            'agentswitchboard.product-pass-local',
            content,
            "Proof packet must have product-pass-local schema identifier"
        )

    def test_no_admin_box_claim(self):
        """Prove script must not claim Admin Box authority"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        # Should not claim Admin Box
        self.assertNotIn(
            'admin-box',
            content.lower(),
            "Static prove script must not claim Admin Box"
        )

    def test_no_secret_handling(self):
        """Prove script must not handle secrets"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        secret_keywords = ['secret', 'credential', 'password', 'token']
        for keyword in secret_keywords:
            self.assertNotIn(
                keyword,
                content.lower(),
                f"Static prove script must not handle secrets: {keyword}"
            )


class ProductPassLocalZeroTestDetection(unittest.TestCase):
    """Fail-closed zero-test detection"""

    def test_meta_contract_has_tests(self):
        """This test suite must have multiple tests"""
        loader = unittest.TestLoader()
        suite = loader.loadTestsFromModule(sys.modules[__name__])
        test_count = suite.countTestCases()
        self.assertGreater(
            test_count, 5,
            f"Product pass local test suite must have more than 5 tests, found {test_count}"
        )


if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    if result.testsRun == 0:
        print("FAIL_CLOSED: Zero tests executed", file=sys.stderr)
        sys.exit(1)

    sys.exit(0 if result.wasSuccessful() else 1)
