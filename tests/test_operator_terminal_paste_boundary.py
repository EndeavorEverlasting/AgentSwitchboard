from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "operator-command-delivery"
PROBE = ROOT / "scripts" / "Inspect-OperatorTerminalPasteBoundary.ps1"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class OperatorTerminalPasteBoundaryContract(unittest.TestCase):
    def test_probe_and_contract_are_registered(self) -> None:
        codebase = json.loads(text(HARNESS / "codebase-map.json"))
        artifacts = json.loads(text(HARNESS / "artifact-registry.json"))
        artifact_by_id = {item["artifactId"]: item for item in artifacts["artifacts"]}

        self.assertEqual(
            "scripts/Inspect-OperatorTerminalPasteBoundary.ps1",
            codebase["entrypoints"]["terminalPasteProbe"],
        )
        self.assertEqual(
            "tests/test_operator_terminal_paste_boundary.py",
            codebase["entrypoints"]["terminalPasteContract"],
        )
        self.assertTrue(PROBE.is_file())
        self.assertIn("terminal-paste-boundary-result", artifact_by_id)
        self.assertEqual(
            "scripts/Inspect-OperatorTerminalPasteBoundary.ps1",
            artifact_by_id["terminal-paste-boundary-result"]["producer"],
        )
        for field in (
            "classification",
            "captureSource",
            "utf8Sha256",
            "literalQuestionMarkCount",
            "replacementCharacterCount",
            "rawTextPersisted",
            "proofCeiling",
        ):
            self.assertIn(field, artifacts["requiredTerminalPasteFields"])

    def test_probe_is_read_only_with_respect_to_terminal_configuration(self) -> None:
        body = text(PROBE)
        for token in (
            "Get-Clipboard -Raw",
            "SHA256]::HashData",
            "literalQuestionMarkCount",
            "replacementCharacterCount",
            "rawTextPersisted = $false",
            "captured-input-contains-replacement-character",
            "captured-input-contains-question-mark",
            "captured-input-clean-presentation-unproven",
            "terminal glyph rendering",
            "PSReadLine",
            "WezTerm configuration",
        ):
            self.assertIn(token, body, token)

        for forbidden in (
            "SetEnvironmentVariable",
            "reg.exe",
            "Set-ItemProperty",
            "Remove-Item",
            "winget",
            "wezterm.lua",
            "font_rules",
        ):
            self.assertNotIn(forbidden, body, forbidden)
        self.assertNotIn("rawText =", body)
        self.assertNotIn("capturedText =", body)

    def test_fixtures_preserve_clean_and_visible_question_mark_cases(self) -> None:
        clean = text(HARNESS / "fixtures" / "terminal-paste-clean.fixture.txt")
        question = text(HARNESS / "fixtures" / "terminal-paste-question-mark.fixture.txt")

        self.assertIn("—", clean)
        self.assertIn("→", clean)
        self.assertNotIn("?", clean)
        self.assertIn("?", question)

    def test_failure_workflow_keeps_presentation_proof_bounded(self) -> None:
        workflow = json.loads(text(HARNESS / "workflows" / "handle-command-delivery-failure.workflow.json"))
        rendered = json.dumps(workflow)
        self.assertIn("input-capture", rendered)
        self.assertIn("presentation-rendering-unproven", rendered)
        self.assertIn("Inspect-OperatorTerminalPasteBoundary.ps1", rendered)
        self.assertIn("captured-input-clean-presentation-unproven", rendered)
        self.assertIn("clean captured input", rendered.lower())

    def test_docs_skill_and_ci_route_the_probe(self) -> None:
        docs = text(ROOT / "docs" / "harness" / "operator-command-delivery.md")
        skill = text(ROOT / ".ai" / "skills" / "operator-command-delivery" / "SKILL.md")
        workflow = text(ROOT / ".github" / "workflows" / "operator-command-delivery-harness.yml")

        for body in (docs, skill):
            self.assertIn("Inspect-OperatorTerminalPasteBoundary.ps1", body)
            self.assertIn("captured-input-clean-presentation-unproven", body)
            self.assertIn("raw", body.lower())
        self.assertIn("tests.test_operator_terminal_paste_boundary", workflow)
        self.assertIn("terminal-paste-clean.fixture.txt", workflow)
        self.assertIn("terminal-paste-question-mark.fixture.txt", workflow)
        self.assertIn("rawTextPersisted", workflow)


if __name__ == "__main__":
    unittest.main()
