from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "operator-command-delivery"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class OperatorCommandDeliveryHarnessContract(unittest.TestCase):
    def test_components_exist(self) -> None:
        required = [
            HARNESS / "codebase-map.json",
            HARNESS / "artifact-registry.json",
            HARNESS / "workflows" / "verify-command-delivery.workflow.json",
            HARNESS / "workflows" / "handle-command-delivery-failure.workflow.json",
            HARNESS / "fixtures" / "valid-powershell-command.fixture.ps1",
            HARNESS / "fixtures" / "invalid-corrupted-command.fixture.txt",
            HARNESS / "fixtures" / "child-launch-access-denied.fixture.json",
            HARNESS / "operator-report.template.md",
            HARNESS / "hooks" / "pre-push.ps1",
            ROOT / ".ai" / "skills" / "operator-command-delivery" / "SKILL.md",
            ROOT / "docs" / "harness" / "operator-command-delivery.md",
            ROOT / "scripts" / "Test-OperatorCommandDeliveryHarnessCompleteness.ps1",
            ROOT / "scripts" / "Test-OperatorChildExecutableLaunch.ps1",
            ROOT / ".github" / "workflows" / "operator-command-delivery-harness.yml",
        ]
        for path in required:
            self.assertTrue(path.is_file(), f"missing harness component: {path.relative_to(ROOT)}")

    def test_json_contracts(self) -> None:
        codebase = json.loads(text(HARNESS / "codebase-map.json"))
        artifacts = json.loads(text(HARNESS / "artifact-registry.json"))
        verify = json.loads(text(HARNESS / "workflows" / "verify-command-delivery.workflow.json"))
        failure = json.loads(text(HARNESS / "workflows" / "handle-command-delivery-failure.workflow.json"))
        blocked = json.loads(text(HARNESS / "fixtures" / "child-launch-access-denied.fixture.json"))
        self.assertEqual("agentswitchboard.operator-command-delivery-harness.v1", codebase["harnessId"])
        self.assertEqual("tracked-contract", codebase["status"])
        self.assertEqual("scripts/Test-OperatorChildExecutableLaunch.ps1", codebase["entrypoints"]["childExecutableProbe"])
        self.assertFalse(artifacts["tracked"])
        self.assertEqual("local-operational", artifacts["sensitivity"])
        self.assertIn("child-executable-launch-result", {a["artifactId"] for a in artifacts["artifacts"]})
        self.assertIn("childExecutableLaunchArtifacts", artifacts["requiredResultFields"])
        self.assertGreaterEqual(len(verify["steps"]), 10)
        self.assertGreaterEqual(len(failure["steps"]), 8)
        self.assertIn("child-executable-launch", json.dumps(verify))
        self.assertIn("child-executable-launch", json.dumps(failure))
        self.assertEqual("Access is denied.", blocked["startError"])
        self.assertEqual(5, blocked["observedWrapperExitCode"])
        self.assertFalse(blocked["downstreamArtifactProduced"])
        self.assertEqual("child-executable-launch-blocked", blocked["expectedClassification"])
        self.assertFalse(blocked["expectedRuntimeProof"])

    def test_positive_fixture_is_safe_for_copy_paste(self) -> None:
        fixture = text(HARNESS / "fixtures" / "valid-powershell-command.fixture.ps1")
        for token in (
            "$env:TEMP",
            "$env:LOCALAPPDATA",
            "gh api --method GET",
            "-f \"ref=$ref\"",
            "CHILD_EXIT_CODE=",
            "ARTIFACT=",
        ):
            self.assertIn(token, fixture)
        self.assertNotRegex(fixture, r"\$env\\:")
        self.assertNotRegex(fixture, r"(?m)^\s*PS\s+[A-Za-z]:\\")
        self.assertNotRegex(fixture, r"(?m)^\s*>>")
        self.assertNotRegex(fixture, r"(?m)^\s*exit\s+")
        self.assertNotRegex(fixture, r"contents/[^\s\"']+\?ref=")

    def test_negative_fixture_preserves_transport_regressions(self) -> None:
        fixture = text(HARNESS / "fixtures" / "invalid-corrupted-command.fixture.txt")
        self.assertRegex(fixture, r"\$env\\:TEMP")
        self.assertRegex(fixture, r"\$env\\:LOCALAPPDATA")
        self.assertRegex(fixture, r"(?m)^PS\s+[A-Za-z]:\\")
        self.assertRegex(fixture, r"contents/[^\s\"']+\?ref=")
        self.assertIn("exit $LASTEXITCODE", fixture)

    def test_child_executable_probe_is_concrete_bounded_and_durable(self) -> None:
        probe = text(ROOT / "scripts" / "Test-OperatorChildExecutableLaunch.ps1")
        for token in (
            "ProcessStartInfo",
            "UseShellExecute = $false",
            "RedirectStandardOutput = $true",
            "RedirectStandardError = $true",
            "WaitForExit",
            "child-executable-launch-result.json",
            "child-executable-launch-blocked",
            "$env:LOCALAPPDATA",
            "STATUS=",
            "ARTIFACT=",
        ):
            self.assertIn(token, probe, token)
        self.assertNotIn("Start-Process", probe)
        self.assertIn("[ValidateRange(1, 120)][int]$TimeoutSeconds", probe)

    def test_skill_workflows_and_report_require_launch_proof(self) -> None:
        skill = text(ROOT / ".ai" / "skills" / "operator-command-delivery" / "SKILL.md")
        for heading in (
            "## Trigger",
            "## Required inputs",
            "## Procedure",
            "## Expected outputs",
            "## Deterministic validation",
            "## Proof promotion",
            "## Forbidden scope",
            "## Stop and escalate",
        ):
            self.assertIn(heading, skill)
        for token in (
            "Test-OperatorChildExecutableLaunch.ps1",
            "where",
            "Get-Command",
            "UseShellExecute=false",
            "child-executable-launch",
        ):
            self.assertIn(token, skill, token)

        verify = text(HARNESS / "workflows" / "verify-command-delivery.workflow.json")
        failure = text(HARNESS / "workflows" / "handle-command-delivery-failure.workflow.json")
        for body in (verify, failure):
            self.assertIn("child-executable-launch", body)
            self.assertIn("Access is denied", body)
        self.assertIn("UseShellExecute=false", verify)

        report = text(HARNESS / "operator-report.template.md")
        for placeholder in (
            "{{STATUS}}",
            "{{RESOLVED_COMMIT}}",
            "{{CHILD_EXECUTABLE}}",
            "{{CHILD_LAUNCH_RESULT}}",
            "{{CHILD_START_ERROR}}",
            "{{CHILD_LAUNCH_ARTIFACT}}",
            "{{CHILD_EXIT_CODE}}",
            "{{DOWNSTREAM_ARTIFACT}}",
            "{{PROOF_CEILING}}",
            "{{NEXT_COMMAND}}",
        ):
            self.assertIn(placeholder, report)

    def test_hook_is_opt_in_and_runs_both_validators(self) -> None:
        hook = text(HARNESS / "hooks" / "pre-push.ps1")
        self.assertIn("Test-OperatorCommandDeliveryHarnessCompleteness.ps1", hook)
        self.assertIn("test_operator_command_delivery_harness.py", hook)
        self.assertNotIn("git config core.hooksPath", hook)
        self.assertNotIn("SetEnvironmentVariable", hook)

    def test_downstream_tmux_launcher_is_present_but_not_owned_here(self) -> None:
        self.assertTrue((ROOT / "Open-AgentSwitchboard-Tmux.cmd").is_file())
        self.assertTrue((ROOT / "Open-AgentSwitchboard-Tmux.ps1").is_file())
        guide = text(ROOT / "docs" / "harness" / "operator-command-delivery.md")
        self.assertIn("Open-AgentSwitchboard-Tmux.ps1", guide)
        self.assertIn("does not prove the downstream runtime", guide)
        self.assertIn("where", guide)
        self.assertIn("Get-Command", guide)
        self.assertIn("Access is denied", guide)


if __name__ == "__main__":
    unittest.main()
