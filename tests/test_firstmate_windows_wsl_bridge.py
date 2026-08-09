import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1"
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
INTEGRATION = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"


class FirstMateWindowsWslBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bridge = BRIDGE.read_text(encoding="utf-8")
        cls.manifest = json.loads((HARNESS / "manifest.json").read_text(encoding="utf-8"))
        cls.codebase = json.loads((HARNESS / "codebase-map.json").read_text(encoding="utf-8"))
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.validators = json.loads((HARNESS / "validator-registry.json").read_text(encoding="utf-8"))
        cls.integration = json.loads(INTEGRATION.read_text(encoding="utf-8"))
        cls.report_builder = (HARNESS / "Build-FirstMateHarnessReport.py").read_text(encoding="utf-8")

    def test_bridge_is_registered_everywhere(self):
        self.assertEqual(
            self.manifest["components"]["windows_wsl_bridge"],
            "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1",
        )
        self.assertIn("windows_wsl_bridge", self.codebase["entrypoints"])
        ids = {item["id"] for item in self.artifacts["artifacts"]}
        self.assertIn("windows-wsl-runtime-proof", ids)
        self.assertIn("windows-wsl-diagnostics", ids)
        self.assertIn(
            "firstmate-windows-wsl-bridge-contract",
            {item["id"] for item in self.validators["validators"]},
        )

    def test_bridge_uses_wslenv_path_translation_not_wslpath(self):
        self.assertNotIn("wslpath", self.bridge.lower())
        self.assertIn("WSLENV", self.bridge)
        self.assertIn('"$stringName/p"', self.bridge)
        self.assertIn("ASB_SOURCE_REPO", self.bridge)
        self.assertIn("-PathEnvironmentNames @('ASB_SOURCE_REPO')", self.bridge)
        self.assertIn("RedirectStandardOutput = $true", self.bridge)
        self.assertIn("RedirectStandardError = $true", self.bridge)
        self.assertIn("ReadToEndAsync", self.bridge)

    def test_bridge_does_not_use_windows_linked_worktree_as_linux_git_checkout(self):
        self.assertIn("rev-parse --path-format=absolute --git-common-dir", self.bridge)
        self.assertIn("git clone --quiet --no-hardlinks --no-checkout", self.bridge)
        self.assertIn('checkout --quiet --detach "$ASB_EXPECTED_HEAD"', self.bridge)
        self.assertIn("/tmp/agentswitchboard-firstmate-", self.bridge)
        self.assertIn("WSL-owned standalone clone", self.bridge)
        self.assertIn("$psi.WorkingDirectory = $env:SystemRoot", self.bridge)

    def test_bridge_pins_canonical_ubuntu_instead_of_default_distro(self):
        self.assertEqual(self.integration["platform_contract"]["wsl_distribution"], "Ubuntu")
        self.assertIn("platform_contract.wsl_distribution", self.bridge)
        self.assertIn("$psi.ArgumentList.Add('-d')", self.bridge)
        self.assertIn("$psi.ArgumentList.Add($Distribution)", self.bridge)
        self.assertIn("WSL_DISTRO_NAME=$WslDistribution", self.bridge)
        self.assertIn("Canonical WSL distribution", self.bridge)

    def test_bridge_bounds_every_wsl_subprocess(self):
        self.assertIn("[int]$WslTimeoutSeconds = 120", self.bridge)
        self.assertIn("WaitForExit($TimeoutSeconds * 1000)", self.bridge)
        self.assertIn("ExitCode = if ($timedOut) { 124 }", self.bridge)
        self.assertIn("TIMEOUT: wsl.exe exceeded", self.bridge)

    def test_bridge_has_explicit_repo_owned_repair_path(self):
        self.assertIn("RepairWslIfNeeded", self.bridge)
        self.assertIn("Repair-Technician-WSL-Ubuntu.cmd", self.bridge)
        self.assertIn("AGENT_SWITCHBOARD_NO_PAUSE", self.bridge)
        self.assertIn("required Windows reboot boundary", self.bridge)

    def test_bridge_uses_unique_evidence_directory_per_attempt(self):
        self.assertIn("Get-Date -Format 'yyyyMMdd-HHmmss'", self.bridge)
        self.assertIn("[guid]::NewGuid()", self.bridge)
        self.assertIn("firstmate-windows-wsl", self.bridge)

    def test_bridge_verifies_same_exact_head_inside_wsl(self):
        self.assertIn("git rev-parse HEAD", self.bridge)
        self.assertIn("standalone clone did not prove the canonical distribution and expected AgentSwitchboard HEAD", self.bridge)
        self.assertIn("Exact-head mismatch", self.bridge)

    def test_bridge_preserves_wsl_stderr_and_workspace_as_evidence(self):
        self.assertIn("wsl-stderr.log", self.bridge)
        self.assertIn("WSL stdout and stderr remain separate", self.bridge)
        self.assertIn("Add-WslDiagnostic", self.bridge)
        self.assertIn("WSL_WORKSPACE_PRESERVED", self.bridge)
        self.assertIn("wsl-bootstrap-stdout.txt", self.bridge)
        self.assertIn("ubuntu-preflight-initial", self.bridge)

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

    def test_bridge_requires_yolo_off_on_ready_route(self):
        self.assertIn("$routeObject.yolo_enabled -ne $false", self.bridge)

    def test_report_builder_supports_stdout_transport(self):
        self.assertIn('parser.add_argument("--stdout"', self.report_builder)
        self.assertIn('parser.error("--stdout and --output are mutually exclusive")', self.report_builder)

    def test_known_trap_records_all_observed_windows_wsl_failure_classes(self):
        traps = "\n".join(self.codebase["known_traps"])
        self.assertIn("Windows temporary paths", traps)
        self.assertIn("capture stdout/stderr separately", traps)
        self.assertIn("WSL configuration warning", traps)
        self.assertIn("Windows-created linked worktree", traps)
        self.assertIn("WSLENV /p", traps)
        self.assertIn("standalone clone", traps)
        self.assertIn("default WSL distribution", traps)
        self.assertIn("Ubuntu", traps)


if __name__ == "__main__":
    unittest.main()
