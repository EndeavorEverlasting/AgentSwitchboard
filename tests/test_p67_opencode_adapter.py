#!/usr/bin/env python3
"""Contract tests for P67 OpenCode adapter capability probe (ADP-01)."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ADAPTER_DIR = ROOT / "tooling" / "evals" / "p67-opencode-adapter"
PROBE_SCRIPT = ADAPTER_DIR / "Get-P67OpenCodeAdapterStatus.ps1"
CAPABILITY_CONTRACT = ADAPTER_DIR / "capability-contract.v1.json"
FIXTURES_DIR = ADAPTER_DIR / "fixtures"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def run_probe(output_path: str | None = None) -> tuple[int, str]:
    """Run the probe script and return exit code and stdout."""
    import shutil
    
    if not shutil.which("pwsh"):
        raise unittest.SkipTest("PowerShell (pwsh) not available")
    
    cmd = ["pwsh", "-NoLogo", "-NoProfile", "-File", str(PROBE_SCRIPT)]
    if output_path:
        cmd.extend(["-OutputPath", output_path])
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout


class P67OpenCodeAdapterTests(unittest.TestCase):
    def test_required_components_exist(self) -> None:
        """Verify all ADP-01 components are present."""
        required = [
            PROBE_SCRIPT,
            CAPABILITY_CONTRACT,
            FIXTURES_DIR / "readiness-ready.json",
            FIXTURES_DIR / "readiness-blocked-not-found.json",
            FIXTURES_DIR / "readiness-blocked-identity.json",
            FIXTURES_DIR / "readiness-evaluative-rejected.json",
        ]
        for path in required:
            self.assertTrue(path.exists(), f"Missing required component: {path}")
    
    def test_capability_contract_schema(self) -> None:
        """Verify capability contract structure and vocabulary alignment."""
        contract = load_json(CAPABILITY_CONTRACT)
        
        self.assertEqual(contract["schema_version"], "p67-opencode-capability-contract/v1")
        
        self.assertIn("required_capabilities", contract)
        capabilities = contract["required_capabilities"]
        self.assertIn("noninteractive_execution", capabilities)
        self.assertIn("explicit_identity", capabilities)
        self.assertIn("isolated_config", capabilities)
        self.assertIn("instrumentation_feasibility", capabilities)
        self.assertIn("auth_readiness", capabilities)
        
        self.assertIn("blocker_codes", contract)
        blockers = contract["blocker_codes"]
        self.assertIn("OPENCODE_NOT_FOUND", blockers)
        self.assertIn("OPENCODE_AUTH_UNAVAILABLE", blockers)
        
        self.assertIn("alignment_with_triage_contract", contract)
        alignment = contract["alignment_with_triage_contract"]
        self.assertIn("RUNTIME_UNAVAILABLE", alignment["invalid_run_codes_reused"])
        
        self.assertIn("forbidden_mutations", contract)
        forbidden = contract["forbidden_mutations"]
        self.assertTrue(any("credential" in rule.lower() for rule in forbidden))
        self.assertTrue(any("prompt" in rule.lower() for rule in forbidden))
        
        self.assertEqual(contract["proof_boundary"], 
                        "Capability verification only. Does not prove adapter implementation correctness or provider effectiveness.")
    
    def test_readiness_status_schema_contract(self) -> None:
        """Verify readiness status schema forbids credentials and evaluative fields."""
        contract = load_json(CAPABILITY_CONTRACT)
        status_schema = contract["readiness_status_schema"]
        
        self.assertEqual(status_schema["schema_version"], "p67-opencode-readiness-status/v1")
        
        fields = status_schema["fields"]
        self.assertIn("status", fields)
        self.assertEqual(fields["status"]["values"], ["READY", "BLOCKED"])
        
        self.assertIn("opencode_found", fields)
        self.assertIn("capabilities_verified", fields)
        self.assertIn("blocker", fields)
        self.assertIn("probe_timestamp_utc", fields)
        
        forbidden_fields = status_schema["forbidden_fields"]
        self.assertIn("api_key", forbidden_fields)
        self.assertIn("token", forbidden_fields)
        self.assertIn("secret", forbidden_fields)
        self.assertIn("password", forbidden_fields)
        self.assertIn("credential", forbidden_fields)
    
    def test_fixture_ready_status_is_valid(self) -> None:
        """Verify ready fixture matches schema."""
        fixture = load_json(FIXTURES_DIR / "readiness-ready.json")
        
        self.assertEqual(fixture["schema_version"], "p67-opencode-readiness-status/v1")
        self.assertEqual(fixture["status"], "READY")
        self.assertTrue(fixture["opencode_found"])
        self.assertIsNotNone(fixture["opencode_version"])
        
        caps = fixture["capabilities_verified"]
        self.assertEqual(caps["noninteractive_execution"], "VERIFIED")
        self.assertEqual(caps["explicit_identity"], "VERIFIED")
        self.assertEqual(caps["isolated_config"], "VERIFIED")
        self.assertEqual(caps["instrumentation_feasibility"], "VERIFIED")
        self.assertEqual(caps["auth_readiness"], "VERIFIED")
        
        self.assertIsNone(fixture["blocker"])
    
    def test_fixture_blocked_not_found_has_typed_blocker(self) -> None:
        """Verify blocked fixture returns exactly one typed blocker."""
        fixture = load_json(FIXTURES_DIR / "readiness-blocked-not-found.json")
        
        self.assertEqual(fixture["status"], "BLOCKED")
        self.assertFalse(fixture["opencode_found"])
        self.assertIsNone(fixture["opencode_version"])
        
        blocker = fixture["blocker"]
        self.assertIsNotNone(blocker)
        self.assertEqual(blocker["code"], "OPENCODE_NOT_FOUND")
        self.assertIn("message", blocker)
        self.assertGreater(len(blocker["message"]), 10)
        
        caps = fixture["capabilities_verified"]
        self.assertEqual(caps["noninteractive_execution"], "BLOCKED")
        self.assertEqual(caps["explicit_identity"], "BLOCKED")
    
    def test_fixture_blocked_identity_has_typed_blocker(self) -> None:
        """Verify identity blocker fixture is valid."""
        fixture = load_json(FIXTURES_DIR / "readiness-blocked-identity.json")
        
        self.assertEqual(fixture["status"], "BLOCKED")
        self.assertTrue(fixture["opencode_found"])
        
        blocker = fixture["blocker"]
        self.assertEqual(blocker["code"], "OPENCODE_IDENTITY_OPAQUE")
        self.assertIn("identity", blocker["message"].lower())
    
    def test_fixture_evaluative_rejected_contains_forbidden_fields(self) -> None:
        """Verify evaluative fixture contains forbidden credential fields for rejection testing."""
        fixture = load_json(FIXTURES_DIR / "readiness-evaluative-rejected.json")
        
        fixture_text = json.dumps(fixture)
        self.assertIn("api_key", fixture_text.lower())
        self.assertIn("token", fixture_text.lower())
        
        self.assertIn("FORBIDDEN_FIELD", fixture_text)
    
    def test_probe_script_is_executable_and_read_only(self) -> None:
        """Verify probe script exists and is marked as read-only in contract."""
        self.assertTrue(PROBE_SCRIPT.exists())
        
        script_content = PROBE_SCRIPT.read_text(encoding="utf-8")
        
        self.assertIn("Read-only probe", script_content)
        self.assertIn("ADP-01", script_content)
        self.assertNotIn("Set-Content -LiteralPath $global", script_content.lower())
        self.assertNotIn("Remove-Item", script_content)
        
        self.assertIn("OPENCODE_NOT_FOUND", script_content)
        self.assertIn("OPENCODE_AUTH_UNAVAILABLE", script_content)
        self.assertIn("p67-opencode-readiness-status/v1", script_content)
    
    def test_probe_runs_without_opencode_installed(self) -> None:
        """Verify probe returns BLOCKED status when OpenCode is not installed."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            output_path = f.name
        
        try:
            exit_code, stdout = run_probe(output_path)
            
            self.assertEqual(exit_code, 0, "Probe should exit 0 even when OpenCode is not found")
            
            status = load_json(Path(output_path))
            
            self.assertEqual(status["schema_version"], "p67-opencode-readiness-status/v1")
            self.assertEqual(status["status"], "BLOCKED")
            self.assertFalse(status["opencode_found"])
            self.assertIsNone(status["opencode_version"])
            
            blocker = status["blocker"]
            self.assertIsNotNone(blocker)
            self.assertEqual(blocker["code"], "OPENCODE_NOT_FOUND")
            
            for field in ["api_key", "token", "secret", "password", "credential"]:
                status_text = json.dumps(status).lower()
                if field in status_text:
                    self.assertNotRegex(status_text, rf"{field}.*[:=]\s*[a-zA-Z0-9+/]{{10,}}")
        
        finally:
            Path(output_path).unlink(missing_ok=True)
    
    def test_probe_outputs_valid_json_to_stdout(self) -> None:
        """Verify probe outputs valid JSON to stdout when no output path specified."""
        exit_code, stdout = run_probe()
        
        self.assertEqual(exit_code, 0)
        self.assertGreater(len(stdout), 10)
        
        status = json.loads(stdout)
        self.assertEqual(status["schema_version"], "p67-opencode-readiness-status/v1")
        self.assertIn(status["status"], ["READY", "BLOCKED"])
    
    def test_no_evaluative_fields_in_status_schema(self) -> None:
        """Verify status schema rejects evaluative fields per CAPTURE_EVALUATIVE_REJECTED rule."""
        contract = load_json(CAPABILITY_CONTRACT)
        
        status_schema = contract["readiness_status_schema"]
        allowed_fields = set(status_schema["fields"].keys())
        
        evaluative_fields = {"useful", "first_green", "after_fixed_point", "correct", "effectiveness"}
        self.assertTrue(allowed_fields.isdisjoint(evaluative_fields), 
                       "Status schema must not allow evaluative fields")
        
        contract_fields = json.dumps(list(status_schema["fields"].keys())).lower()
        for forbidden in evaluative_fields:
            self.assertNotIn(f'"{forbidden}"', contract_fields, 
                           f"Status schema must not contain evaluative field: {forbidden}")


if __name__ == "__main__":
    unittest.main()
