from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "tooling" / "profiles" / "windows" / "Install-AgentSwitchboardOpenCode.ps1"
SETUP = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
DISPATCH = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"
ENTRY = ROOT / "Bootstrap-OpenCode-SystemWide.cmd"
UNBOOTSTRAP = ROOT / "Unbootstrap-OpenCode-SystemWide.cmd"
CONTRACT = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup" / "native-system-bootstrap.contract.json"
LIFECYCLE = ROOT / "tooling" / "harness" / "system-bootstrap-lifecycle" / "lifecycle.contract.json"
DOC = ROOT / "docs" / "harness" / "opencode-native-system-bootstrap.md"


class OpenCodeNativeSystemBootstrapTests(unittest.TestCase):
    def test_owned_files_exist_and_contract_parses(self):
        for path in (BOOTSTRAP, SETUP, DISPATCH, ENTRY, UNBOOTSTRAP, CONTRACT, LIFECYCLE, DOC):
            self.assertTrue(path.is_file(), str(path.relative_to(ROOT)))
        contract = json.loads(CONTRACT.read_text(encoding="utf-8-sig"))
        self.assertEqual(2, contract["schemaVersion"])
        self.assertEqual("agentswitchboard.opencode-native-system-bootstrap.v2", contract["contractId"])
        self.assertEqual("tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1", contract["owner"])
        self.assertEqual(["Inspect", "Apply", "Remove"], contract["operations"])
        self.assertEqual([], contract["preflight"]["packageManagersAssumed"])
        self.assertFalse(contract["preflight"]["userScopedNodeOrNpmRequired"])
        self.assertTrue(contract["powershellSafety"]["implementationMustRunAsWholeScript"])
        self.assertFalse(contract["powershellSafety"]["interactiveFragmentExecutionAllowed"])
        lifecycle = contract["lifecycle"]
        self.assertTrue(lifecycle["applyUsesPerResourceWriteAheadIntent"])
        self.assertTrue(lifecycle["reapplyRejectsOwnedStateDrift"])
        self.assertTrue(lifecycle["removeCheckpointsEachResourceRollback"])
        self.assertTrue(lifecycle["interruptedRemoveIsResumable"])
        proof = contract["proof"]
        self.assertTrue(proof["inspectReportsOwnershipAndRemoveReadiness"])
        self.assertTrue(proof["applyRequiresManagedLspReadback"])
        self.assertTrue(proof["applyRequiresResolvedLspDebugConfig"])
        self.assertTrue(proof["applyRequiresImmediateRemoveReadiness"])
        self.assertTrue(proof["applyRejectsPreviouslyOwnedDrift"])
        self.assertTrue(proof["removeRequiresPreflightDriftCheckBeforeRollback"])
        self.assertTrue(proof["removeRequiresRollbackVerification"])
        self.assertTrue(proof["removePersistsPerResourceRollbackCompletion"])
        self.assertTrue(proof["versionComparisonIgnoresLeadingV"])
        self.assertTrue(proof["dirtyCheckoutStillAllowsBootstrapOpencode"])
        self.assertTrue(proof["activeLspProofRequiresRuntimeObservation"])

    def test_bootstrap_ascertains_prerequisites_before_machine_payload_mutation(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
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
            "get-asblifecyclestatepath",
        ):
            self.assertIn(token, lower)
        first_payload_mutation = text.index("$null = New-Item -ItemType Directory -Path $installDirectory -Force")
        self.assertLess(text.index("$managed = Read-ManagedConfig"), first_payload_mutation)
        self.assertLess(text.index("$assetDigest = [string]$asset.digest"), first_payload_mutation)
        self.assertLess(text.index("$actualSha256 = (Get-FileHash"), first_payload_mutation)
        self.assertLess(text.index("Save-LifecycleState -State $state"), first_payload_mutation)

    def test_bootstrap_is_machine_wide_and_not_package_manager_backed(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        lower = text.lower()
        self.assertIn("join-path $env:programfiles 'opencode'", lower)
        self.assertIn("join-path $env:programdata 'opencode'", lower)
        self.assertIn("setenvironmentvariable('path'", lower)
        self.assertIn("'machine'", lower)
        self.assertIn("bootstrap-lifecycle", lower)
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
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        lower = text.lower()
        self.assertIn("opencode.jsonc", lower)
        self.assertIn("opencode_managed_jsonc_present", lower)
        self.assertIn("convertfrom-json -ashashtable", lower)
        self.assertIn("$managed['lsp'] = $true", text)
        self.assertIn("opencode.managed.before.json", lower)
        self.assertIn("opencode_managed_lsp_failed", lower)
        self.assertIn("restore-managedconfigfromstate", lower)
        self.assertIn("$config.remove('lsp')", lower)
        self.assertNotIn("remove-item -literalpath $manageddirectory -recurse", lower)

    def test_remove_without_state_treats_jsonc_as_present_and_unowned(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        start = text.index("function Invoke-OpenCodeRemove")
        gate = text.index("OPENCODE_REMOVE_OWNERSHIP_UNPROVEN", start)
        preflight = text[start:gate]
        self.assertIn("Test-Path -LiteralPath $managedJsonc -PathType Leaf", preflight)
        self.assertIn("Test-Path -LiteralPath $managedJson -PathType Leaf", preflight)

    def test_native_bootstrap_is_reachable_and_unbootstrap_is_direct(self):
        setup = SETUP.read_text(encoding="utf-8-sig")
        dispatch = DISPATCH.read_text(encoding="utf-8-sig")
        entry = ENTRY.read_text(encoding="utf-8-sig")
        unbootstrap = UNBOOTSTRAP.read_text(encoding="utf-8-sig")
        self.assertIn("'bootstrap-opencode'", setup)
        self.assertIn("Install-AgentSwitchboardOpenCode.ps1", setup)
        self.assertIn("& $nativeBootstrapPath -Mode Apply", setup)
        self.assertIn('"bootstrap-opencode"', dispatch)
        self.assertIn('bootstrap-opencode "%ROOT%." "%GIT_REF%"', entry)
        self.assertIn("Unbootstrap-OpenCode-SystemWide.cmd", entry)
        self.assertIn("Do not paste implementation fragments into an interactive PowerShell REPL", entry)
        self.assertIn("Install-AgentSwitchboardOpenCode.ps1", unbootstrap)
        self.assertIn("-Mode Remove", unbootstrap)
        self.assertNotIn("pwsh.exe -Command", entry)
        self.assertNotIn("powershell.exe -Command", entry)
        self.assertNotIn("git reset", unbootstrap.lower())
        self.assertNotIn("git clean", unbootstrap.lower())

    def test_receipt_distinguishes_config_runtime_and_lifecycle_proof(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        doc = DOC.read_text(encoding="utf-8-sig").lower()
        self.assertIn("active language-server behavior", text.lower())
        self.assertIn("OPENCODE_NATIVE_BOOTSTRAP_LSP_ENABLED=", text)
        self.assertIn("OPENCODE_NATIVE_BOOTSTRAP_LSP_RESOLVED=", text)
        self.assertIn("OPENCODE_NATIVE_BOOTSTRAP_LSP_PROBE=", text)
        self.assertIn("OPENCODE_NATIVE_BOOTSTRAP_LIFECYCLE_STATE=", text)
        self.assertIn("OPENCODE_NATIVE_BOOTSTRAP_REMOVE_READY=", text)
        self.assertIn("lsp=true", doc)
        self.assertIn("does not prove", doc)
        self.assertIn("supported source file", doc)
        self.assertIn("opencode debug config", doc)
        self.assertIn("dirty checkout", doc)
        self.assertIn("unbootstrap-opencode-systemwide.cmd", doc)
        self.assertIn("programdata", doc)

    def test_apply_requires_sha_direct_readback_and_immediate_remove_readiness(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        self.assertIn("OPENCODE_ASSET_SHA256_MISSING", text)
        self.assertIn("OPENCODE_ASSET_SHA256_MISMATCH", text)
        self.assertIn("$script:finalVersion = Get-OpenCodeVersion -Path $targetExe", text)
        self.assertIn("OPENCODE_MACHINE_PATH_FAILED", text)
        self.assertIn("OPENCODE_MANAGED_LSP_FAILED", text)
        self.assertIn("Normalize-OpenCodeVersion", text)
        self.assertIn("debug', 'config'", text)
        self.assertIn("OPENCODE_LSP_RESOLVE_PROBE_FAILED", text)
        self.assertIn("OPENCODE_LSP_NOT_RESOLVED", text)
        self.assertIn("OPENCODE_POST_APPLY_REMOVE_CONTRACT_FAILED", text)
        self.assertIn("$resolved['lsp'] -eq $false", text)
        self.assertIn("ClearEnvironmentVariables", text)
        self.assertIn("OPENCODE_CONFIG_CONTENT", text)
        self.assertIn("OPENCODE_CONFIG_DIR", text)

    def test_remove_requires_ownership_and_drift_preflight(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        for token in (
            "OPENCODE_REMOVE_OWNERSHIP_UNPROVEN",
            "Get-RemovalBlockers",
            "OPENCODE_REMOVE_DRIFT_DETECTED",
            "binary-drift",
            "binary-backup-drift",
            "managed-lsp-drift",
            "managed-schema-drift",
            "OPENCODE_REMOVE_BINARY_RESTORE_FAILED",
            "OPENCODE_REMOVE_CONFIG_VERIFY_FAILED",
        ):
            self.assertIn(token, text)
        drift_index = text.index("$blockers = @(Get-RemovalBlockers -State $state)")
        removing_index = text.index("$state['status'] = 'removing'")
        self.assertLess(drift_index, removing_index)

    def test_remove_only_reverses_asb_owned_deltas(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        self.assertIn("if ([bool]$pathState['addedByAsb']", text)
        self.assertIn("[bool]$binary['changedByAsb']", text)
        self.assertIn("if ([bool]$ConfigState['lspChangedByAsb'])", text)
        self.assertIn("if ([bool]$ConfigState['schemaChangedByAsb'])", text)
        self.assertNotIn("Remove-Item -LiteralPath $installDirectory -Recurse", text)
        self.assertNotIn("Remove-Item -LiteralPath $managedDirectory -Recurse", text)

    def test_bootstrap_opencode_tolerates_dirty_checkout_without_git_rewrite(self):
        dispatch = DISPATCH.read_text(encoding="utf-8-sig")
        self.assertIn("Skipping fetch/pull for bootstrap-opencode", dispatch)
        self.assertIn('if /I "%MODE%"=="bootstrap-opencode"', dispatch)
        self.assertIn("Machine mutation does not rewrite Git state", dispatch)
        self.assertIn("The checkout contains local changes.", dispatch)
        self.assertIn("set \"RESULT=13\"", dispatch)


if __name__ == "__main__":
    unittest.main()
