from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHYSICAL = ROOT / "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1"
BRIDGE = ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1"
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
INTEGRATION = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"


class FirstMateWindowsWslPrerequisiteGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.physical = PHYSICAL.read_text(encoding="utf-8")
        cls.bridge = BRIDGE.read_text(encoding="utf-8")
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.integration = json.loads(INTEGRATION.read_text(encoding="utf-8"))

    def test_prerequisite_gate_is_registered_and_uses_explicit_distribution(self) -> None:
        ids = {item["id"] for item in self.artifacts["artifacts"]}
        self.assertIn("windows-wsl-prerequisite-proof", ids)
        self.assertIn("windows-wsl-prerequisite-stderr", ids)
        self.assertEqual("Ubuntu", self.integration["platform_contract"]["wsl_distribution"])
        self.assertIn("--distribution", self.physical)
        self.assertIn("$WslDistribution", self.physical)

    def test_gate_checks_required_tools_and_github_auth(self) -> None:
        for tool in ("git", "gh", "tmux", "python3"):
            self.assertIn(tool, self.physical)
        self.assertIn("gh auth status --hostname github.com", self.physical)
        self.assertIn("STATUS=BLOCKED_MISSING_TOOLS", self.physical)
        self.assertIn("STATUS=BLOCKED_GITHUB_AUTH", self.physical)
        self.assertIn("STATUS=PASS", self.physical)

    def test_gate_reports_recovery_but_does_not_execute_it(self) -> None:
        self.assertIn("NEXT_ACTION=sudo apt-get update && sudo apt-get install -y", self.physical)
        self.assertIn("NEXT_ACTION=gh auth login --hostname github.com --git-protocol https --web", self.physical)
        self.assertNotIn("& sudo", self.physical)
        self.assertNotIn("Start-Process sudo", self.physical)
        self.assertNotIn("gh auth login --hostname github.com --git-protocol https --web'", self.physical)
        self.assertIs(self.integration["windows_bridge"]["dependency_installation"], False)
        self.assertIs(self.integration["windows_bridge"]["credential_mutation"], False)

    def test_gate_is_bounded_and_uses_unique_evidence(self) -> None:
        self.assertIn("[int]$PrerequisiteTimeoutSeconds = 60", self.physical)
        self.assertIn("WaitForExit($TimeoutSeconds * 1000)", self.physical)
        self.assertIn("ExitCode = if ($timedOut) { 124 }", self.physical)
        self.assertIn("Get-Date -Format 'yyyyMMdd-HHmmss'", self.physical)
        self.assertIn("[guid]::NewGuid()", self.physical)
        self.assertIn("firstmate-wsl-prerequisites.txt", self.physical)
        self.assertIn("firstmate-wsl-prerequisites-stderr.log", self.physical)

    def test_gate_propagates_lower_bridge_failure(self) -> None:
        self.assertIn("Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1", self.physical)
        self.assertIn("bridge-stdout.txt", self.physical)
        self.assertIn("bridge-stderr.txt", self.physical)
        self.assertIn("FirstMate lower bridge failed", self.physical)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR", self.physical)

    def test_contract_only_does_not_require_live_wsl(self) -> None:
        contract_index = self.physical.index("if ($ContractOnly)")
        wsl_index = self.physical.index("Get-Command wsl.exe")
        self.assertLess(contract_index, wsl_index)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_PREREQUISITE_GATE_CONTRACT", self.physical)

    def test_no_automatic_dependency_or_credential_mutation(self) -> None:
        lowered = self.physical.lower()
        for forbidden in (
            "invoke-webrequest",
            "choco install",
            "winget install",
            "wsl --install",
            "npm install",
            "pip install",
            "set-content ~/.config/gh",
        ):
            self.assertNotIn(forbidden, lowered)


if __name__ == "__main__":
    unittest.main()
