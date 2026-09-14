from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PS1 = ROOT / "Test-AgentSwitchboard-FirstMate-Harness.ps1"
CMD = ROOT / "Test-AgentSwitchboard-FirstMate-Harness.cmd"


class FirstMateWindowsHarnessPortabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ps1 = PS1.read_text(encoding="utf-8")
        cls.cmd = CMD.read_text(encoding="utf-8")

    def test_windows_front_door_resolves_current_python_interpreter(self) -> None:
        self.assertIn("Get-Command python.exe", self.ps1)
        self.assertIn("Get-Command python", self.ps1)
        self.assertIn("& $Python.Source $test", self.ps1)
        self.assertNotIn("& python3", self.ps1)
        self.assertNotIn("python3 tests/", self.ps1)

    def test_windows_contract_does_not_spawn_bare_bash(self) -> None:
        self.assertNotIn("Get-Command bash", self.ps1)
        self.assertNotIn("& bash", self.ps1)
        self.assertNotIn("bash -lc", self.ps1)
        self.assertIn("Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1", self.ps1)
        self.assertIn("Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1", self.ps1)

    def test_runtime_mode_delegates_to_physical_floor(self) -> None:
        self.assertIn(
            "[ValidateSet('contract', 'physical-floor', 'physical-floor-continue')]",
            self.ps1,
        )
        self.assertIn("'physical-floor'", self.ps1)
        self.assertIn("'physical-floor-continue'", self.ps1)
        self.assertIn("Invoke-FirstMatePhysicalFloorContinuation.ps1", self.ps1)
        self.assertIn("-WslDistribution", self.ps1)
        self.assertIn("WINDOWS_ROLE=bridge-only", self.ps1)
        self.assertIn("RUNTIME_OWNER=FirstMate", self.ps1)

    def test_contract_mode_runs_windows_safe_contracts_only(self) -> None:
        self.assertIn("-ContractOnly", self.ps1)
        self.assertIn("FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS", self.ps1)
        for test_name in (
            "test_firstmate_asb_convergence_contract.py",
            "test_firstmate_operational_harness.py",
            "test_firstmate_windows_harness_portability.py",
            "test_firstmate_windows_wsl_bridge.py",
            "test_firstmate_windows_wsl_prerequisite_gate.py",
        ):
            self.assertIn(test_name, self.ps1)
        self.assertNotIn("'tests/test_firstmate_integration_contract.py'", self.ps1)
        self.assertIn("belongs to Linux CI", self.ps1)

    def test_cmd_wrapper_is_location_independent_and_preserves_exit(self) -> None:
        self.assertIn("%~dp0", self.cmd)
        self.assertIn("where pwsh.exe", self.cmd)
        self.assertIn("%ERRORLEVEL%", self.cmd)
        self.assertIn("exit /b %EXITCODE%", self.cmd)

    def test_cmd_wrapper_respects_host_execution_policy(self) -> None:
        self.assertNotIn("ExecutionPolicy", self.cmd)
        self.assertNotIn("Bypass", self.cmd)
        self.assertIn('pwsh.exe -NoLogo -NoProfile -File "%ENTRY%" %*', self.cmd)


if __name__ == "__main__":
    unittest.main()
