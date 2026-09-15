from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PI = ROOT / "tooling" / "pi"
HARNESS = PI / "harness"
ENTRY = ROOT / "Bootstrap-Pi-WSL.cmd"
INSTALLER = PI / "Install-AgentSwitchboardPiWsl.ps1"
SETUP = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
DISPATCH = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"
DOC = ROOT / "docs" / "harness" / "pi-wsl-workstation-bootstrap.md"
CONTRACT = HARNESS / "wsl-user-bootstrap.contract.json"
NATIVE_ENTRY = ROOT / "Bootstrap-Pi-SystemWide.cmd"
NATIVE_INSTALLER = PI / "Install-AgentSwitchboardPiSystem.ps1"


class PiWslBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(CONTRACT.read_text(encoding="utf-8-sig"))
        cls.entry = ENTRY.read_text(encoding="utf-8-sig")
        cls.installer = INSTALLER.read_text(encoding="utf-8-sig")
        cls.setup = SETUP.read_text(encoding="utf-8-sig")
        cls.dispatch = DISPATCH.read_text(encoding="utf-8-sig")
        cls.docs = DOC.read_text(encoding="utf-8-sig")

    def test_owned_surfaces_exist_without_replacing_native_bootstrap(self) -> None:
        for path in (ENTRY, INSTALLER, CONTRACT, DOC, NATIVE_ENTRY, NATIVE_INSTALLER):
            self.assertTrue(path.is_file(), str(path.relative_to(ROOT)))
        self.assertTrue(self.contract["target"]["nativeWindowsPiUnchanged"])
        self.assertNotEqual(ENTRY, NATIVE_ENTRY)
        self.assertNotEqual(INSTALLER, NATIVE_INSTALLER)

    def test_one_click_entry_mirrors_canonical_dispatcher_contract(self) -> None:
        for token in (
            'set "ROOT=%~dp0"',
            'set "GIT_REF=%~1"',
            'if not defined GIT_REF set "GIT_REF=main"',
            'if not exist "%ROOT%Pull-And-Run-AgentSwitchboard.cmd"',
            'where pwsh.exe',
            'Do not paste implementation fragments into an interactive PowerShell REPL',
            'call "%ROOT%Pull-And-Run-AgentSwitchboard.cmd" bootstrap-pi-wsl "%ROOT%." "%GIT_REF%"',
            'exit /b %RESULT%',
        ):
            self.assertIn(token, self.entry)
        self.assertNotIn("pwsh.exe -Command", self.entry)
        self.assertIn('"bootstrap-pi-wsl"', self.dispatch)
        self.assertIn("bootstrap-pi-wsl", self.setup)
        self.assertIn("Install-AgentSwitchboardPiWsl.ps1", self.setup)
        self.assertIn("-Mode Apply -Distribution $Distribution", self.setup)

    def test_contract_pins_observed_working_linux_stack(self) -> None:
        versions = self.contract["versions"]
        self.assertEqual("v0.40.7", versions["nvm"])
        self.assertEqual("24.21.0", versions["node"])
        self.assertEqual("0.85.1", versions["pi"])
        self.assertEqual("@earendil-works/pi-coding-agent", versions["npmPackage"])
        self.assertEqual("Ubuntu", self.contract["target"]["wslDistribution"])
        self.assertTrue(self.contract["target"]["linuxUserOwned"])

    def test_installer_is_linux_native_and_rejects_windows_path_leak(self) -> None:
        lower = self.installer.lower()
        for token in (
            "wsl.exe",
            "--distribution",
            "bash",
            "-lc",
            "status=blocked_windows_path_leak",
            "$home/.nvm/versions/node/",
            "npm install -g --ignore-scripts",
            "@earendil-works/pi-coding-agent",
            "pi_wsl_bootstrap=pass",
            "pi_wsl_inspect=ready",
        ):
            self.assertIn(token, lower)
        self.assertIn(".Replace(([char]0).ToString(), [string]::Empty)", self.installer)
        self.assertIn("@'", self.installer)
        self.assertIn('export NVM_DIR="$HOME/.nvm"', self.installer)
        self.assertNotIn("/mnt/c/Users/", self.installer)

    def test_package_mutation_is_bounded_to_contract_allowlist(self) -> None:
        bounded = self.contract["boundedMutation"]
        self.assertEqual(["git", "curl", "ca-certificates"], bounded["ubuntuAptPackages"])
        self.assertFalse(bounded["windowsPackageManagerMutation"])
        self.assertFalse(bounded["wslDistributionInstallOrRemoval"])
        self.assertFalse(bounded["credentialMutation"])
        self.assertFalse(bounded["providerSelectionMutation"])
        self.assertFalse(bounded["authFileMutation"])
        for forbidden in ("winget install", "choco install", "scoop install", "wsl --install"):
            self.assertNotIn(forbidden, self.installer.lower())

    def test_authentication_remains_user_owned(self) -> None:
        lower = self.installer.lower()
        self.assertIn("provider authentication is per-user", lower)
        self.assertIn("run /login", lower)
        self.assertIn("exec pi", lower)
        for forbidden in ("auth.json", "api_key", "api-key", "openai_api_key", "gh auth login"):
            self.assertNotIn(forbidden, lower)
        self.assertIn("does **not** choose a provider", self.docs)
        self.assertIn("/login", self.docs)

    def test_nvm_is_preservation_first_and_shell_init_is_literal(self) -> None:
        self.assertIn("STATUS=BLOCKED_NVM_ROOT_OWNERSHIP", self.installer)
        self.assertIn("STATUS=BLOCKED_NVM_DIRTY", self.installer)
        self.assertIn("status --porcelain=v1", self.installer)
        self.assertNotIn("git reset", self.installer.lower())
        self.assertNotIn("git clean", self.installer.lower())
        self.assertIn("<<'ASB_NVM'", self.installer)
        self.assertIn('export NVM_DIR="$HOME/.nvm"', self.installer)

    def test_proof_ceiling_does_not_promote_manual_screenshot_to_cmd_field_proof(self) -> None:
        ceiling = self.contract["proofCeiling"].lower()
        self.assertIn("one manual", ceiling)
        self.assertIn("not this new cmd on another workstation", ceiling)
        self.assertIn("provider authentication remains user-owned", ceiling)


if __name__ == "__main__":
    unittest.main()
