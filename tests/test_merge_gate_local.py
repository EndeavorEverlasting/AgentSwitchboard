#!/usr/bin/env python3
"""
AgentSwitchboard merge-gate-local meta contracts

Fail closed on zero tests.
"""

import json
import os
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


class MergeGateLocalMetaContract(unittest.TestCase):
    """Meta contracts for merge-gate-local proof system"""

    def setUp(self):
        self.manifest_path = REPO_ROOT / '.ai' / 'harness' / 'merge-gate-local.manifest.json'
        self.prove_script = REPO_ROOT / 'scripts' / 'Prove-MergeGateLocal.ps1'

    def test_manifest_exists(self):
        """Manifest file must exist"""
        self.assertTrue(
            self.manifest_path.exists(),
            f"Manifest not found: {self.manifest_path}"
        )

    def test_manifest_valid_json(self):
        """Manifest must be valid JSON"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        self.assertIsInstance(manifest, dict)

    def test_manifest_schema(self):
        """Manifest must have required schema fields"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        required_fields = [
            'schemaVersion',
            'manifestId',
            'proofLevel',
            'proofCeiling',
            'failClosed',
            'gates'
        ]
        for field in required_fields:
            self.assertIn(field, manifest, f"Missing required field: {field}")
        
        self.assertEqual(manifest['schemaVersion'], 1)
        self.assertEqual(manifest['manifestId'], 'agentswitchboard.merge-gate-local.v1')
        self.assertEqual(manifest['proofLevel'], 'static-test')

    def test_fail_closed_rules(self):
        """Manifest must enforce fail-closed rules"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        fail_closed = manifest['failClosed']
        required_rules = [
            'skipMustNotCountAsPass',
            'missingHostCapabilityFails',
            'missingToolFails'
        ]
        for rule in required_rules:
            self.assertIn(rule, fail_closed, f"Missing fail-closed rule: {rule}")
            self.assertTrue(fail_closed[rule], f"Fail-closed rule must be true: {rule}")

    def test_proof_ceiling_forbids_merge_authority(self):
        """Proof ceiling must explicitly forbid merge/release/deploy authority"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        ceiling = manifest['proofCeiling'].lower()
        # Must not claim merge authority
        self.assertNotIn('grant', ceiling)
        self.assertNotIn('permits merge', ceiling.lower())
        self.assertNotIn('allows merge', ceiling.lower())
        
        # Must explicitly state what it does NOT prove
        forbidden_keywords = ['merge', 'release', 'deploy']
        ceiling_contains_forbidden = any(kw in ceiling for kw in forbidden_keywords)
        self.assertTrue(
            ceiling_contains_forbidden,
            "Proof ceiling must explicitly state what it does NOT prove (merge/release/deploy)"
        )

    def test_has_always_on_gates(self):
        """Manifest must have at least one always-on gate"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        always_on_gates = [g for g in manifest['gates'] if g.get('tier') == 'always-on']
        self.assertGreater(
            len(always_on_gates), 0,
            "Manifest must have at least one always-on gate"
        )

    def test_gates_have_required_fields(self):
        """Each gate must have required fields"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        required_gate_fields = [
            'id',
            'tier',
            'workflow',
            'job',
            'paths',
            'commands',
            'host',
            'required',
            'proof'
        ]
        
        for gate in manifest['gates']:
            for field in required_gate_fields:
                self.assertIn(
                    field, gate,
                    f"Gate {gate.get('id', 'UNKNOWN')} missing required field: {field}"
                )
            
            # Validate tier values
            self.assertIn(
                gate['tier'], ['always-on', 'path-activated'],
                f"Gate {gate['id']} has invalid tier: {gate['tier']}"
            )
            
            # Validate host values
            valid_hosts = ['any', 'linux', 'windows', 'macos', 'admin-box']
            self.assertIn(
                gate['host'], valid_hosts,
                f"Gate {gate['id']} has invalid host: {gate['host']}"
            )
            
            # Always-on gates should have empty paths
            if gate['tier'] == 'always-on':
                self.assertEqual(
                    len(gate['paths']), 0,
                    f"Always-on gate {gate['id']} should have empty paths"
                )
            
            # Path-activated gates should have non-empty paths
            if gate['tier'] == 'path-activated':
                self.assertGreater(
                    len(gate['paths']), 0,
                    f"Path-activated gate {gate['id']} must have paths"
                )
            
            # Must have at least one command
            self.assertGreater(
                len(gate['commands']), 0,
                f"Gate {gate['id']} must have at least one command"
            )
            
            # required must be true (fail-closed)
            self.assertTrue(
                gate['required'],
                f"Gate {gate['id']} must be required (fail-closed)"
            )

    def test_automated_test_floor_is_always_on(self):
        """Automated test floor must be always-on"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        floor_gates = [
            g for g in manifest['gates']
            if 'automated-test-floor' in g.get('id', '').lower()
        ]
        self.assertGreater(len(floor_gates), 0, "Must have automated-test-floor gate")
        
        for gate in floor_gates:
            self.assertEqual(
                gate['tier'], 'always-on',
                f"Gate {gate['id']} must be always-on"
            )

    def test_prove_script_exists(self):
        """Prove-MergeGateLocal.ps1 must exist"""
        self.assertTrue(
            self.prove_script.exists(),
            f"Prove script not found: {self.prove_script}"
        )

    def test_prove_script_references_manifest(self):
        """Prove script must reference the manifest"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        self.assertIn(
            'merge-gate-local.manifest.json',
            content,
            "Prove script must reference manifest file"
        )

    def test_no_skip_as_pass_in_prove_script(self):
        """Prove script must not silently skip gates as pass"""
        content = self.prove_script.read_text(encoding='utf-8-sig')
        
        # Should have explicit BLOCKED or FAIL states for unmet requirements
        self.assertIn('BLOCKED', content, "Prove script must have BLOCKED state")
        
        # Should fail closed
        self.assertIn('FAIL', content, "Prove script must have FAIL state")

    def test_gate_commands_exist(self):
        """Commands referenced by gates must exist in the repository"""
        with open(self.manifest_path, 'r', encoding='utf-8-sig') as f:
            manifest = json.load(f)
        
        for gate in manifest['gates']:
            for cmd in gate['commands']:
                # Extract file path from command
                if 'pwsh' in cmd or 'python' in cmd or 'bash' in cmd:
                    parts = cmd.split()
                    # Find the script path
                    for part in parts:
                        if part.endswith('.ps1') or part.endswith('.py') or part.endswith('.sh'):
                            script_path = REPO_ROOT / part
                            self.assertTrue(
                                script_path.exists(),
                                f"Gate {gate['id']} references non-existent script: {part}"
                            )


class MergeGateLocalZeroTestDetection(unittest.TestCase):
    """Fail-closed zero-test detection"""

    def test_meta_contract_has_tests(self):
        """This test suite must have multiple tests"""
        loader = unittest.TestLoader()
        suite = loader.loadTestsFromModule(sys.modules[__name__])
        test_count = suite.countTestCases()
        self.assertGreater(
            test_count, 5,
            f"Merge gate local test suite must have more than 5 tests, found {test_count}"
        )


if __name__ == '__main__':
    # Run with verbose output
    suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Fail closed on zero tests
    if result.testsRun == 0:
        print("FAIL_CLOSED: Zero tests executed", file=sys.stderr)
        sys.exit(1)
    
    # Exit with proper code
    sys.exit(0 if result.wasSuccessful() else 1)
