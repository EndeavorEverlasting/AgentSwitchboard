from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
import sys
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tooling" / "skills" / "skill_factoring_contracts.py"
SPEC = importlib.util.spec_from_file_location("skill_factoring_contracts", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class SkillFactoringContractTests(unittest.TestCase):
    def test_routing_fixtures_are_deterministic(self) -> None:
        fixture_path = Path(__file__).resolve().parents[1] / MODULE.ROUTING_FIXTURE_PATH
        cases = json.loads(fixture_path.read_text(encoding="utf-8"))["cases"]
        for case in cases:
            with self.subTest(case=case["id"]):
                primary, required = MODULE.route_case(case["input"])
                self.assertEqual(case.get("expectedPrimary"), primary)
                self.assertEqual(sorted(case.get("expectedRequired", [])), required)

    def test_boundary_fixtures_match_expected_results(self) -> None:
        fixture_path = Path(__file__).resolve().parents[1] / MODULE.BOUNDARY_FIXTURE_PATH
        cases = json.loads(fixture_path.read_text(encoding="utf-8"))["cases"]
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


if __name__ == "__main__":
    unittest.main()
