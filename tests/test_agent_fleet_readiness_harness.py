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
        json_paths = [
            HARNESS / "codebase-map.json",
            HARNESS / "artifact-registry.json",
            HARNESS / "fixtures" / "readiness-state-cases.json",
            *sorted((HARNESS / "workflows").glob("*.json")),
        ]
        for path in json_paths:
            with self.subTest(path=path.name):
                self.assertIsInstance(self.read_json(path), dict)

    def test_map_routes_bootstrap_before_post_setup_launcher(self):
        data = self.read_json(HARNESS / "codebase-map.json")
        traps = "\n".join(data["knownTraps"])
        self.assertIn("post-setup launcher", traps)
        self.assertIn("state.json", traps)
        self.assertIn("tmux/WezTerm/WSL", traps)
        self.assertIn("clean-checkout", traps)
        self.assertEqual("Setup-AgentSwitchboard.cmd", data["entrypoints"]["rootSetupLauncher"])
        self.assertEqual("AgentSwitchboard.cmd", data["entrypoints"]["rootOperatorLauncher"])

    def test_registry_has_installed_state_and_evidence(self):
        data = self.read_json(HARNESS / "artifact-registry.json")
        ids = {item["artifactId"] for item in data["artifacts"]}
        expected = {
            "fleet-state",
            "installed-operator-launcher",
            "setup-summary",
            "setup-transcript",
            "startup-readiness-json",
            "startup-readiness-markdown",
            "provider-route-proof",
        }
        self.assertTrue(expected.issubset(ids))
        states = {item["state"] for item in data["stateGates"]}
        self.assertTrue({"not-bootstrapped", "partial-or-inconsistent", "installed-unclassified", "adapter-ready"}.issubset(states))

    def test_state_fixtures_prevent_the_regression(self):
        data = self.read_json(HARNESS / "fixtures" / "readiness-state-cases.json")
        cases = {case["name"]: case for case in data["cases"]}
        self.assertEqual("bootstrap-or-repair", cases["not-bootstrapped"]["expectedNextAction"])
        self.assertEqual("-ListAgents", cases["not-bootstrapped"]["mustNotSuggest"])
        self.assertEqual("partial-or-inconsistent", cases["partial-state-only"]["expectedClassification"])
        self.assertEqual("partial-or-inconsistent", cases["partial-launcher-only"]["expectedClassification"])
        self.assertEqual("list-readiness", cases["installed-unclassified"]["expectedNextAction"])
        self.assertEqual("hosted-response-proven", cases["adapter-ready-provider-unproved"]["mustNotClaim"])

    def test_workflows_have_proof_ceilings(self):
        for path in sorted((HARNESS / "workflows").glob("*.json")):
            data = self.read_json(path)
            with self.subTest(path=path.name):
                self.assertTrue(data.get("workflowId"))
                self.assertTrue(data.get("proofCeiling"))

    def test_skill_contains_state_gate_and_provider_boundaries(self):
        text = (ROOT / ".ai" / "skills" / "agent-fleet-readiness" / "SKILL.md").read_text(encoding="utf-8")
        for token in [
            "Separate terminal readiness from fleet readiness",
            "Inspect both installed-state surfaces before post-setup commands",
            "not-bootstrapped",
            "partial-or-inconsistent",
            "List readiness before selecting an agent",
            "Keep provider proof separate",
            "Require an explicit task prompt outside AgentSwitchboard",
            "No post-setup launcher command before installed-state classification",
        ]:
            self.assertIn(token, text)

    def test_operator_guide_names_exact_failure_class(self):
        text = (ROOT / "docs" / "harness" / "agent-fleet-readiness.md").read_text(encoding="utf-8")
        self.assertIn("post-setup `agent-switchboard.cmd -ListAgents` command being recommended before", text)
        self.assertIn("not an agent failure", text)
        self.assertIn("two separate operator floors", text)

    def test_existing_product_surfaces_are_referenced_not_replaced(self):
        for relative in [
            "Setup-AgentSwitchboard.cmd",
            "AgentSwitchboard.cmd",
            "tooling/gnhf/Setup-AgentSwitchboard.ps1",
            "tooling/gnhf/Start-AgentSwitchboard.ps1",
            "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1",
            "tooling/gnhf/Test-GnhfFleetContracts.ps1",
        ]:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_no_private_machine_paths_or_secrets_in_harness(self):
        forbidden = [
            "CheeksMcClappeth",
            "pa_rperez26",
            "BEGIN PRIVATE KEY",
            "ghp_",
            "sk-",
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
