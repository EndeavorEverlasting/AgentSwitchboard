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
        for path in [HARNESS / "codebase-map.json", HARNESS / "artifact-registry.json", HARNESS / "fixtures" / "readiness-state-cases.json", *sorted((HARNESS / "workflows").glob("*.json"))]:
            with self.subTest(path=path.name):
                self.assertIsInstance(self.read_json(path), dict)

    def test_map_covers_path_shell_and_optional_hermes_traps(self):
        data = self.read_json(HARNESS / "codebase-map.json")
        traps = "\n".join(data["knownTraps"])
        for token in ["post-setup launcher", "tmux/WezTerm/WSL", "stale hard-coded repository paths", "irm are not CMD commands", "Hermes is optional for core autoconfig", "-SkipHermesInstall", "clean-checkout"]:
            self.assertIn(token, traps)
        self.assertEqual("Setup-AgentSwitchboard.cmd", data["entrypoints"]["rootSetupLauncher"])
        self.assertIn("core-autoconfig-defer-hermes.workflow.json", data["entrypoints"]["coreAutoconfigWorkflow"])

    def test_registry_has_deferred_hermes_state(self):
        data = self.read_json(HARNESS / "artifact-registry.json")
        ids = {item["artifactId"] for item in data["artifacts"]}
        self.assertTrue({"fleet-state", "installed-operator-launcher", "setup-summary", "setup-transcript", "startup-readiness-json", "startup-readiness-markdown", "provider-route-proof"}.issubset(ids))
        states = {item["state"] for item in data["stateGates"]}
        self.assertTrue({"not-bootstrapped", "partial-or-inconsistent", "core-ready-hermes-deferred", "installed-unclassified", "adapter-ready"}.issubset(states))
        hermes = next(item for item in data["optionalDependencies"] if item["name"] == "Hermes")
        self.assertEqual("-SkipHermesInstall", hermes["setupFlag"])
        self.assertEqual("TBD", hermes["deferredLabel"])

    def test_state_fixtures_cover_observed_regressions(self):
        data = self.read_json(HARNESS / "fixtures" / "readiness-state-cases.json")
        cases = {case["name"]: case for case in data["cases"]}
        self.assertEqual("bootstrap-or-repair", cases["not-bootstrapped"]["expectedNextAction"])
        self.assertEqual("repository-path-invalid", cases["stale-repository-path"]["expectedClassification"])
        self.assertEqual("shell-command-mismatch", cases["powershell-command-pasted-into-cmd"]["expectedClassification"])
        self.assertEqual("core-ready-hermes-deferred", cases["hermes-unavailable-core-autoconfig"]["expectedClassification"])
        self.assertEqual("TBD", cases["hermes-unavailable-core-autoconfig"]["hermesLabel"])
        self.assertEqual("list-readiness", cases["hermes-unavailable-core-autoconfig"]["expectedNextAction"])

    def test_core_autoconfig_workflow_never_blocks_on_hermes(self):
        data = self.read_json(HARNESS / "workflows" / "core-autoconfig-defer-hermes.workflow.json")
        text = json.dumps(data)
        self.assertIn("-SkipHermesInstall", text)
        self.assertIn("TBD/deferred", text)
        self.assertIn("Do not manually install Hermes", text)
        self.assertIn("state.json exists", text)
        self.assertIn("agent-switchboard.cmd exists", text)

    def test_existing_product_already_supports_nonblocking_hermes(self):
        setup = (ROOT / "tooling" / "gnhf" / "Setup-AgentSwitchboard.ps1").read_text(encoding="utf-8")
        self.assertIn("[switch]$SkipHermesInstall", setup)
        self.assertIn("Core fleet setup will continue and Hermes will be recorded as BLOCKED", setup)
        self.assertIn('Add-SetupStep -Name "hermes-install" -Status "skipped"', setup)

    def test_workflows_have_proof_ceilings(self):
        for path in sorted((HARNESS / "workflows").glob("*.json")):
            data = self.read_json(path)
            with self.subTest(path=path.name):
                self.assertTrue(data.get("workflowId"))
                self.assertTrue(data.get("proofCeiling"))

    def test_skill_contains_nonblocking_core_autoconfig(self):
        text = (ROOT / ".ai" / "skills" / "agent-fleet-readiness" / "SKILL.md").read_text(encoding="utf-8")
        for token in ["status: experimental", "Resolve the repository root before Git or setup", "irm is a PowerShell alias, not a CMD command", "Prefer non-blocking core autoconfig when Hermes is not the priority", "-SkipHermesInstall", "TBD/deferred", "No manual Hermes installation or repeated Hermes retry"]:
            self.assertIn(token, text)

    def test_operator_guide_names_exact_failure_classes(self):
        text = (ROOT / "docs" / "harness" / "agent-fleet-readiness.md").read_text(encoding="utf-8")
        for token in ["stale hard-coded repository path", "PowerShell-only `irm ... | iex`", "repository-path-invalid", "shell-command-mismatch", "hermes-deferred", "core-ready-hermes-deferred", "Do not collapse these into a generic “agent failed.”"]:
            self.assertIn(token, text)

    def test_existing_product_surfaces_are_referenced_not_replaced(self):
        for relative in ["Setup-AgentSwitchboard.cmd", "AgentSwitchboard.cmd", "tooling/gnhf/Setup-AgentSwitchboard.ps1", "tooling/gnhf/Start-AgentSwitchboard.ps1", "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1", "tooling/gnhf/Test-GnhfFleetContracts.ps1", "tooling/gnhf/Test-HermesSetupContracts.ps1"]:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_no_private_machine_paths_or_secrets_in_harness(self):
        forbidden = ["Cheeks" + "McClappeth", "pa_" + "rperez26", "BEGIN PRIVATE " + "KEY", "ghp" + "_", "sk" + "-"]
        for path in REQUIRED:
            if path.suffix.lower() not in {".json", ".md", ".ps1", ".py", ".yml"}:
                continue
            text = path.read_text(encoding="utf-8")
            for token in forbidden:
                with self.subTest(path=path.name, token=token):
                    self.assertNotIn(token, text)


if __name__ == "__main__":
    unittest.main()
