from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "tooling" / "profiles" / "windows" / "Install-AgentSwitchboardOpenCode.ps1"
SETUP = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
DISPATCH = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"
ENTRY = ROOT / "Bootstrap-OpenCode-SystemWide.cmd"
CONTRACT = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup" / "native-system-bootstrap.contract.json"
DOC = ROOT / "docs" / "harness" / "opencode-native-system-bootstrap.md"


class OpenCodeNativeSystemBootstrapTests(unittest.TestCase):
    def test_owned_files_exist_and_contract_parses(self):
        for path in (BOOTSTRAP, SETUP, DISPATCH, ENTRY, CONTRACT, DOC):
            self.assertTrue(path.is_file(), str(path.relative_to(ROOT)))
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(1, contract["schemaVersion"])
        self.assertEqual("tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1", contract["owner"])
        self.assertEqual([], contract["preflight"]["packageManagersAssumed"])
        self.assertFalse(contract["preflight"]["userScopedNodeOrNpmRequired"])
        self.assertTrue(contract["powershellSafety"]["implementationMustRunAsWholeScript"])
        self.assertFalse(contract["powershellSafety"]["interactiveFragmentExecutionAllowed"])

    def test_bootstrap_ascertains_prerequisites_before_mutation(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        lower = text.lower()
        for token in (
            "test-iselevated",
            "is64bitoperatingsystem",
            "processor_architecture",
            "administrator_required",
            "read-managedconfig",
            "releases/latest",
            "opencode-windows-x64.zip",
            "asset.digest",
            "get-filehash",
            "sha256",
        ):
            self.assertIn(token, lower)
        first_mutation = text.index("$null = New-Item -ItemType Directory -Path $installDirectory -Force")
        self.assertLess(text.index("$managed = Read-ManagedConfig"), first_mutation)
        self.assertLess(text.index("$assetDigest = [string]$asset.digest"), first_mutation)
        self.assertLess(text.index("$actualSha256 = (Get-FileHash"), first_mutation)

    def test_bootstrap_is_machine_wide_and_not_package_manager_backed(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        lower = text.lower()
        self.assertIn("join-path $env:programfiles 'opencode'", lower)
        self.assertIn("join-path $env:programdata 'opencode'", lower)
        self.assertIn("setenvironmentvariable('path'", lower)
        self.assertIn("'machine'", lower)
        for forbidden in (
            "choco install",
            "scoop install",
            "npm install",
            "winget install",
            "invoke-expression",
            "iex ",
            "appdata\\npm",
            "familyrecipes",
        ):
            self.assertNotIn(forbidden, lower)

    def test_managed_lsp_config_preserves_unrelated_json_and_fails_closed_on_jsonc(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        lower = text.lower()
        self.assertIn("opencode.jsonc", lower)
        self.assertIn("opencode_managed_jsonc_present", lower)
        self.assertIn("convertfrom-json -ashashtable", lower)
        self.assertIn("$managed['lsp'] = $true", text)
        self.assertIn("opencode.managed.before.json", lower)
        self.assertIn("opencode_managed_lsp_failed", lower)
        self.assertNotIn("$managed = [ordered]@{'$schema'", text)

    def test_native_bootstrap_is_reachable_through_agentswitchboard_dispatch(self):
        setup = SETUP.read_text(encoding="utf-8")
        dispatch = DISPATCH.read_text(encoding="utf-8")
        entry = ENTRY.read_text(encoding="utf-8")
        self.assertIn("'bootstrap-opencode'", setup)
        self.assertIn("Install-AgentSwitchboardOpenCode.ps1", setup)
        self.assertIn("& $nativeBootstrapPath -Mode Apply", setup)
        self.assertIn('"bootstrap-opencode"', dispatch)
        self.assertIn('bootstrap-opencode "%ROOT%." "%GIT_REF%"', entry)
        self.assertIn("Do not paste implementation fragments into an interactive PowerShell REPL", entry)
        self.assertNotIn("pwsh.exe -Command", entry)
        self.assertNotIn("powershell.exe -Command", entry)

    def test_receipt_distinguishes_configuration_from_active_lsp_proof(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        doc = DOC.read_text(encoding="utf-8").lower()
        self.assertIn("active language-server behavior", text.lower())
        self.assertIn("lsp=true", doc)
        self.assertIn("does not prove", doc)
        self.assertIn("supported source file", doc)

    def test_apply_requires_sha_and_direct_readback(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("OPENCODE_ASSET_SHA256_MISSING", text)
        self.assertIn("OPENCODE_ASSET_SHA256_MISMATCH", text)
        self.assertIn("$script:finalVersion = Get-OpenCodeVersion -Path $targetExe", text)
        self.assertIn("OPENCODE_MACHINE_PATH_FAILED", text)
        self.assertIn("OPENCODE_MANAGED_LSP_FAILED", text)
        self.assertIn("Normalize-OpenCodeVersion", text)
        self.assertIn("debug', 'config'", text)
        self.assertIn("OPENCODE_LSP_NOT_RESOLVED", text)

    def test_bootstrap_opencode_tolerates_dirty_checkout_without_git_rewrite(self):
        dispatch = DISPATCH.read_text(encoding="utf-8")
        self.assertIn("Skipping fetch/pull for bootstrap-opencode", dispatch)
        self.assertIn('if /I "%MODE%"=="bootstrap-opencode"', dispatch)
        self.assertIn("Machine mutation does not rewrite Git state", dispatch)
        # Non-bootstrap modes must still fail closed on dirty trees.
        self.assertIn("The checkout contains local changes.", dispatch)
        self.assertIn("set \"RESULT=13\"", dispatch)


if __name__ == "__main__":
    unittest.main()
