import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1"
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"


class FirstMateWindowsWslBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bridge = BRIDGE.read_text(encoding="utf-8")
        cls.manifest = json.loads((HARNESS / "manifest.json").read_text(encoding="utf-8"))
        cls.codebase = json.loads((HARNESS / "codebase-map.json").read_text(encoding="utf-8"))
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.validators = json.loads((HARNESS / "validator-registry.json").read_text(encoding="utf-8"))
        cls.report_builder = (HARNESS / "Build-FirstMateHarnessReport.py").read_text(encoding="utf-8")

    def test_bridge_is_registered_everywhere(self):
        self.assertEqual(
            self.manifest["components"]["windows_wsl_bridge"],
            "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1",
        )
        self.assertIn("windows_wsl_bridge", self.codebase["entrypoints"])
        self.assertIn("windows-wsl-runtime-proof", {item["id"] for item in self.artifacts["artifacts"]})
        self.assertIn(
            "firstmate-windows-wsl-bridge-contract",
            {item["id"] for item in self.validators["validators"]},
        )

    def test_bridge_does_not_depend_on_wslpath(self):
        self.assertNotIn("wslpath", self.bridge.lower())
        self.assertIn("ProcessStartInfo", self.bridge)
        self.assertIn("WorkingDirectory", self.bridge)
        self.assertIn("RedirectStandardOutput = $true", self.bridge)
        self.assertIn("RedirectStandardError = $true", self.bridge)
        self.assertIn("ReadToEndAsync", self.bridge)

    def test_bridge_verifies_same_exact_head_inside_wsl(self):
        self.assertIn("git rev-parse HEAD", self.bridge)
        self.assertIn("WSL did not resolve the same AgentSwitchboard HEAD", self.bridge)
        self.assertIn("Exact-head mismatch", self.bridge)

    def test_bridge_preserves_wsl_stderr_as_diagnostic_evidence(self):
        self.assertIn("wsl-stderr.log", self.bridge)
        self.assertIn("WSL stderr is isolated from machine-readable stdout", self.bridge)
        self.assertIn("Add-WslDiagnostic", self.bridge)

    def test_bridge_runs_owning_contract_before_live_floor(self):
        contract_index = self.bridge.index("Test-AgentSwitchboard-FirstMate-Harness.sh contract")
        probe_index = self.bridge.index("Test-FirstMateInterop.sh")
        self.assertLess(contract_index, probe_index)

    def test_bridge_resolves_and_prints_canonical_artifacts(self):
        for filename in (
            "firstmate-harness-report.md",
            "firstmate-floor.txt",
            "firstmate-route.json",
            "wsl-stderr.log",
        ):
            self.assertIn(filename, self.bridge)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR", self.bridge)

    def test_report_builder_supports_stdout_transport(self):
        self.assertIn('parser.add_argument("--stdout"', self.report_builder)
        self.assertIn('parser.error("--stdout and --output are mutually exclusive")', self.report_builder)

    def test_known_trap_records_observed_transport_failure_class(self):
        traps = "\n".join(self.codebase["known_traps"])
        self.assertIn("Windows temporary paths", traps)
        self.assertIn("capture stdout/stderr separately", traps)
        self.assertIn("WSL configuration warning", traps)


if __name__ == "__main__":
    unittest.main()
