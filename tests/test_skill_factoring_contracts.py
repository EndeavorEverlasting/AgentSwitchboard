from __future__ import annotations

import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tooling" / "skills" / "skill_factoring_contracts.py"
SPEC = importlib.util.spec_from_file_location("skill_factoring_contracts", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]


class SkillFactoringContractTests(unittest.TestCase):
    def test_routing_fixtures_are_deterministic(self) -> None:
        cases = json.loads((ROOT / MODULE.ROUTING_FIXTURE_PATH).read_text(encoding="utf-8"))["cases"]
        for case in cases:
            with self.subTest(case=case["id"]):
                primary, required = MODULE.route_case(case["input"])
                self.assertEqual(case.get("expectedPrimary"), primary)
                self.assertEqual(sorted(case.get("expectedRequired", [])), required)

    def test_boundary_fixtures_match_expected_results(self) -> None:
        cases = json.loads((ROOT / MODULE.BOUNDARY_FIXTURE_PATH).read_text(encoding="utf-8"))["cases"]
        for case in cases:
            with self.subTest(case=case["id"]):
                result = MODULE.validate_interactive_powershell(case["snippets"], case["deliveryMode"])
                self.assertEqual(case["expected"], result.status)
                if case.get("expectedRule"):
                    self.assertEqual(case["expectedRule"], result.rule)

    def test_original_failure_is_rejected(self) -> None:
        snippets = [
            "$repo = if ($env:ROOT) {\n  $env:ROOT\n}",
            "elseif (Test-Path '.repo-path') {\n  Get-Content '.repo-path'\n}",
            "else {\n  git rev-parse --show-toplevel\n}",
        ]
        result = MODULE.validate_interactive_powershell(snippets, "interactive-copy-paste")
        self.assertEqual("FAIL", result.status)
        self.assertEqual("detached-continuation-snippet", result.rule)

    def test_incomplete_powershell_is_rejected_before_early_pass(self) -> None:
        result = MODULE.validate_interactive_powershell(["if ($a) {\n  Write-Host x"], "interactive-copy-paste")
        self.assertEqual("FAIL", result.status)
        self.assertEqual("incomplete-powershell-syntax", result.rule)

    def test_atomic_outer_scriptblock_is_accepted(self) -> None:
        snippet = "& {\n  if ($a) {\n    1\n  } elseif ($b) {\n    2\n  } else {\n    3\n  }\n}"
        result = MODULE.validate_interactive_powershell([snippet], "interactive-copy-paste")
        self.assertEqual("PASS", result.status)

    def test_saved_script_is_not_subject_to_interactive_boundary(self) -> None:
        snippet = "if ($a) { 1 }\nelseif ($b) { 2 }\nelse { 3 }"
        result = MODULE.validate_interactive_powershell([snippet], "script-file")
        self.assertEqual("PASS", result.status)

    def test_candidate_markdown_blocks_are_extracted(self) -> None:
        text = "Before\n```powershell\nif (-not $a) { throw 'x' }\n```\nAfter\n"
        self.assertEqual(["if (-not $a) { throw 'x' }"], MODULE.extract_powershell_blocks(text))

    def test_unterminated_markdown_fence_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unterminated Markdown fence"):
            MODULE.extract_powershell_blocks("```powershell\nWrite-Host x\n")

    def test_relative_candidate_resolves_against_root(self) -> None:
        candidate = ROOT / "relative-handoff.md"
        candidate.write_text("```powershell\nWrite-Host x\n```\n", encoding="utf-8")
        try:
            self.assertEqual(candidate.resolve(), MODULE.resolve_candidate_path(ROOT, Path("relative-handoff.md")))
        finally:
            candidate.unlink()

    def test_registry_schema_is_loaded_and_enforced(self) -> None:
        registry = json.loads((ROOT / MODULE.REGISTRY_PATH).read_text(encoding="utf-8"))
        schema = json.loads((ROOT / MODULE.SCHEMA_PATH).read_text(encoding="utf-8"))
        invalid = copy.deepcopy(registry)
        invalid.pop("artifactPolicy")
        invalid["unexpected"] = True
        errors = MODULE.validate_json_schema(invalid, schema)
        self.assertTrue(any("artifactPolicy" in error for error in errors))
        self.assertTrue(any("unexpected" in error for error in errors))

    def test_unterminated_candidate_fails_contract(self) -> None:
        candidate = ROOT / "unterminated-handoff.md"
        candidate.write_text("```powershell\nWrite-Host x\n", encoding="utf-8")
        try:
            findings, _ = MODULE.run_contracts(ROOT, Path("unterminated-handoff.md"))
            self.assertTrue(any(f.check == "candidate/markdown-fence" and f.status == "FAIL" for f in findings))
        finally:
            candidate.unlink()

    def test_cmd_entrypoint_supports_both_powershell_hosts(self) -> None:
        text = (ROOT / "Test-SkillFactoringContracts.cmd").read_text(encoding="utf-8")
        self.assertIn("where pwsh.exe", text)
        self.assertIn("where powershell.exe", text)
        self.assertIn('set "PSHOST=powershell.exe"', text)
        self.assertIn('"%PSHOST%" -NoLogo -NoProfile', text)

    def test_cmd_entrypoint_normalizes_dp0_before_native_handoff(self) -> None:
        text = (ROOT / "Test-SkillFactoringContracts.cmd").read_text(encoding="utf-8")
        self.assertIn('for %%I in ("%~dp0.") do set "ROOT=%%~fI"', text)
        self.assertIn('-File "%ROOT%\\scripts\\Test-SkillFactoringContracts.ps1"', text)
        self.assertIn('-RootPath "%ROOT%"', text)
        self.assertNotIn('-RootPath "%~dp0"', text)


if __name__ == "__main__":
    unittest.main()
