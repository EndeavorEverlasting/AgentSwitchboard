import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "agent-fleet-readiness"

REQUIRED = [
    HARNESS / "codebase-map.json",
    HARNESS / "artifact-registry.json",
    HARNESS / "workflows" / "pick-up-agent-task.workflow.json",
    HARNESS / "workflows" / "bootstrap-or-list-readiness.workflow.json",
    HARNESS / "workflows" / "prove-readiness-through-powershell.workflow.json",
    HARNESS / "workflows" / "core-autoconfig-defer-hermes.workflow.json",
    HARNESS / "workflows" / "handle-readiness-failure.workflow.json",
    HARNESS / "workflows" / "handoff-agent-task.workflow.json",
    HARNESS / "fixtures" / "readiness-state-cases.json",
    HARNESS / "operator-report.template.md",
    HARNESS / "hooks" / "pre-push.ps1",
    ROOT / ".ai" / "skills" / "agent-fleet-readiness" / "SKILL.md",
    ROOT / "docs" / "harness" / "agent-fleet-readiness.md",
    ROOT / "scripts" / "Test-AgentFleetReadinessHarnessCompleteness.ps1",
    ROOT / "tests" / "test_agent_fleet_readiness_harness.py",
    ROOT / ".github" / "workflows" / "agent-fleet-readiness-harness.yml",
]


class AgentFleetReadinessHarnessTests(unittest.TestCase):
    def read_json(self, path):
        return json.loads(path.read_text(encoding="utf-8"))

    def test_all_components_exist(self):
        missing = [str(path.relative_to(ROOT)) for path in REQUIRED if not path.is_file()]
        self.assertEqual([], missing)

    def test_json_contracts_parse(self):
        for path in [
            HARNESS / "codebase-map.json",
            HARNESS / "artifact-registry.json",
            HARNESS / "fixtures" / "readiness-state-cases.json",
            *sorted((HARNESS / "workflows").glob("*.json")),
        ]:
            with self.subTest(path=path.name):
                self.assertIsInstance(self.read_json(path), dict)

    def test_map_covers_path_shell_hermes_and_cmd_shim_traps(self):
        data = self.read_json(HARNESS / "codebase-map.json")
        traps = "\n".join(data["knownTraps"])
        for token in [
            "tmux/WezTerm/WSL",
            "stale hard-coded repository paths",
            "irm are not CMD commands",
            "Hermes is optional for core autoconfig",
            "-SkipHermesInstall",
            "Access is denied",
            "exit 5",
            "cmd-shim-blocked",
            "Start-AgentSwitchboard.ps1",
            "clean-checkout",
        ]:
            self.assertIn(token, traps)
        self.assertEqual("Setup-AgentSwitchboard.cmd", data["entrypoints"]["rootSetupLauncher"])
        self.assertIn(
            "prove-readiness-through-powershell.workflow.json",
            data["entrypoints"]["readinessProofWorkflow"],
        )

    def test_registry_uses_powershell_operator_authority(self):
        data = self.read_json(HARNESS / "artifact-registry.json")
        artifacts = {item["artifactId"]: item for item in data["artifacts"]}
        self.assertIn("installed-operator-implementation", artifacts)
        self.assertTrue(
            artifacts["installed-operator-implementation"]["pathPattern"].endswith(
                r"\Start-AgentSwitchboard.ps1"
            )
        )
        self.assertIn("installed-operator-launcher", artifacts)
        self.assertTrue(
            artifacts["installed-operator-launcher"]["pathPattern"].endswith(
                r"\agent-switchboard.cmd"
            )
        )
        states = {item["state"]: item for item in data["stateGates"]}
        self.assertIn("cmd-shim-blocked", states)
        self.assertEqual(
            "prove-readiness-through-powershell",
            states["cmd-shim-blocked"]["nextWorkflow"],
        )
        compatibility = data["compatibilitySurfaces"][0]
        self.assertEqual("cmd-shim-blocked", compatibility["blockedClass"])
        self.assertIn("exit 5", compatibility["blockedSignals"])

    def test_registry_has_deferred_hermes_state(self):
        data = self.read_json(HARNESS / "artifact-registry.json")
        states = {item["state"] for item in data["stateGates"]}
        self.assertTrue(
            {
                "not-bootstrapped",
                "partial-or-inconsistent",
                "cmd-shim-blocked",
                "core-ready-hermes-deferred",
                "installed-unclassified",
                "adapter-ready",
            }.issubset(states)
        )
        hermes = next(
            item for item in data["optionalDependencies"] if item["name"] == "Hermes"
        )
        self.assertEqual("-SkipHermesInstall", hermes["setupFlag"])
        self.assertEqual("TBD", hermes["deferredLabel"])

    def test_state_fixtures_cover_observed_regressions(self):
        data = self.read_json(HARNESS / "fixtures" / "readiness-state-cases.json")
        cases = {case["name"]: case for case in data["cases"]}
        self.assertEqual(
            "bootstrap-or-repair", cases["not-bootstrapped"]["expectedNextAction"]
        )
        self.assertEqual(
            "repository-path-invalid",
            cases["stale-repository-path"]["expectedClassification"],
        )
        self.assertEqual(
            "shell-command-mismatch",
            cases["powershell-command-pasted-into-cmd"]["expectedClassification"],
        )
        self.assertEqual(
            "cmd-shim-blocked",
            cases["cmd-shim-access-denied-powershell-ready"]["expectedClassification"],
        )
        self.assertEqual(
            "prove-readiness-through-powershell",
            cases["cmd-shim-access-denied-powershell-ready"]["expectedNextAction"],
        )
        self.assertEqual(
            "core-ready-hermes-deferred",
            cases["hermes-unavailable-core-autoconfig"]["expectedClassification"],
        )
        self.assertEqual(
            "TBD", cases["hermes-unavailable-core-autoconfig"]["hermesLabel"]
        )
        self.assertEqual(
            "prove-readiness-through-powershell",
            cases["hermes-unavailable-core-autoconfig"]["expectedNextAction"],
        )

    def test_readiness_proof_workflow_bypasses_blocked_cmd_shim(self):
        data = self.read_json(
            HARNESS / "workflows" / "prove-readiness-through-powershell.workflow.json"
        )
        text = json.dumps(data)
        self.assertEqual("prove-readiness-through-powershell", data["workflowId"])
        for token in [
            "Start-AgentSwitchboard.ps1",
            "Access is denied",
            "exit 5",
            "cmd-shim-blocked",
            "-ListAgents",
            "startup-readiness-json",
        ]:
            self.assertIn(token, text)
        self.assertIn("Do not retry the shim", text)

    def test_bootstrap_workflow_does_not_require_cmd_shim(self):
        data = self.read_json(
            HARNESS / "workflows" / "bootstrap-or-list-readiness.workflow.json"
        )
        text = json.dumps(data)
        self.assertIn("installed Start-AgentSwitchboard.ps1 exists", text)
        self.assertIn("The CMD shim is observed separately", text)
        self.assertIn("cmd-shim-blocked", text)
        self.assertIn("prove-readiness-through-powershell", text)

    def test_core_autoconfig_workflow_never_blocks_on_hermes(self):
        data = self.read_json(
            HARNESS / "workflows" / "core-autoconfig-defer-hermes.workflow.json"
        )
        text = json.dumps(data)
        self.assertIn("-SkipHermesInstall", text)
        self.assertIn("TBD/deferred", text)
        self.assertIn("Do not manually install Hermes", text)
        self.assertIn("state.json exists", text)

    def test_existing_product_already_supports_nonblocking_hermes(self):
        setup = (
            ROOT / "tooling" / "gnhf" / "Setup-AgentSwitchboard.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("[switch]$SkipHermesInstall", setup)
        self.assertIn(
            "Core fleet setup will continue and Hermes will be recorded as BLOCKED", setup
        )
        self.assertIn(
            'Add-SetupStep -Name "hermes-install" -Status "skipped"', setup
        )

    def test_existing_product_installs_powershell_readiness_implementation(self):
        installer = (
            ROOT / "tooling" / "gnhf" / "Install-AgentSwitchboardGnhf.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn('"Start-AgentSwitchboard.ps1"', installer)
        operator = (
            ROOT / "tooling" / "gnhf" / "Start-AgentSwitchboard.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("[switch]$ListAgents", operator)
        self.assertIn("Show-AgentReadiness -State $state", operator)

    def test_workflows_have_proof_ceilings(self):
        for path in sorted((HARNESS / "workflows").glob("*.json")):
            data = self.read_json(path)
            with self.subTest(path=path.name):
                self.assertTrue(data.get("workflowId"))
                self.assertTrue(data.get("proofCeiling"))

    def test_skill_contains_nonblocking_and_cmd_recovery_contracts(self):
        text = (
            ROOT / ".ai" / "skills" / "agent-fleet-readiness" / "SKILL.md"
        ).read_text(encoding="utf-8")
        for token in [
            "status: experimental",
            "version: 1.2.0",
            "Resolve the repository root before Git or setup",
            "irm is a PowerShell alias, not a CMD command",
            "Treat the PowerShell implementation as the installed readiness authority",
            "Access is denied",
            "cmd-shim-blocked",
            "prove-readiness-through-powershell",
            "Prefer non-blocking core autoconfig when Hermes is not the priority",
            "-SkipHermesInstall",
            "TBD/deferred",
            "No repeated CMD-shim retry",
            "No manual Hermes installation or repeated Hermes retry",
        ]:
            self.assertIn(token, text)

    def test_operator_guide_names_exact_failure_classes(self):
        text = (
            ROOT / "docs" / "harness" / "agent-fleet-readiness.md"
        ).read_text(encoding="utf-8")
        for token in [
            "stale hard-coded repository path",
            "PowerShell-only `irm ... | iex`",
            "repository-path-invalid",
            "shell-command-mismatch",
            "cmd-shim-blocked",
            "Access is denied",
            "exit 5",
            "prove-readiness-through-powershell",
            "core-ready-hermes-deferred",
            "Do not collapse these into a generic “agent failed.”",
        ]:
            self.assertIn(token, text)

    def test_existing_product_surfaces_are_referenced_not_replaced(self):
        for relative in [
            "Setup-AgentSwitchboard.cmd",
            "AgentSwitchboard.cmd",
            "tooling/gnhf/Setup-AgentSwitchboard.ps1",
            "tooling/gnhf/Install-AgentSwitchboardGnhf.ps1",
            "tooling/gnhf/Start-AgentSwitchboard.ps1",
            "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1",
            "tooling/gnhf/Test-GnhfFleetContracts.ps1",
            "tooling/gnhf/Test-HermesSetupContracts.ps1",
        ]:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_task_launch_uses_installed_powershell_implementation(self):
        data = self.read_json(HARNESS / "workflows" / "pick-up-agent-task.workflow.json")
        text = json.dumps(data)
        self.assertIn("Start-AgentSwitchboard.ps1", text)
        self.assertIn("cmd-shim-blocked", text)
        self.assertIn("never make it required", text)

    def test_handoff_preserves_cmd_shim_boundary(self):
        data = self.read_json(HARNESS / "workflows" / "handoff-agent-task.workflow.json")
        text = json.dumps(data)
        self.assertIn("Access is denied", text)
        self.assertIn("exit 5", text)
        self.assertIn("prove-readiness-through-powershell", text)
        self.assertIn("do not retry the shim", text)

    def test_no_private_machine_paths_or_secrets_in_harness(self):
        forbidden = [
            "Cheeks" + "McClappeth",
            "pa_" + "rperez26",
            "BEGIN PRIVATE " + "KEY",
            "ghp" + "_",
            "sk" + "-",
        ]
        for path in REQUIRED:
            if path.suffix.lower() not in {".json", ".md", ".ps1", ".py", ".yml"}:
                continue
            text = path.read_text(encoding="utf-8")
            for token in forbidden:
                with self.subTest(path=path.name, token=token):
                    self.assertNotIn(token, text)


if __name__ == "__main__":
    unittest.main()
