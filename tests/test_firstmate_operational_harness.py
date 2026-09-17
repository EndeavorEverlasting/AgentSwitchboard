from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
INTEGRATION = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"
CONVERGENCE = ROOT / "tooling" / "firstmate" / "harness" / "convergence-contract.json"


class FirstMateOperationalHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads((HARNESS / "manifest.json").read_text(encoding="utf-8"))
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.validators = json.loads((HARNESS / "validator-registry.json").read_text(encoding="utf-8"))
        cls.codebase = json.loads((HARNESS / "codebase-map.json").read_text(encoding="utf-8"))
        cls.integration = json.loads(INTEGRATION.read_text(encoding="utf-8"))
        cls.convergence = json.loads(CONVERGENCE.read_text(encoding="utf-8"))

    def test_required_entrypoints_exist(self) -> None:
        for path in (
            "Test-AgentSwitchboard-FirstMate-Harness.ps1",
            "Test-AgentSwitchboard-FirstMate-Harness.cmd",
            "Test-AgentSwitchboard-FirstMate-Harness.sh",
            "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1",
            "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1",
            "Invoke-FirstMatePhysicalFloorContinuation.ps1",
            "Invoke-FmWsl12AdminBoxLiveProof.ps1",
            "Invoke-Asq017AdminBoxLiveFloor.ps1",
            "tooling/firstmate/Test-FirstMateInterop.sh",
            "tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPreCommit.sh",
            "tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPrePush.sh",
            "docs/harness/firstmate-operational-harness.md",
            "docs/harness/firstmate-wsl-physical-floor-runbook.md",
        ):
            self.assertTrue((ROOT / path).is_file(), path)
        self.assertEqual(
            "Invoke-FmWsl12AdminBoxLiveProof.ps1",
            self.manifest["components"]["admin_box_live_proof"],
        )
        self.assertEqual(
            "Invoke-Asq017AdminBoxLiveFloor.ps1",
            self.manifest["components"]["asq017_admin_box_live_floor"],
        )
        self.assertEqual(
            "tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPreCommit.sh",
            self.manifest["components"]["pre_commit_hook"],
        )
        self.assertEqual(
            "tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPrePush.sh",
            self.manifest["components"]["pre_push_hook"],
        )

    def test_manifest_binds_physical_floor_runbook(self) -> None:
        runbook = self.manifest["components"]["physical_floor_runbook"]
        self.assertEqual(
            "docs/harness/firstmate-wsl-physical-floor-runbook.md",
            runbook,
        )
        text = (ROOT / runbook).read_text(encoding="utf-8")
        self.assertIn("FM-WSL-12", text)
        self.assertIn("-Mode physical-floor", text)
        self.assertIn("-ExpectedHead", text)
        self.assertIn("-WslDistribution Ubuntu", text)
        self.assertIn("Invoke-FmWsl12AdminBoxLiveProof.ps1", text)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR", text)
        self.assertIn("no live firstmate crew dispatch", text.lower())
        self.assertIn("FM-CREW-13", text)
        self.assertIn("bounded repair is authorized by FM-WSL-12", text)
        self.assertIn("without stopping for additional operator permission", text)

    def test_manifest_is_bridge_only_and_firstmate_owns_runtime(self) -> None:
        self.assertEqual("firstmate-windows-wsl-bridge", self.manifest["harness_id"])
        self.assertEqual("contract-integrated-runtime-unproved", self.manifest["status"])
        routing = self.manifest["routing"]
        self.assertEqual("bridge_only", routing["windows_host"])
        self.assertEqual("Ubuntu", routing["wsl_distribution"])
        self.assertEqual("FirstMate", routing["runtime_dispatch_owner"])
        self.assertEqual("FirstMate", routing["runtime_lifecycle_owner"])
        self.assertIsNone(routing["agentswitchboard_skill"])
        self.assertIsNone(routing["agentswitchboard_capability"])
        self.assertIsNone(routing["agentswitchboard_trigger"])
        self.assertIn("do-not-revive", routing["stale_skill_disposition"])
        self.assertIn("do-not-revive", routing["stale_selector_disposition"])

    def test_stale_asb_runtime_router_is_not_reintroduced(self) -> None:
        self.assertFalse((HARNESS / "Select-FirstMateWorkflow.py").exists())
        self.assertFalse((ROOT / ".ai" / "skills" / "firstmate-crew-orchestration" / "SKILL.md").exists())
        joined = "\n".join(self.manifest["guardrails"]).lower()
        self.assertIn("no agentswitchboard child-bus adapter", joined)
        self.assertIn("firstmate crew-control skill", joined)

    def test_artifacts_are_local_untracked_and_secret_free(self) -> None:
        self.assertIs(self.artifacts["tracked"], False)
        self.assertIn("temporary directory", self.artifacts["default_root"])
        ids = {item["id"] for item in self.artifacts["artifacts"]}
        self.assertEqual(
            {
                "windows-wsl-prerequisite-proof",
                "windows-wsl-prerequisite-stderr",
                "windows-wsl-diagnostics",
                "windows-wsl-bootstrap-stdout",
                "windows-wsl-runtime-proof",
            },
            ids,
        )
        safety = self.artifacts["safety"]
        self.assertIs(safety["repository_tracking_allowed"], False)
        self.assertIs(safety["credentials_allowed"], False)
        self.assertIs(safety["provider_tokens_allowed"], False)
        self.assertIs(safety["raw_gh_auth_output_allowed"], False)

    def test_validator_registry_covers_bridge_and_prerequisite_gate(self) -> None:
        by_id = {item["id"]: item for item in self.validators["validators"]}
        for validator_id in (
            "firstmate-integration-contract",
            "firstmate-convergence-contract",
            "firstmate-operational-harness-contract",
            "firstmate-windows-harness-portability",
            "firstmate-windows-wsl-bridge-contract",
            "firstmate-windows-wsl-prerequisite-gate",
            "firstmate-windows-contract-front-door",
        ):
            self.assertIn(validator_id, by_id)
        self.assertEqual(
            "python3 tests/test_firstmate_integration_contract.py",
            by_id["firstmate-integration-contract"]["command"],
        )
        self.assertEqual(
            "linux-wsl-or-ci",
            by_id["firstmate-integration-contract"]["platform"],
        )

    def test_integration_contract_binds_operational_bridge(self) -> None:
        bridge = self.integration["windows_bridge"]
        self.assertEqual("FM-BRIDGE-10", bridge["lane"])
        self.assertEqual("contract-integrated-runtime-unproved", bridge["status"])
        self.assertEqual("Ubuntu", bridge["distribution"])
        self.assertIs(bridge["dependency_installation"], False)
        self.assertIs(bridge["credential_mutation"], False)
        self.assertEqual("FirstMate", bridge["runtime_owner_after_bridge"])

        recovery = self.integration["physical_floor_recovery"]
        self.assertEqual("FM-WSL-12", recovery["lane"])
        self.assertIs(recovery["execution_owner_may_install_missing_packages"], True)
        self.assertIs(recovery["additional_operator_confirmation_required"], False)
        self.assertEqual("Ubuntu", recovery["distribution"])
        self.assertEqual("apt-get", recovery["package_manager"])
        self.assertEqual(["git", "gh", "tmux", "python3"], recovery["package_allowlist"])
        self.assertIs(recovery["credential_mutation"], False)
        self.assertIs(recovery["github_authentication_requires_operator"], True)

        disposition = self.integration["routing_disposition"]
        self.assertIsNone(disposition["agentswitchboard_skill"])
        self.assertIsNone(disposition["agentswitchboard_capability"])
        self.assertIsNone(disposition["agentswitchboard_trigger"])

    def test_codebase_map_records_historical_failure_classes(self) -> None:
        traps = "\n".join(self.codebase["known_traps"])
        for marker in (
            "linked worktree",
            "Ubuntu",
            "CRLF",
            "empty",
            "stdout and stderr separately",
            "WSLENV /p",
            "timeout",
            "prerequisite gate",
        ):
            self.assertIn(marker.lower(), traps.lower())

    def test_proof_ceiling_stays_below_physical_and_live_crew(self) -> None:
        ceiling = self.manifest["proof_ceiling"].lower()
        self.assertIn("physical wsl", ceiling)
        self.assertIn("live", ceiling)
        self.assertIn("crew", ceiling)
        self.assertIn("fm-wsl-12", ceiling)
        self.assertIn("fm-crew-13", ceiling)


if __name__ == "__main__":
    unittest.main()
