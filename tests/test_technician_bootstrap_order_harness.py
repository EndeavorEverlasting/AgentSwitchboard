from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "technician-ready"
REGISTRY = HARNESS / "harness.registry.json"
ARTIFACTS = HARNESS / "artifact-registry.json"
ROUTING = HARNESS / "skill-routing.registry.json"
CODEBASE_MAP = HARNESS / "codebase-map.json"
SKILL = ROOT / ".ai" / "skills" / "technician-bootstrap-order-validation" / "SKILL.md"
CI = ROOT / ".github" / "workflows" / "technician-bootstrap-order.yml"
HOOK = ROOT / "tooling" / "profiles" / "windows" / "hooks" / "Invoke-TechnicianBootstrapOrderPreCommit.ps1"
STATUS = ROOT / "tooling" / "profiles" / "windows" / "Get-TechnicianBootstrapOrderHarnessStatus.ps1"
VALIDATOR = ROOT / "scripts" / "Test-TechnicianBootstrapOrderHarnessCompleteness.ps1"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class TechnicianBootstrapOrderHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = load(REGISTRY)
        self.artifacts = load(ARTIFACTS)
        self.routing = load(ROUTING)
        self.map = load(CODEBASE_MAP)

    def test_registered_component_files_exist(self) -> None:
        missing = [path for path in self.registry["requiredPaths"] if not (ROOT / path).is_file()]
        self.assertEqual([], missing)

    def test_machine_readable_harness_files_parse(self) -> None:
        json_paths = [ROOT / path for path in self.registry["requiredPaths"] if path.endswith(".json")]
        for path in json_paths:
            with self.subTest(path=path):
                self.assertIsInstance(load(path), dict)

    def test_workflows_are_routed_and_unique(self) -> None:
        expected = self.registry["workflowIds"]
        routes = [route["workflowId"] for route in self.routing["routes"]]
        self.assertEqual(len(expected), len(set(expected)))
        self.assertEqual(set(expected), set(routes))
        actual = {load(path)["workflowId"] for path in (HARNESS / "workflows").glob("*.workflow.json")}
        self.assertEqual(set(expected), actual)

    def test_artifacts_are_local_and_untracked(self) -> None:
        self.assertFalse(self.artifacts["tracked"])
        self.assertIn("%LOCALAPPDATA%", self.artifacts["defaultRunRoot"])
        ids = [item["artifactId"] for item in self.artifacts["artifacts"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("bootstrap-order-harness-validation", ids)
        self.assertIn("bootstrap-order-harness-status-markdown", ids)

    def test_refactor_coupling_is_explicit(self) -> None:
        coupling = self.registry["refactorCoupling"]
        self.assertEqual("source-anchor-contract-and-validator-coupled", coupling["policy"])
        self.assertIn("Technician-AgentSwitchboard-Ready.cmd", coupling["ownerPaths"])
        self.assertIn("bootstrap-order.contract.json", coupling["coupledPaths"][0])
        self.assertIn("must update the contract and affected validators in the same change", coupling["rule"])
        self.assertIn("may not be weakened", coupling["rule"])

    def test_skill_preserves_gate_integrity_and_handoff(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        for token in ("repair-failure", "validate-change", "handoff", "Never weaken", "Proof ceiling"):
            self.assertIn(token, text)

    def test_ci_runs_new_and_existing_floor(self) -> None:
        text = CI.read_text(encoding="utf-8")
        for token in (
            "tests.test_technician_bootstrap_order_harness",
            "Test-TechnicianBootstrapOrderHarnessCompleteness.ps1",
            "Get-TechnicianBootstrapOrderHarnessStatus.ps1",
            "tests.test_technician_bootstrap_order",
            "Test-TechnicianBootstrapOrder.ps1",
            "tests.test_technician_agentswitchboard_ready",
            "git diff --check",
        ):
            self.assertIn(token, text)

    def test_opt_in_hook_runs_focused_floor(self) -> None:
        text = HOOK.read_text(encoding="utf-8")
        self.assertIn("diff --cached --name-only", text)
        self.assertIn("tests.test_technician_bootstrap_order_harness", text)
        self.assertIn("Test-TechnicianBootstrapOrderHarnessCompleteness.ps1", text)
        self.assertIn("Test-TechnicianBootstrapOrder.ps1", text)
        self.assertIn("diff --cached --check", text)
        self.assertNotIn("git reset", text.lower())
        self.assertNotIn("git clean", text.lower())

    def test_status_and_validator_write_only_outside_repo_by_default(self) -> None:
        for path in (STATUS, VALIDATOR):
            text = path.read_text(encoding="utf-8")
            self.assertIn("LOCALAPPDATA", text)
            self.assertIn("[System.IO.Path]::GetTempPath()", text)
            self.assertNotIn("Set-Content -LiteralPath (Join-Path $RootPath", text)

    def test_status_handles_detached_head_without_null_trim(self) -> None:
        text = STATUS.read_text(encoding="utf-8")
        self.assertIn("$branchLines = @(& git -C $RootPath branch --show-current", text)
        self.assertIn("$env:GITHUB_HEAD_REF", text)
        self.assertIn("'<detached>'", text)
        self.assertIn("$headLines = @(& git -C $RootPath rev-parse HEAD", text)
        self.assertIn("branch = $branch", text)
        self.assertIn("head = $head", text)
        self.assertNotIn("branch = $branch.Trim()", text)
        self.assertNotIn("head = $head.Trim()", text)

    def test_codebase_map_names_build_test_and_no_deploy(self) -> None:
        names = {item["name"] for item in self.map["commands"]}
        self.assertIn("Harness completeness", names)
        self.assertIn("Existing order contracts", names)
        self.assertIsNone(self.map["deploy"]["command"])
        self.assertIn("outside this harness-infrastructure sprint", self.map["deploy"]["reason"])


if __name__ == "__main__":
    unittest.main()
