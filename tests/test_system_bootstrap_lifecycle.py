from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIFECYCLE = ROOT / "tooling" / "harness" / "system-bootstrap-lifecycle"
OPEN_CODE = ROOT / "tooling" / "profiles" / "windows" / "Install-AgentSwitchboardOpenCode.ps1"
OPEN_CODE_CONTRACT = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup" / "native-system-bootstrap.contract.json"
UNBOOTSTRAP = ROOT / "Unbootstrap-OpenCode-SystemWide.cmd"


class SystemBootstrapLifecycleTests(unittest.TestCase):
    def test_generic_contract_registry_and_schema(self):
        contract = json.loads((LIFECYCLE / "lifecycle.contract.json").read_text(encoding="utf-8-sig"))
        registry = json.loads((LIFECYCLE / "adapters.v1.json").read_text(encoding="utf-8-sig"))
        schema = json.loads((LIFECYCLE / "lifecycle-state.schema.json").read_text(encoding="utf-8-sig"))
        self.assertEqual("agentswitchboard.system-bootstrap-lifecycle.v1", contract["contractId"])
        self.assertEqual(["Inspect", "Apply", "Remove"], contract["operations"])
        self.assertIn("fail-closed-before-rollback", contract["failureRules"]["ownedResourceDrift"])
        self.assertEqual("agentswitchboard.system-bootstrap-state.v1", schema["$id"])
        self.assertEqual("agentswitchboard.system-bootstrap-adapter-registry.v1", registry["schema"])
        self.assertEqual("tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1", registry["sharedModule"])
        adapters = {item["adapterId"]: item for item in registry["adapters"]}
        self.assertIn("opencode", adapters)
        self.assertEqual("reference-implementation", adapters["opencode"]["status"])
        self.assertEqual(["Inspect", "Apply", "Remove"], adapters["opencode"]["operations"])
        self.assertTrue(adapters["opencode"]["removeRequiresOwnershipState"])
        self.assertTrue(adapters["opencode"]["removePreservesUnrelatedSharedState"])

    def test_shared_module_owns_atomic_state_and_path_delta_helpers(self):
        text = (LIFECYCLE / "BootstrapLifecycle.psm1").read_text(encoding="utf-8-sig")
        for token in (
            "Get-ASBLifecycleRoot",
            "Get-ASBLifecycleStatePath",
            "Read-ASBLifecycleState",
            "Write-ASBLifecycleStateAtomic",
            "Archive-ASBLifecycleState",
            "Get-ASBFileSha256",
            "Add-ASBPathEntry",
            "Remove-ASBPathEntry",
            "Test-ASBDirectoryEmpty",
            "Move-Item -LiteralPath $temporary -Destination $StatePath -Force",
        ):
            self.assertIn(token, text)
        self.assertIn("[char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)", text)
        self.assertNotIn("Invoke-Expression", text)

    def test_opencode_implements_reversible_lifecycle(self):
        text = OPEN_CODE.read_text(encoding="utf-8-sig")
        for token in (
            "[ValidateSet('Inspect','Apply','Remove')]",
            "$adapterId = 'opencode'",
            "Get-ASBLifecycleRoot",
            "Get-ASBLifecycleStatePath",
            "agentswitchboard.system-bootstrap-state.v1",
            "New-OpenCodeLifecycleState",
            "Get-RemovalBlockers",
            "Restore-ManagedConfigFromState",
            "Invoke-OpenCodeRemove",
            "OPENCODE_REMOVE_OWNERSHIP_UNPROVEN",
            "OPENCODE_REMOVE_DRIFT_DETECTED",
            "OPENCODE_REMOVE_BINARY_RESTORE_FAILED",
            "OPENCODE_REMOVE_CONFIG_VERIFY_FAILED",
            "OPENCODE_POST_APPLY_REMOVE_CONTRACT_FAILED",
        ):
            self.assertIn(token, text)

    def test_remove_is_ownership_delta_not_blanket_cleanup(self):
        text = OPEN_CODE.read_text(encoding="utf-8-sig")
        self.assertIn("if ([bool]$pathState['addedByAsb']", text)
        self.assertIn("if ([bool]$binary['changedByAsb'])", text)
        self.assertIn("if ([bool]$ConfigState['lspChangedByAsb'])", text)
        self.assertIn("if ([bool]$ConfigState['schemaChangedByAsb'])", text)
        self.assertIn("$config.Remove('lsp')", text)
        self.assertIn("$config.Remove('$schema')", text)
        self.assertNotIn("Remove-Item -LiteralPath $managedDirectory -Recurse", text)
        self.assertNotIn("Remove-Item -LiteralPath $installDirectory -Recurse", text)

    def test_preexisting_binary_has_verified_backup_before_replacement(self):
        text = OPEN_CODE.read_text(encoding="utf-8-sig")
        backup = text.index("Copy-Item -LiteralPath $targetExe -Destination $backupPath -Force")
        verify = text.index("OPENCODE_LIFECYCLE_BACKUP_VERIFY_FAILED")
        replace = text.index("Move-Item -LiteralPath $incoming -Destination $targetExe -Force")
        self.assertLess(backup, replace)
        self.assertLess(verify, replace)
        self.assertIn("beforeSha256", text)
        self.assertIn("afterSha256", text)

    def test_shared_json_rollback_is_property_level_and_drift_guarded(self):
        text = OPEN_CODE.read_text(encoding="utf-8-sig")
        self.assertIn("managed-lsp-drift", text)
        self.assertIn("managed-schema-drift", text)
        self.assertIn("lspBeforePresent", text)
        self.assertIn("lspBeforeValue", text)
        self.assertIn("schemaBeforePresent", text)
        self.assertIn("schemaBeforeValue", text)
        self.assertIn("Restore-ManagedConfigFromState", text)
        self.assertNotIn("Copy-Item -LiteralPath $script:managedConfigBackup -Destination $managedJson", text)

    def test_unbootstrap_entrypoint_is_direct_and_non_git_mutating(self):
        text = UNBOOTSTRAP.read_text(encoding="utf-8-sig")
        self.assertIn("Install-AgentSwitchboardOpenCode.ps1", text)
        self.assertIn("-Mode Remove", text)
        self.assertNotIn("git reset", text.lower())
        self.assertNotIn("git clean", text.lower())
        self.assertNotIn("git checkout", text.lower())

    def test_opencode_contract_declares_remove_and_user_state_boundary(self):
        contract = json.loads(OPEN_CODE_CONTRACT.read_text(encoding="utf-8-sig"))
        self.assertEqual(2, contract["schemaVersion"])
        self.assertEqual("agentswitchboard.opencode-native-system-bootstrap.v2", contract["contractId"])
        self.assertEqual(["Inspect", "Apply", "Remove"], contract["operations"])
        self.assertTrue(contract["lifecycle"]["removeRequiresOwnershipStateForPresentResources"])
        self.assertTrue(contract["lifecycle"]["removeFailsClosedOnOwnedResourceDrift"])
        self.assertEqual("never targeted", contract["remove"]["credentials"])
        self.assertEqual("never targeted", contract["remove"]["sessions"])
        self.assertEqual("never targeted", contract["remove"]["projectState"])


if __name__ == "__main__":
    unittest.main()
