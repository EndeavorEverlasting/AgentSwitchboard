#!/usr/bin/env python3
"""Contract tests for P67 OpenCode adapter (ADP-01 + ADP-02)."""

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
NEW_CONFIG_SCRIPT = ADAPTER_DIR / "New-P67AdapterConfig.ps1"
INVOKE_SCRIPT = ADAPTER_DIR / "Invoke-P67OpenCodeAdapter.ps1"
NORMALIZER_MODULE = ADAPTER_DIR / "ConvertTo-NeutralCapture.psm1"


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


class P67OpenCodeAdapterADP02Tests(unittest.TestCase):
    """ADP-02: Adapter implementation tests."""

    def test_adp02_components_exist(self) -> None:
        """Verify all ADP-02 components are present."""
        required = [
            NEW_CONFIG_SCRIPT,
            INVOKE_SCRIPT,
            NORMALIZER_MODULE,
        ]
        for path in required:
            self.assertTrue(path.exists(), f"Missing ADP-02 component: {path}")

    def test_new_config_script_structure(self) -> None:
        """Verify New-P67AdapterConfig.ps1 structure and contracts."""
        content = NEW_CONFIG_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("ADP-02", content)
        self.assertIn("compute-authority-agent-adapter/v1", content)
        self.assertIn("Invoke-P67OpenCodeAdapter.ps1", content)

        self.assertIn("Provider", content)
        self.assertIn("Model", content)
        self.assertIn("Agent", content)

        self.assertNotIn("api_key.*=.*[a-zA-Z0-9]{10,}", content.lower())
        self.assertNotIn("token.*=.*[a-zA-Z0-9]{10,}", content.lower())

    def test_new_config_no_credential_values(self) -> None:
        """Verify config generator never stores credential values."""
        content = NEW_CONFIG_SCRIPT.read_text(encoding="utf-8")

        credential_leak_patterns = [
            r'api[_-]?key.*[:=]\s*[a-zA-Z0-9+/]{10,}',
            r'token.*[:=]\s*[a-zA-Z0-9+/]{10,}',
            r'secret.*[:=]\s*[a-zA-Z0-9+/]{10,}',
        ]

        for pattern in credential_leak_patterns:
            import re
            self.assertIsNone(re.search(pattern, content, re.IGNORECASE),
                            f"Config script may contain credential values matching: {pattern}")

    def test_invoke_script_argv_only(self) -> None:
        """Verify Invoke script accepts only argv parameters (no shell composition)."""
        content = INVOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("[Parameter(Mandatory)]", content)
        self.assertIn("$Workspace", content)
        self.assertIn("$Task", content)
        self.assertIn("$Prompt", content)
        self.assertIn("$Result", content)

        self.assertNotIn("Invoke-Expression", content)
        self.assertNotIn("iex", content.lower())

    def test_invoke_script_privacy_bounded(self) -> None:
        """Verify Invoke script maintains privacy boundaries."""
        content = INVOKE_SCRIPT.read_text(encoding="utf-8")

        forbidden_persistence = [
            "raw_transcript",
            "full_conversation",
            "model_text.*Set-Content",
            "chat_history",
        ]

        for forbidden in forbidden_persistence:
            import re
            self.assertIsNone(re.search(forbidden, content, re.IGNORECASE),
                            f"Invoke script may persist forbidden data: {forbidden}")

    def test_invoke_script_fail_closed(self) -> None:
        """Verify Invoke script fails closed on timeout/nonzero/missing."""
        content = INVOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("INVALID", content)
        self.assertIn("timeout", content.lower())
        self.assertIn("exit 1", content)

    def test_invoke_script_evaluative_rejected(self) -> None:
        """Verify Invoke script enforces CAPTURE_EVALUATIVE_REJECTED."""
        content = INVOKE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("CAPTURE_EVALUATIVE_REJECTED", content)

        evaluative_fields = ["useful", "first_green", "after_fixed_point", "correct", "effectiveness"]
        for field in evaluative_fields:
            self.assertIn(field, content.lower())

    def test_normalizer_module_structure(self) -> None:
        """Verify neutral event normalizer module structure."""
        content = NORMALIZER_MODULE.read_text(encoding="utf-8")

        self.assertIn("ADP-02", content)
        self.assertIn("CAPTURE_EVALUATIVE_REJECTED", content)
        self.assertIn("Export-ModuleMember", content)

        required_functions = [
            "Test-CaptureFieldAllowed",
            "Test-CaptureObjectValid",
            "ConvertTo-NeutralExecutionSummary",
            "ConvertTo-NeutralProviderIdentity",
        ]

        for func in required_functions:
            self.assertIn(func, content)

    def test_normalizer_rejects_evaluative_fields(self) -> None:
        """Verify normalizer rejects evaluative fields."""
        content = NORMALIZER_MODULE.read_text(encoding="utf-8")

        evaluative_fields = ["useful", "first_green", "after_fixed_point", "correct", "effectiveness"]
        for field in evaluative_fields:
            self.assertIn(field, content.lower())

        self.assertIn("ForbiddenEvaluativeFields", content)

    def test_normalizer_rejects_privacy_fields(self) -> None:
        """Verify normalizer rejects privacy-violating fields."""
        content = NORMALIZER_MODULE.read_text(encoding="utf-8")

        privacy_fields = ["raw_prompt", "raw_response", "transcript", "full_conversation"]
        for field in privacy_fields:
            self.assertIn(field, content.lower())

        self.assertIn("ForbiddenPrivacyFields", content)

    def test_normalizer_rejects_credential_fields(self) -> None:
        """Verify normalizer rejects credential fields."""
        content = NORMALIZER_MODULE.read_text(encoding="utf-8")

        credential_fields = ["api_key", "token", "secret", "password", "credential"]
        for field in credential_fields:
            self.assertIn(field, content.lower())

        self.assertIn("ForbiddenCredentialFields", content)

    def test_capture_contract_v2_schema(self) -> None:
        """Verify capture contract v2 schema is used."""
        invoke_content = INVOKE_SCRIPT.read_text(encoding="utf-8")
        normalizer_content = NORMALIZER_MODULE.read_text(encoding="utf-8")

        self.assertIn("compute-authority-provider-capture/v2", invoke_content)
        self.assertIn("compute-authority-provider-capture/v2", normalizer_content)


class P67OpenCodeAdapterADP03Tests(unittest.TestCase):
    """ADP-03: Synthetic interoperability tests."""

    def setUp(self) -> None:
        self.adp03_fixtures_dir = FIXTURES_DIR / "adp03"

    def test_adp03_fixtures_exist(self) -> None:
        """Verify all ADP-03 synthetic fixtures are present."""
        required_fixtures = [
            "synthetic-01-happy-path-valid.json",
            "synthetic-02-validation-nonzero.json",
            "synthetic-03-timeout-fail-closed.json",
            "synthetic-04-missing-result-fail-closed.json",
            "synthetic-05-parallel-subagent-lane.json",
            "synthetic-06-privacy-rejected.json",
            "synthetic-07-evaluative-rejected.json",
            "synthetic-08-invalid-workspace.json",
        ]
        for fixture in required_fixtures:
            fixture_path = self.adp03_fixtures_dir / fixture
            self.assertTrue(fixture_path.exists(), f"Missing ADP-03 fixture: {fixture}")

    def test_adp03_fixture_01_happy_path_valid(self) -> None:
        """Verify happy path fixture produces VALID capture v2."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-01-happy-path-valid.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "VALID")
        self.assertIn("provider_identity", fixture)
        self.assertIn("task_id", fixture)
        self.assertIn("execution_summary", fixture)
        self.assertIn("workspace_state", fixture)
        self.assertIn("validation_result", fixture)

        self.assertTrue(fixture["validation_result"]["validation_passed"])

    def test_adp03_fixture_02_validation_nonzero(self) -> None:
        """Verify validation nonzero fixture handles test failure correctly."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-02-validation-nonzero.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "VALID")
        self.assertFalse(fixture["validation_result"]["validation_passed"])
        self.assertEqual(fixture["validation_result"]["validation_exit_code"], 1)

    def test_adp03_fixture_03_timeout_fail_closed(self) -> None:
        """Verify timeout fixture produces INVALID with EXECUTION_TIMEOUT."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-03-timeout-fail-closed.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "INVALID")
        self.assertEqual(fixture["invalid_reason"]["code"], "EXECUTION_TIMEOUT")
        self.assertIn("timeout", fixture["invalid_reason"]["message"].lower())

    def test_adp03_fixture_04_missing_result_fail_closed(self) -> None:
        """Verify missing result fixture produces INVALID with fail-closed code."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-04-missing-result-fail-closed.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "INVALID")
        self.assertIn(fixture["invalid_reason"]["code"], ["RUNTIME_UNAVAILABLE", "ADAPTER_ERROR"])

    def test_adp03_fixture_05_parallel_subagent_lane(self) -> None:
        """Verify parallel/subagent synthetic fixture captures multi-lane execution."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-05-parallel-subagent-lane.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "VALID")
        self.assertIn("neutral_telemetry", fixture)
        self.assertGreater(fixture["neutral_telemetry"]["provider_actions_count"], 1)

    def test_adp03_fixture_06_privacy_rejected(self) -> None:
        """Verify privacy rejection fixture contains no actual privacy violations."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-06-privacy-rejected.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "INVALID")
        self.assertIn("PRIVACY", fixture["invalid_reason"]["code"])

        fixture_text = json.dumps(fixture)
        forbidden_privacy_fields = ["raw_prompt", "raw_response", "transcript", "full_conversation", "chat_history"]
        for field in forbidden_privacy_fields:
            pattern = f'"{field}":\\s*[^"]'
            self.assertNotRegex(fixture_text, pattern,
                              f"Privacy rejection fixture must not contain actual {field} field outside marker")

    def test_adp03_fixture_07_evaluative_rejected(self) -> None:
        """Verify evaluative rejection fixture contains no actual evaluative judgments."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-07-evaluative-rejected.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "INVALID")
        self.assertEqual(fixture["invalid_reason"]["code"], "CAPTURE_EVALUATIVE_REJECTED")

        fixture_text = json.dumps(fixture)
        forbidden_evaluative_fields = ["useful", "first_green", "after_fixed_point", "correct", "effectiveness"]
        for field in forbidden_evaluative_fields:
            if field in fixture["invalid_reason"].get("FORBIDDEN_FIELD_EXAMPLE", ""):
                continue
            pattern = f'"{field}":\\s*(true|false|[0-9])'
            self.assertNotRegex(fixture_text, pattern,
                              f"Evaluative rejection fixture must not contain actual {field} field outside marker")

    def test_adp03_fixture_08_invalid_workspace(self) -> None:
        """Verify invalid workspace fixture fails closed with WORKSPACE_INVALID."""
        fixture = load_json(self.adp03_fixtures_dir / "synthetic-08-invalid-workspace.json")

        self.assertEqual(fixture["schema_version"], "compute-authority-provider-capture/v2")
        self.assertEqual(fixture["run_status"], "INVALID")
        self.assertEqual(fixture["invalid_reason"]["code"], "WORKSPACE_INVALID")
        self.assertIn("workspace", fixture["invalid_reason"]["message"].lower())

    def test_adp03_all_fixtures_have_no_live_opencode(self) -> None:
        """Verify ADP-03 fixtures are synthetic only (no live OpenCode execution)."""
        fixtures = [
            "synthetic-01-happy-path-valid.json",
            "synthetic-02-validation-nonzero.json",
            "synthetic-03-timeout-fail-closed.json",
            "synthetic-04-missing-result-fail-closed.json",
            "synthetic-05-parallel-subagent-lane.json",
            "synthetic-06-privacy-rejected.json",
            "synthetic-07-evaluative-rejected.json",
            "synthetic-08-invalid-workspace.json",
        ]

        for fixture_name in fixtures:
            fixture = load_json(self.adp03_fixtures_dir / fixture_name)
            self.assertIn("synthetic", fixture.get("task_id", "").lower(),
                        f"Fixture {fixture_name} must have synthetic marker in task_id")

    def test_adp03_synthetic_interop_runner_exists(self) -> None:
        """Verify ADP-03 synthetic interoperability runner script exists."""
        runner_script = ROOT / "scripts" / "Invoke-P67OpenCodeAdapterSyntheticInterop.ps1"
        self.assertTrue(runner_script.exists(), "ADP-03 runner script missing")

        content = runner_script.read_text(encoding="utf-8")
        self.assertIn("ADP-03", content)
        self.assertIn("synthetic interoperability", content.lower())
        self.assertIn("no live OpenCode", content.lower())

    def test_adp03_runner_produces_receipt(self) -> None:
        """Verify ADP-03 runner can produce a machine-readable receipt."""
        import shutil

        if not shutil.which("pwsh"):
            self.skipTest("PowerShell (pwsh) not available")

        runner_script = ROOT / "scripts" / "Invoke-P67OpenCodeAdapterSyntheticInterop.ps1"
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            output_path = f.name

        try:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-File", str(runner_script), "-OutputPath", output_path],
                capture_output=True,
                text=True
            )

            self.assertTrue(Path(output_path).exists(), "Receipt file not created")

            receipt = load_json(Path(output_path))
            self.assertIn("schema_version", receipt)
            self.assertIn("test_run_summary", receipt)
            self.assertIn("adp03_paths_covered", receipt)
            self.assertEqual(receipt["proof_level"], "SYNTHETIC_INTEROPERABILITY")

            paths_covered = receipt["adp03_paths_covered"]
            self.assertIn("happy_path_valid_capture_v2", paths_covered)
            self.assertIn("timeout_fail_closed", paths_covered)
            self.assertIn("privacy_rejection", paths_covered)
            self.assertIn("evaluative_rejection", paths_covered)

        finally:
            Path(output_path).unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
