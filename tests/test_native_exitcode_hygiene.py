from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN_PATTERN = re.compile(r"\$(?:global:)?LASTEXITCODE", re.IGNORECASE)
AMBIGUOUS_COLON_PATTERN = re.compile(
    r"""\$(?!\{)([A-Za-z_][A-Za-z0-9_]*):(?=$|[\s"'`,;)\]}])""",
    re.IGNORECASE,
)
STRICT_MODE_SCRIPTS = (
    "scripts/Test-CommandDeliveryEntrypoint.ps1",
    "scripts/Test-CommandDeliveryHarnessCompleteness.ps1",
    "scripts/Test-AppHarnessOneCommandProof.ps1",
)


class NativeExitCodeHygieneTests(unittest.TestCase):
    def test_strict_mode_scripts_initialize_before_first_reference(self) -> None:
        for relative in STRICT_MODE_SCRIPTS:
            with self.subTest(script=relative):
                text = (ROOT / relative).read_text(encoding="utf-8")
                matches = list(TOKEN_PATTERN.finditer(text))
                self.assertTrue(matches, f"{relative} never records native exit state")
                initialization = text.find("$global:LASTEXITCODE = 0")
                self.assertGreaterEqual(initialization, 0, f"{relative} does not initialize native exit state")
                self.assertEqual(
                    initialization,
                    matches[0].start(),
                    f"{relative} references LASTEXITCODE before deterministic initialization",
                )

    def test_interpolated_colon_variables_are_delimited(self) -> None:
        for relative in STRICT_MODE_SCRIPTS:
            with self.subTest(script=relative):
                text = (ROOT / relative).read_text(encoding="utf-8")
                ambiguous = [
                    f"{match.group(1)}@{text.count(chr(10), 0, match.start()) + 1}"
                    for match in AMBIGUOUS_COLON_PATTERN.finditer(text)
                ]
                self.assertEqual(
                    [],
                    ambiguous,
                    f"{relative} contains ambiguous PowerShell variable-colon interpolation; use ${{name}}:",
                )

    def test_one_command_proof_surfaces_child_failures(self) -> None:
        proof = (ROOT / "scripts/Test-AppHarnessOneCommandProof.ps1").read_text(encoding="utf-8")
        self.assertIn("[int]$ValidatorTimeoutSeconds = 120", proof)
        self.assertIn("FAILED OFFLINE VALIDATOR DETAILS", proof)
        self.assertIn("$failedCheck.details", proof)
        self.assertIn("Required offline validator aggregate failed", proof)
        self.assertLess(
            proof.index("FAILED OFFLINE VALIDATOR DETAILS"),
            proof.index("Required offline validator aggregate failed"),
        )

    def test_entrypoint_retains_spaced_worktree_proof(self) -> None:
        entrypoint = (ROOT / "scripts/Test-CommandDeliveryEntrypoint.ps1").read_text(encoding="utf-8")
        self.assertIn("Test-SkillFactoringContracts.cmd", entrypoint)
        self.assertIn("worktree add --detach", entrypoint)
        self.assertIn("worktreeContainsSpaces", entrypoint)


if __name__ == "__main__":
    unittest.main()
