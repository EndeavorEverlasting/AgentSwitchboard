import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1"
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
WORKFLOW = ROOT / ".github" / "workflows" / "firstmate-interop.yml"


class FirstMateWindowsWslPrerequisiteGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.wrapper = WRAPPER.read_text(encoding="utf-8")
        cls.manifest = json.loads((HARNESS / "manifest.json").read_text(encoding="utf-8"))
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.validators = json.loads((HARNESS / "validator-registry.json").read_text(encoding="utf-8"))
        cls.codebase = json.loads((HARNESS / "codebase-map.json").read_text(encoding="utf-8"))
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_wrapper_is_registered_as_physical_floor_owner(self):
        self.assertEqual(
            self.manifest["components"]["windows_wsl_physical_floor"],
            "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1",
        )
        self.assertIn("Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1", self.codebase["entrypoints"]["windows_wsl_bridge"])
        self.assertIn("firstmate-wsl-prerequisites.txt", self.wrapper)
        self.assertIn(
            "windows-wsl-prerequisite-proof",
            {item["id"] for item in self.artifacts["artifacts"]},
        )

    def test_prerequisite_gate_checks_full_linux_floor_before_bridge(self):
        self.assertIn("required=(git gh tmux python3)", self.wrapper)
        self.assertIn("gh auth status --hostname github.com >/dev/null 2>&1", self.wrapper)
        self.assertIn("STATUS=BLOCKED_MISSING_TOOLS", self.wrapper)
        self.assertIn("STATUS=BLOCKED_GITHUB_AUTH", self.wrapper)
        self.assertIn("STATUS=PASS", self.wrapper)
        preflight_index = self.wrapper.index("$preflight = Invoke-CapturedProcess")
        bridge_index = self.wrapper.index("$bridge = Invoke-CapturedProcess")
        self.assertLess(preflight_index, bridge_index)

    def test_gate_reports_operator_repair_but_never_installs_dependencies(self):
        apt_lines = [line.strip() for line in self.wrapper.splitlines() if "apt-get" in line]
        self.assertEqual(len(apt_lines), 1)
        self.assertIn("NEXT_ACTION=", apt_lines[0])
        self.assertIn("sudo apt-get update && sudo apt-get install -y", apt_lines[0])
        self.assertIn("NEXT_ACTION=gh auth login --hostname github.com --git-protocol https --web", self.wrapper)

    def test_auth_probe_suppresses_sensitive_cli_output(self):
        self.assertIn("gh auth status --hostname github.com >/dev/null 2>&1", self.wrapper)
        self.assertNotIn("gh auth token", self.wrapper)
        self.assertNotIn("GH_TOKEN", self.wrapper)
        self.assertNotIn("GITHUB_TOKEN", self.wrapper)

    def test_success_marker_is_inside_wrapper_after_child_exit_gate(self):
        failure_index = self.wrapper.index("if ($bridge.ExitCode -ne 0)")
        pass_index = self.wrapper.index("[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR")
        self.assertLess(failure_index, pass_index)
        self.assertIn("throw \"First Mate lower bridge failed. Exit=$($bridge.ExitCode)\"", self.wrapper)

    def test_evidence_root_is_unique_per_physical_attempt(self):
        self.assertIn("[guid]::NewGuid()", self.wrapper)
        self.assertIn("firstmate-windows-wsl\\$runId", self.wrapper)

    def test_validator_and_ci_execute_prerequisite_contract(self):
        ids = {item["id"] for item in self.validators["validators"]}
        self.assertIn("firstmate-windows-wsl-prerequisite-gate", ids)
        self.assertIn("test_firstmate_windows_wsl_prerequisite_gate.py", self.workflow)
        self.assertIn("Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1", self.workflow)
        self.assertIn("-ContractOnly", self.workflow)

    def test_known_traps_capture_late_dependency_and_false_pass_failure(self):
        traps = "\n".join(self.codebase["known_traps"])
        self.assertIn("gh", traps)
        self.assertIn("before clone/test work", traps)
        self.assertIn("separately pasted PowerShell statements", traps)
        self.assertIn("success marker", traps)


if __name__ == "__main__":
    unittest.main()
