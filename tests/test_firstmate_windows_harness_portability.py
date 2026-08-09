import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
MANIFEST = HARNESS / "manifest.json"
CODEBASE = HARNESS / "codebase-map.json"
VALIDATORS = HARNESS / "validator-registry.json"
WORKFLOWS = HARNESS / "workflow-registry.json"
WINDOWS_ENTRY = ROOT / "Test-AgentSwitchboard-FirstMate-Harness.ps1"
WINDOWS_CMD = ROOT / "Test-AgentSwitchboard-FirstMate-Harness.cmd"
INTEGRATION_TEST = ROOT / "tests" / "test_firstmate_integration_contract.py"
OPERATIONAL_TEST = ROOT / "tests" / "test_firstmate_operational_harness.py"
CI = ROOT / ".github" / "workflows" / "firstmate-interop.yml"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class FirstMateWindowsHarnessPortabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = load(MANIFEST)
        cls.codebase = load(CODEBASE)
        cls.validators = load(VALIDATORS)
        cls.workflows = load(WORKFLOWS)
        cls.windows_entry = WINDOWS_ENTRY.read_text(encoding="utf-8")
        cls.windows_cmd = WINDOWS_CMD.read_text(encoding="utf-8")
        cls.integration_test = INTEGRATION_TEST.read_text(encoding="utf-8")
        cls.operational_test = OPERATIONAL_TEST.read_text(encoding="utf-8")
        cls.ci = CI.read_text(encoding="utf-8")

    def test_manifest_registers_windows_native_front_door_and_normalizer(self):
        components = self.manifest["components"]
        self.assertEqual(components["windows_entrypoint"], "Test-AgentSwitchboard-FirstMate-Harness.ps1")
        self.assertEqual(components["windows_cmd_entrypoint"], "Test-AgentSwitchboard-FirstMate-Harness.cmd")
        self.assertEqual(
            components["origin_normalizer"],
            "tooling/firstmate/harness/operational/Normalize-FirstMateOrigin.py",
        )

    def test_windows_front_door_runs_contracts_without_bare_bash(self):
        lowered = self.windows_entry.lower()
        self.assertNotIn("bash", lowered)
        for test_name in (
            "test_firstmate_integration_contract.py",
            "test_firstmate_operational_harness.py",
            "test_firstmate_windows_harness_portability.py",
            "test_firstmate_windows_wsl_bridge.py",
        ):
            self.assertIn(test_name, self.windows_entry)
        self.assertIn("FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS", self.windows_entry)
        self.assertIn("'runtime-floor'", self.windows_entry)
        self.assertIn("RepairWslIfNeeded", self.windows_entry)

    def test_bridge_is_invoked_as_child_process_so_exit_cannot_skip_parent_gates(self):
        self.assertIn("& pwsh -NoLogo -NoProfile -File $bridge", self.windows_entry)
        self.assertIn("& pwsh @bridgeArgs", self.windows_entry)
        self.assertNotIn("& $bridge", self.windows_entry)
        self.assertIn("Working-tree diff hygiene", self.windows_entry)
        self.assertIn("FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS", self.windows_entry)

    def test_cmd_wrapper_is_location_independent_and_propagates_exit_code(self):
        self.assertIn("%~dp0", self.windows_cmd)
        self.assertIn("Test-AgentSwitchboard-FirstMate-Harness.ps1", self.windows_cmd)
        self.assertIn("exit /b %EXITCODE%", self.windows_cmd)

    def test_integration_contract_no_longer_executes_bash_from_windows_python(self):
        self.assertNotRegex(
            self.integration_test,
            re.compile(r"subprocess\.run\(\s*\[\s*[\"']bash[\"']", re.MULTILINE),
        )
        self.assertIn("sys.executable", self.integration_test)
        self.assertIn("Normalize-FirstMateOrigin.py", self.integration_test)

    def test_operational_contract_reuses_current_python_interpreter(self):
        self.assertIn("import sys", self.operational_test)
        self.assertIn("sys.executable", self.operational_test)
        self.assertNotRegex(
            self.operational_test,
            re.compile(r"subprocess\.run\(\s*\[\s*[\"']python3[\"']", re.MULTILINE),
        )
        self.assertNotRegex(
            self.operational_test,
            re.compile(r"subprocess\.run\(\s*\[\s*[\"']python[\"']", re.MULTILINE),
        )

    def test_registry_exposes_platform_aware_windows_validator_and_workflow(self):
        validator_ids = {item["id"] for item in self.validators["validators"]}
        self.assertIn("firstmate-windows-native-harness", validator_ids)
        workflow_ids = {item["id"] for item in self.workflows["workflows"]}
        self.assertIn("windows-laptop-validation", workflow_ids)
        workflow = load(HARNESS / "workflows" / "windows-laptop-validation.json")
        self.assertEqual(workflow["id"], "windows-laptop-validation")
        self.assertIn("PowerShell", "\n".join(workflow["steps"]))
        handling = workflow["failure_handling"]
        if isinstance(handling, str):
            handling = [handling]
        handling_text = "\n".join(handling).lower()
        self.assertIn("bare bash", handling_text)
        self.assertIn("9009", handling_text)
        self.assertIn("sys.executable", handling_text)

    def test_codebase_map_records_observed_cross_shell_and_python_alias_traps(self):
        traps = "\n".join(self.codebase["known_traps"]).lower()
        self.assertIn("bare bash", traps)
        self.assertIn("windows path", traps)
        self.assertIn("default wsl distribution", traps)
        self.assertIn("python3", traps)
        self.assertIn("sys.executable", traps)
        self.assertIn("windows_harness", self.codebase["entrypoints"])

    def test_windows_ci_runs_the_windows_native_front_door(self):
        self.assertIn("Test-AgentSwitchboard-FirstMate-Harness.ps1", self.ci)
        self.assertIn("-Mode contract", self.ci)
        self.assertIn("test_firstmate_windows_harness_portability.py", self.ci)


if __name__ == "__main__":
    unittest.main()
