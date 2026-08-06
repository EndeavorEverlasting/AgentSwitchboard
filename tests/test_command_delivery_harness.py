from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "skills" / "harness" / "command-delivery"
MANIFEST = HARNESS / "manifest.json"


def load(relative: str) -> dict:
    with (ROOT / relative).open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise AssertionError(f"Expected JSON object: {relative}")
    return value


class CommandDeliveryHarnessTests(unittest.TestCase):
    def test_manifest_components_exist(self) -> None:
        manifest = load("tooling/skills/harness/command-delivery/manifest.json")
        components = manifest["components"]
        self.assertEqual(len(components), len(set(components)))
        missing = [path for path in components if not (ROOT / path).is_file()]
        self.assertEqual([], missing)

    def test_manifest_entrypoints_are_components(self) -> None:
        manifest = load("tooling/skills/harness/command-delivery/manifest.json")
        components = set(manifest["components"])
        for name, path in manifest["entrypoints"].items():
            with self.subTest(entrypoint=name):
                self.assertIn(path, components)
                self.assertTrue((ROOT / path).is_file())

    def test_codebase_map_has_entrypoints_commands_and_traps(self) -> None:
        payload = load("tooling/skills/harness/command-delivery/codebase-map.json")
        self.assertEqual("EndeavorEverlasting/AgentSwitchboard", payload["repository"])
        self.assertGreaterEqual(len(payload["entrypoints"]), 10)
        names = {item["name"] for item in payload["commands"]}
        self.assertIn("Outer entrypoint proof", names)
        traps = "\n".join(payload["knownTraps"])
        self.assertIn("%~dp0", traps)
        self.assertIn("path containing spaces", traps)

    def test_workflows_are_complete_and_distinct(self) -> None:
        expected = {
            "task-intake.workflow.json": "command-delivery.task-intake",
            "validation-before-commit.workflow.json": "command-delivery.validation-before-commit",
            "failure-recovery.workflow.json": "command-delivery.failure-recovery",
            "handoff.workflow.json": "command-delivery.handoff",
        }
        ids = []
        for filename, workflow_id in expected.items():
            payload = load(f"tooling/skills/harness/command-delivery/workflows/{filename}")
            ids.append(payload["workflowId"])
            self.assertEqual(workflow_id, payload["workflowId"])
            self.assertTrue(payload["trigger"])
            self.assertTrue(payload["requiredInputs"])
            self.assertGreaterEqual(len(payload["steps"]), 4)
            self.assertTrue(payload["outputs"])
            self.assertTrue(payload["failurePolicy"])
            self.assertTrue(payload["proofCeiling"])
            self.assertEqual(list(range(1, len(payload["steps"]) + 1)), [step["order"] for step in payload["steps"]])
        self.assertEqual(len(ids), len(set(ids)))

    def test_artifact_registry_has_generators_and_local_policy(self) -> None:
        payload = load("tooling/skills/harness/command-delivery/artifact-registry.json")
        self.assertFalse(payload["tracked"])
        ids = [item["artifactId"] for item in payload["artifacts"]]
        self.assertEqual(len(ids), len(set(ids)))
        for artifact in payload["artifacts"]:
            self.assertTrue(artifact["fileName"])
            self.assertIn(artifact["root"], payload["roots"])
            self.assertTrue(artifact["generateWith"])
            self.assertTrue(artifact["proofCeiling"])
        self.assertIn("command-delivery-entrypoint-json", ids)
        self.assertIn("command-delivery-handoff", ids)

    def test_capabilities_register_outer_entrypoint_and_status(self) -> None:
        payload = load("tooling/skills/harness/command-delivery/capability-registry.json")
        ids = {item["id"] for item in payload["capabilities"]}
        self.assertIn("command.entrypoint.spaced-path.validate", ids)
        self.assertIn("command.harness.completeness.validate", ids)
        self.assertIn("command.harness.status.report", ids)

    def test_cmd_normalizes_root_without_trailing_separator(self) -> None:
        text = (ROOT / "Test-SkillFactoringContracts.cmd").read_text(encoding="utf-8")
        self.assertIn('for %%I in ("%~dp0.") do set "ROOT=%%~fI"', text)
        self.assertIn('-RootPath "%ROOT%"', text)
        self.assertNotIn('-RootPath "%~dp0"', text)

    def test_outer_entrypoint_validator_requires_spaced_worktree_and_report(self) -> None:
        text = (ROOT / "scripts" / "Test-CommandDeliveryEntrypoint.ps1").read_text(encoding="utf-8")
        self.assertIn("AgentSwitchboard Command Delivery", text)
        self.assertIn("worktree add --detach", text)
        self.assertIn("Test-SkillFactoringContracts.cmd", text)
        self.assertIn("skill-factoring-report.json", text)
        self.assertIn("worktree remove", text)

    def test_hooks_are_opt_in_and_cover_generated_evidence(self) -> None:
        precommit = (ROOT / "tooling/skills/hooks/Invoke-CommandDeliveryHarnessPreCommit.ps1").read_text(encoding="utf-8")
        prepush = (ROOT / "tooling/skills/hooks/Invoke-CommandDeliveryHarnessPrePush.ps1").read_text(encoding="utf-8")
        self.assertIn("diff --cached --check", precommit)
        self.assertIn("Generated command-delivery evidence must remain untracked", precommit)
        self.assertIn("Test-CommandDeliveryEntrypoint.ps1", prepush)
        self.assertNotIn("git config core.hooksPath", precommit + prepush)

    def test_status_template_and_reporter_match(self) -> None:
        template = (HARNESS / "reports/operator-status.template.md").read_text(encoding="utf-8")
        reporter = (ROOT / "tooling/skills/Get-CommandDeliveryHarnessStatus.ps1").read_text(encoding="utf-8")
        for token in ("{{STATUS}}", "{{WORKING}}", "{{GAPS}}", "{{TRAPS}}", "{{NEXT_COMMAND}}"):
            self.assertIn(token, template)
            self.assertIn(token, reporter)

    def test_operator_guide_records_exact_boundary_rule(self) -> None:
        text = (ROOT / "docs/harness/command-delivery-skill-factoring.md").read_text(encoding="utf-8")
        self.assertIn("must not pass quoted `%~dp0` directly", text)
        self.assertIn("An inner PS1 pass does not prove the outer CMD entrypoint", text)
        self.assertIn("path containing spaces", text)


if __name__ == "__main__":
    unittest.main()
