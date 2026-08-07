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
SKILLS = ROOT / "SKILLS.md"
TRIGGERS = ROOT / "TRIGGERS.md"
CI = ROOT / ".github" / "workflows" / "technician-bootstrap-order.yml"
HOOK = ROOT / "tooling" / "profiles" / "windows" / "hooks" / "Invoke-TechnicianBootstrapOrderPreCommit.ps1"
PRE_PUSH = ROOT / "tooling" / "profiles" / "windows" / "hooks" / "Invoke-TechnicianBootstrapOrderPrePush.ps1"
STATUS = ROOT / "tooling" / "profiles" / "windows" / "Get-TechnicianBootstrapOrderHarnessStatus.ps1"
VALIDATOR = ROOT / "scripts" / "Test-TechnicianBootstrapOrderHarnessCompleteness.ps1"
CMD = ROOT / "Test-TechnicianBootstrapOrderHarness.cmd"
MANDATORY_PATHS = {
    "SKILLS.md", "TRIGGERS.md",
    "tooling/profiles/windows/harness/technician-ready/bootstrap-order.contract.json",
    "tooling/profiles/windows/harness/technician-ready/harness.registry.json",
    "tooling/profiles/windows/harness/technician-ready/codebase-map.json",
    "tooling/profiles/windows/harness/technician-ready/artifact-registry.json",
    "tooling/profiles/windows/harness/technician-ready/skill-routing.registry.json",
    "tooling/profiles/windows/harness/technician-ready/operator-report.template.md",
    "tooling/profiles/windows/harness/technician-ready/workflows/intake.workflow.json",
    "tooling/profiles/windows/harness/technician-ready/workflows/validate-change.workflow.json",
    "tooling/profiles/windows/harness/technician-ready/workflows/repair-failure.workflow.json",
    "tooling/profiles/windows/harness/technician-ready/workflows/handoff.workflow.json",
    ".ai/skills/technician-bootstrap-order-validation/SKILL.md",
    "tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1",
    "tooling/profiles/windows/hooks/Invoke-TechnicianBootstrapOrderPreCommit.ps1",
    "tooling/profiles/windows/hooks/Invoke-TechnicianBootstrapOrderPrePush.ps1",
    "scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1",
    "tests/test_technician_bootstrap_order_harness.py",
    "Test-TechnicianBootstrapOrderHarness.cmd",
    "docs/harness/technician-bootstrap-order-harness.md",
    ".github/workflows/technician-bootstrap-order.yml",
}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class TechnicianBootstrapOrderHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = load(REGISTRY)
        self.artifacts = load(ARTIFACTS)
        self.routing = load(ROUTING)
        self.map = load(CODEBASE_MAP)

    def test_registry_cannot_drop_canonical_owners(self) -> None:
        registered = set(self.registry["requiredPaths"])
        self.assertTrue(MANDATORY_PATHS <= registered, sorted(MANDATORY_PATHS - registered))
        self.assertEqual(
            "tooling/profiles/windows/hooks/Invoke-TechnicianBootstrapOrderPrePush.ps1",
            self.registry["canonicalOwners"]["prePushHook"],
        )

    def test_registered_and_mandatory_component_files_exist(self) -> None:
        required = set(self.registry["requiredPaths"]) | MANDATORY_PATHS
        self.assertEqual([], [path for path in sorted(required) if not (ROOT / path).is_file()])

    def test_machine_readable_harness_files_parse(self) -> None:
        for path in [ROOT / path for path in self.registry["requiredPaths"] if path.endswith(".json")]:
            with self.subTest(path=path):
                self.assertIsInstance(load(path), dict)

    def test_workflows_are_routed_and_unique(self) -> None:
        expected = self.registry["workflowIds"]
        routes = [route["workflowId"] for route in self.routing["routes"]]
        self.assertEqual(len(expected), len(set(expected)))
        self.assertEqual(set(expected), set(routes))
        actual = {load(path)["workflowId"] for path in (HARNESS / "workflows").glob("*.workflow.json")}
        self.assertEqual(set(expected), actual)

    def test_canonical_intake_routes_focused_skill(self) -> None:
        skills = SKILLS.read_text(encoding="utf-8")
        triggers = TRIGGERS.read_text(encoding="utf-8")
        self.assertIn("technician-bootstrap-order-validation", skills)
        self.assertIn("bootstrap.order-contract-change", triggers)
        self.assertIn("technician-bootstrap-order-validation", triggers)

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

    def test_skill_satisfies_canonical_contract_and_gate_integrity(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        for token in ("id: technician-bootstrap-order-validation", "version: 1.0.0", "status: canonical", "## Trigger", "## Inputs", "## Procedure", "## Outputs", "## Deterministic validation", "## Forbidden scope", "## Stop and escalate", "Never weaken", "## Proof ceiling"):
            self.assertIn(token, text)

    def test_ci_runs_new_and_existing_floor(self) -> None:
        text = CI.read_text(encoding="utf-8")
        for token in ("SKILLS.md", "TRIGGERS.md", "Invoke-TechnicianBootstrapOrderPrePush.ps1", "tests.test_technician_bootstrap_order_harness", "Test-TechnicianBootstrapOrderHarnessCompleteness.ps1", "Get-TechnicianBootstrapOrderHarnessStatus.ps1", "tests.test_technician_bootstrap_order", "Test-TechnicianBootstrapOrder.ps1", "tests.test_technician_agentswitchboard_ready", "Test-AgentDocumentationContract.ps1", "git diff --check"):
            self.assertIn(token, text)

    def test_opt_in_hook_runs_complete_focused_order_from_repo_root(self) -> None:
        text = HOOK.read_text(encoding="utf-8")
        execution_tokens = [
            "& python -m unittest tests.test_technician_bootstrap_order_harness -v",
            "& python -m unittest tests.test_technician_bootstrap_order -v",
            "& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1')",
            "& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-TechnicianBootstrapOrder.ps1')",
            "& python -m unittest tests.test_technician_agentswitchboard_ready -v",
            "& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-AgentDocumentationContract.ps1')",
            "& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1')",
            "& git -C $RootPath diff --cached --check",
        ]
        for token in ("SKILLS.md", "TRIGGERS.md", "Invoke-TechnicianBootstrapOrderPrePush.ps1", "Test-TechnicianBootstrapOrderHarness.cmd", "Push-Location -LiteralPath $RootPath", "finally", "Pop-Location", *execution_tokens):
            self.assertIn(token, text)
        positions = [text.index(token) for token in execution_tokens]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn("git reset", text.lower())
        self.assertNotIn("git clean", text.lower())

    def test_pre_push_gate_pins_outgoing_identity_and_full_harness(self) -> None:
        text = PRE_PUSH.read_text(encoding="utf-8")
        for token in (
            "ExpectedHead",
            "branch --show-current",
            "status --porcelain --untracked-files=no",
            "Test-TechnicianBootstrapOrderHarness.cmd",
            "merge-base",
            "diff --check",
            "Push-Location -LiteralPath $RootPath",
            "HEAD changed during pre-push validation",
            "PASS: technician bootstrap-order pre-push gate passed.",
        ):
            self.assertIn(token, text)
        lower = text.lower()
        for forbidden in ("git reset", "git clean", "git stash", "push --force", "git push"):
            self.assertNotIn(forbidden, lower)

    def test_operator_cmd_is_location_independent_and_runs_documentation_floor(self) -> None:
        text = CMD.read_text(encoding="utf-8")
        self.assertIn('pushd "%ROOT%"', text)
        self.assertIn("python -m unittest tests.test_technician_bootstrap_order_harness -v", text)
        self.assertIn("Test-AgentDocumentationContract.ps1", text)
        self.assertIn("popd", text)
        self.assertLess(text.index('pushd "%ROOT%"'), text.index("python -m unittest tests.test_technician_bootstrap_order_harness -v"))

    def test_status_reports_component_state_not_validation_readiness(self) -> None:
        text = STATUS.read_text(encoding="utf-8")
        self.assertIn("components-complete-validation-unproven", text)
        self.assertIn("unproven-by-status-reporter", text)
        self.assertIn("does not execute the validation order", text)
        self.assertNotIn("repository-ready", text)

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
        self.assertIn("Pre-push validation", names)
        self.assertIn("Agent documentation contract", names)
        self.assertEqual(
            "tooling/profiles/windows/hooks/Invoke-TechnicianBootstrapOrderPrePush.ps1",
            self.map["entrypoints"]["prePushHook"],
        )
        self.assertIsNone(self.map["deploy"]["command"])
        self.assertIn("outside this harness-infrastructure sprint", self.map["deploy"]["reason"])


if __name__ == "__main__":
    unittest.main()
