import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / ".ai/skills/powershell-interactive-execution/SKILL.md"


class PowerShellInteractiveExecutionSkillTests(unittest.TestCase):
    def test_skill_uses_current_command_authority_and_explicit_delivery_modes(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        for token in (
            "operator-command-delivery",
            "interactive-copy-paste",
            "script-file",
            "Prefer a repository-owned `.cmd` or `.ps1` entrypoint",
            "one outer `& { ... }` block",
            "immediately after each native command",
            "Set-Location -LiteralPath",
            "tests.test_powershell_interactive_execution_skill",
        ):
            self.assertIn(token, text)

        self.assertNotIn("operator-command-envelope", text)
        self.assertNotIn("Test-SkillFactoringContracts", text)

    def test_skill_forbids_detached_continuations_and_destructive_recovery(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        for token in (
            "No standalone `else`, `elseif`, `catch`, or `finally`",
            "No giant interactive bootstrap",
            "No native command whose exit code is inspected only after another native command ran",
            "No reset, discard, force-push, stash, clean, or branch deletion",
        ):
            self.assertIn(token, text)

    def test_examples_do_not_contain_prompt_contamination_or_hardcoded_user_paths(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        self.assertNotRegex(text, re.compile(r"(?im)^\s*PS\s+[^>]*>"))
        self.assertNotRegex(text, re.compile(r"(?i)C:\\Users\\[^\\\s]+"))


if __name__ == "__main__":
    unittest.main()
