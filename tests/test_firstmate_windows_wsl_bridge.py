from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1"
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
INTEGRATION = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"


class FirstMateWindowsWslBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bridge = BRIDGE.read_text(encoding="utf-8")
        cls.manifest = json.loads((HARNESS / "manifest.json").read_text(encoding="utf-8"))
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.validators = json.loads((HARNESS / "validator-registry.json").read_text(encoding="utf-8"))
        cls.integration = json.loads(INTEGRATION.read_text(encoding="utf-8"))

    def test_bridge_is_registered(self) -> None:
        self.assertEqual(
            "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1",
            self.manifest["components"]["windows_wsl_bridge"],
        )
        ids = {item["id"] for item in self.artifacts["artifacts"]}
        self.assertIn("windows-wsl-runtime-proof", ids)
        validator_ids = {item["id"] for item in self.validators["validators"]}
        self.assertIn("firstmate-windows-wsl-bridge-contract", validator_ids)

    def test_bridge_pins_explicit_ubuntu(self) -> None:
        self.assertEqual("Ubuntu", self.integration["platform_contract"]["wsl_distribution"])
        self.assertIn("platform_contract.wsl_distribution", self.bridge)
        self.assertIn("--distribution", self.bridge)
        self.assertIn("$Distribution", self.bridge)
        self.assertIn("WSL_DISTRO_NAME=$WslDistribution", self.bridge)
        self.assertNotIn("wsl.exe --exec bash", self.bridge)

    def test_bridge_normalizes_crlf_before_bash_transport(self) -> None:
        self.assertIn("function ConvertTo-Lf", self.bridge)
        self.assertIn('.Replace("`r`n", "`n").Replace("`r", "`n")', self.bridge)
        self.assertIn("ConvertTo-Lf -Text $Command", self.bridge)
        self.assertIn("CRLF normalization contract failed", self.bridge)

    def test_bridge_accepts_empty_native_streams(self) -> None:
        self.assertIn("[AllowNull()][AllowEmptyString()][string]$Text", self.bridge)
        self.assertIn("function Normalize-WslText", self.bridge)
        self.assertIn("function Add-WslDiagnostic", self.bridge)
        self.assertIn("Empty native stream normalization contract failed", self.bridge)

    def test_bridge_bounds_every_wsl_process(self) -> None:
        self.assertIn("[int]$WslTimeoutSeconds = 120", self.bridge)
        self.assertIn("WaitForExit($TimeoutSeconds * 1000)", self.bridge)
        self.assertIn("ExitCode = if ($timedOut) { 124 }", self.bridge)
        self.assertIn("TIMEOUT: wsl.exe exceeded", self.bridge)

    def test_bridge_uses_wslenv_path_translation_without_wslpath_execution(self) -> None:
        lowered = self.bridge.lower()
        for execution_form in (
            "get-command wslpath",
            "& wslpath",
            "wslpath.exe",
            "command -v wslpath",
            "$(wslpath",
        ):
            self.assertNotIn(execution_form, lowered)
        self.assertIn("WSLENV", self.bridge)
        self.assertIn('"$stringName/p"', self.bridge)
        self.assertIn("ASB_SOURCE_REPO", self.bridge)
        self.assertIn("-PathEnvironmentNames @('ASB_SOURCE_REPO')", self.bridge)

    def test_bridge_replaces_inherited_wslenv_mode_for_owned_variables(self) -> None:
        self.assertIn("Replace any inherited mode for variables this bridge owns", self.bridge)
        self.assertIn("$entryName -ine $stringName", self.bridge)
        self.assertIn("([string]$_ -split '/', 2)[0]", self.bridge)
        self.assertIn('$wslEnvEntries += "$stringName/p"', self.bridge)
        self.assertLess(
            self.bridge.index("$entryName -ine $stringName"),
            self.bridge.index('$wslEnvEntries += "$stringName/p"'),
        )

    def test_bridge_creates_wsl_owned_standalone_exact_head_clone(self) -> None:
        self.assertIn("rev-parse --path-format=absolute --git-common-dir", self.bridge)
        self.assertIn("git clone --quiet --no-hardlinks --no-checkout", self.bridge)
        self.assertIn('checkout --quiet --detach "$ASB_EXPECTED_HEAD"', self.bridge)
        self.assertIn("/tmp/agentswitchboard-firstmate-", self.bridge)
        self.assertIn("WSL-owned standalone clone", self.bridge)
        self.assertIn("STATUS=BLOCKED_HEAD_MISMATCH", self.bridge)
        self.assertIn("NEXT=ff-only refresh main, re-resolve HEAD, and rerun with the recorded SHA", self.bridge)
        self.assertNotIn('throw "Exact-head mismatch', self.bridge)
        self.assertIn("STATUS=BLOCKED_WINDOWS_WSL_REQUIRED", self.bridge)
        self.assertIn("exit 46", self.bridge)
        self.assertNotIn("throw 'WSL is unavailable", self.bridge)

    def test_bridge_preserves_separate_diagnostics_and_unique_evidence(self) -> None:
        self.assertIn("Get-Date -Format 'yyyyMMdd-HHmmss'", self.bridge)
        self.assertIn("[guid]::NewGuid()", self.bridge)
        self.assertIn("wsl-stderr.log", self.bridge)
        self.assertIn("wsl-bootstrap-stdout.txt", self.bridge)
        self.assertIn("stdout and stderr remain separate", self.bridge)

    def test_script_owned_wsl_workspace_is_cleaned_by_default(self) -> None:
        self.assertIn("function Complete-WslWorkspace", self.bridge)
        self.assertIn("[switch]$PreserveWslWorkspaceOnFailure", self.bridge)
        self.assertIn("^/tmp/agentswitchboard-firstmate-[0-9a-fA-F-]+$", self.bridge)
        self.assertIn('rm -rf -- "$ASB_WSL_WORKSPACE"', self.bridge)
        self.assertIn("WSL_WORKSPACE_CLEANED", self.bridge)
        self.assertIn("WSL_WORKSPACE_PRESERVED", self.bridge)
        self.assertIn("-PreserveOnFailure:$PreserveWslWorkspaceOnFailure", self.bridge)
        success_cleanup = self.bridge.rindex("Complete-WslWorkspace -Distribution")
        pass_marker = self.bridge.index("FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR")
        self.assertLess(success_cleanup, pass_marker)

    def test_bridge_runs_contract_before_read_only_probe(self) -> None:
        contract_index = self.bridge.index("Test-AgentSwitchboard-FirstMate-Harness.sh contract")
        probe_index = self.bridge.index("Test-FirstMateInterop.sh")
        self.assertLess(contract_index, probe_index)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR", self.bridge)
        self.assertIn("no FirstMate crew task was dispatched", self.bridge)

    def test_bridge_does_not_reintroduce_asb_runtime_routing(self) -> None:
        self.assertNotIn("Select-FirstMateWorkflow.py", self.bridge)
        self.assertNotIn("firstmate-route.json", self.bridge)
        self.assertNotIn("yolo_enabled", self.bridge)

    def test_bridge_does_not_install_or_mutate_credentials(self) -> None:
        lowered = self.bridge.lower()
        for forbidden in (
            "apt-get install",
            "apt install",
            "gh auth login",
            "npm install",
            "pip install",
            "git push",
            "gh pr create",
        ):
            self.assertNotIn(forbidden, lowered)


if __name__ == "__main__":
    unittest.main()
