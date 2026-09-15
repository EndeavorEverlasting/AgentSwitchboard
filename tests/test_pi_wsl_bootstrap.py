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
        self.assertIn("bootstrap pin", versions["nvmMeaning"])
        self.assertEqual("24.21.0", versions["node"])
        self.assertEqual("0.85.1", versions["pi"])
        self.assertEqual("@earendil-works/pi-coding-agent", versions["npmPackage"])
        self.assertEqual("Ubuntu", self.contract["target"]["wslDistribution"])
        self.assertTrue(self.contract["target"]["linuxUserOwned"])
        self.assertEqual(
            "preserve-clean-functional-checkout",
            self.contract["boundedMutation"]["existingNvmPolicy"],
        )

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
            "__pi_package__@__pi_version__",
            "pi_wsl_bootstrap=pass",
            "pi_wsl_inspect=ready",
            "pi_wsl_inspect=drift",
        ):
            self.assertIn(token, lower)
        self.assertIn(".Replace(([char]0).ToString(), [string]::Empty)", self.installer)
        self.assertIn("@'", self.installer)
        self.assertIn('export NVM_DIR="$HOME/.nvm"', self.installer)
        self.assertNotIn("/mnt/c/Users/", self.installer)

    def test_inspect_ready_requires_nvm_owned_pinned_node_and_pi(self) -> None:
        self.assertIn("nvm --version", self.installer)
        self.assertIn("__NODE_VERSION__", self.installer)
        self.assertIn("__PI_VERSION__", self.installer)
        self.assertIn("$HOME/.nvm/versions/node/", self.installer)
        self.assertNotIn("__NVM_VERSION_PLAIN__", self.installer)

    def test_noninteractive_wsl_work_is_bounded_but_pi_tui_is_interactive(self) -> None:
        timeouts = self.contract["timeouts"]
        self.assertEqual(120, timeouts["inspectSeconds"])
        self.assertEqual(1800, timeouts["applySeconds"])
        self.assertFalse(timeouts["interactivePiTuiBounded"])
        self.assertIn("WaitForExit($TimeoutSeconds * 1000)", self.installer)
        self.assertIn("$process.Kill($true)", self.installer)
        self.assertIn("STATUS=BLOCKED_WSL_TIMEOUT", self.installer)
        self.assertIn("-Interactive", self.installer)

    def test_package_mutation_is_bounded_to_contract_allowlist(self) -> None:
        bounded = self.contract["boundedMutation"]
        self.assertEqual(["git", "curl", "ca-certificates"], bounded["ubuntuAptPackages"])
        self.assertFalse(bounded["windowsPackageManagerMutation"])
        self.assertFalse(bounded["wslDistributionInstallOrRemoval"])
        self.assertFalse(bounded["credentialMutation"])
        self.assertFalse(bounded["providerSelectionMutation"])
        self.assertFalse(bounded["authFileMutation"])
        self.assertIn("dpkg-query -W -f='${Status}' ca-certificates", self.installer)
        self.assertIn("sudo apt-get install -y __APT_PACKAGES__", self.installer)
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

    def test_nvm_is_preservation_first_and_shell_init_is_complete(self) -> None:
        self.assertIn("STATUS=BLOCKED_NVM_ROOT_OWNERSHIP", self.installer)
        self.assertIn("STATUS=BLOCKED_NVM_DIRTY", self.installer)
        self.assertIn("STATUS=BLOCKED_NVM_UNUSABLE", self.installer)
        self.assertIn("status --porcelain=v1", self.installer)
        self.assertIn("git clone --branch '__NVM_VERSION__' --depth 1", self.installer)
        self.assertIn("Preserving existing clean functional NVM checkout", self.installer)
        self.assertNotIn("git -C \"$NVM_DIR\" checkout", self.installer)
        self.assertNotIn("git -C \"$NVM_DIR\" fetch", self.installer)
        self.assertNotIn("git reset", self.installer.lower())
        self.assertNotIn("git clean", self.installer.lower())
        self.assertIn("ensure_bashrc_line", self.installer)
        self.assertIn('export NVM_DIR="$HOME/.nvm"', self.installer)
        self.assertIn('[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"', self.installer)
        self.assertIn('[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"', self.installer)

    def test_proof_ceiling_does_not_promote_manual_screenshot_to_cmd_field_proof(self) -> None:
        ceiling = self.contract["proofCeiling"].lower()
        self.assertIn("one manual", ceiling)
        self.assertIn("not this new cmd on another workstation", ceiling)
        self.assertIn("provider authentication remains user-owned", ceiling)


if __name__ == "__main__":
    unittest.main()
