#!/usr/bin/env python3
"""Contracts for the AgentSwitchboard automated test floor."""
from __future__ import annotations

import ast
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / ".ai/harness/automated-test-floor.manifest.json"
RUNNER = ROOT / "scripts/Test-AutomatedTestFloor.ps1"
WORKFLOW = ROOT / ".github/workflows/automated-test-floor.yml"
DOCS = ROOT / "docs/harness/automated-test-floor.md"
CANARY = ".ai/harness/fixtures/automated-test-floor/canary_fail.py"
EMPTY_SUITE = ROOT / ".ai/harness/fixtures/automated-test-floor/empty_suite.py"


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def run_pwsh(*extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pwsh", "-NoLogo", "-NoProfile", "-File", str(RUNNER), *extra],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=False,
    )


def module_has_testcase(path: Path) -> bool:
    source = path.read_text(encoding="utf-8-sig")
    tree = ast.parse(source, filename=str(path))
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        for base in node.bases:
            if isinstance(base, ast.Name) and base.id == "TestCase":
                return True
            if isinstance(base, ast.Attribute) and base.attr == "TestCase":
                return True
    return False


def module_path(module: str) -> Path:
    return ROOT.joinpath(*module.split(".")).with_suffix(".py")


class AutomatedTestFloorContracts(unittest.TestCase):
    def test_manifest_and_surfaces_exist(self):
        self.assertTrue(MANIFEST.is_file())
        self.assertTrue(RUNNER.is_file())
        self.assertTrue(WORKFLOW.is_file())
        self.assertTrue(DOCS.is_file())
        self.assertTrue(EMPTY_SUITE.is_file())
        self.assertTrue((ROOT / CANARY).is_file())
        manifest = load_manifest()
        self.assertEqual(manifest["manifestId"], "agentswitchboard.automated-test-floor.v1")
        self.assertEqual(manifest["proofLevel"], "static-test")
        self.assertFalse(manifest["determinism"]["networkAllowed"])
        self.assertFalse(manifest["determinism"]["mutationAllowed"])
        self.assertTrue(manifest["failClosed"]["zeroUnittestCases"])
        self.assertTrue(manifest["failClosed"]["falseGreenUnittestDiscoverForbidden"])
        self.assertGreaterEqual(len(manifest["gates"]), 8)
        self.assertIn("Test-AutomatedTestFloor.ps1", manifest["canonicalCommand"])

    def test_runner_types_and_paths_are_consistent(self):
        manifest = load_manifest()
        allowed = {"python-script", "python-unittest", "pwsh-file"}
        for gate in manifest["gates"]:
            self.assertIn(gate["runner"], allowed, gate["id"])
            self.assertIs(gate["required"], True, gate["id"])
            if gate["runner"] == "python-script":
                path = ROOT / gate["path"]
                self.assertTrue(path.is_file(), gate["path"])
                self.assertFalse(
                    module_has_testcase(path),
                    f"{gate['id']} is python-script but defines unittest.TestCase",
                )
            elif gate["runner"] == "python-unittest":
                self.assertGreaterEqual(len(gate["modules"]), 1, gate["id"])
                for module in gate["modules"]:
                    path = module_path(module)
                    self.assertTrue(path.is_file(), f"{gate['id']} missing {path}")
                    self.assertTrue(
                        module_has_testcase(path),
                        f"{gate['id']} module {module} lacks unittest.TestCase",
                    )
            else:
                self.assertTrue((ROOT / gate["path"]).is_file(), gate["path"])

    def test_workflow_triggers_and_docs(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        for token in (
            "pull_request:",
            "push:",
            "workflow_dispatch:",
            "contents: read",
            "scripts/Test-AutomatedTestFloor.ps1",
            "candidateSha",
            "github.event.pull_request.head.sha",
            "PR_HEAD_CONTAINED",
            "ubuntu-latest",
            "windows-latest",
            "concurrency:",
        ):
            self.assertIn(token, text)
        self.assertNotIn("secrets.", text)
        self.assertNotIn("schedule:", text)
        docs = DOCS.read_text(encoding="utf-8").lower()
        self.assertIn("test-automatedtestfloor.ps1", docs)
        self.assertIn("false-green", docs)
        self.assertIn("python-script", docs)

    def test_fail_closed_on_empty_manifest(self):
        with tempfile.TemporaryDirectory(prefix="asb-floor-empty-") as tmp:
            broken = Path(tmp) / "empty.json"
            broken.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "manifestId": "agentswitchboard.automated-test-floor.v1",
                        "proofLevel": "static-test",
                        "proofCeiling": "test",
                        "determinism": {
                            "pythonHashSeed": "0",
                            "timezone": "UTC",
                            "networkAllowed": False,
                            "mutationAllowed": False,
                        },
                        "failClosed": {"zeroRequiredGates": True},
                        "gates": [],
                    }
                ),
                encoding="utf-8",
            )
            result = run_pwsh("-ManifestPath", str(broken), "-OutputRoot", tmp)
            combined = (result.stdout or "") + (result.stderr or "")
            self.assertNotEqual(result.returncode, 0, combined)
            self.assertIn("zero gates", combined.lower())

    def test_fail_closed_on_zero_unittest_cases(self):
        direct = subprocess.run(
            [sys.executable, "-m", "unittest", "empty_suite", "-q"],
            cwd=str(EMPTY_SUITE.parent),
            text=True,
            capture_output=True,
            check=False,
            env={**os.environ, "PYTHONHASHSEED": "0"},
        )
        combined = (direct.stdout or "") + (direct.stderr or "")
        self.assertTrue("NO TESTS RAN" in combined or direct.returncode != 0, combined)

    def test_fail_closed_on_representative_script_defect(self):
        with tempfile.TemporaryDirectory(prefix="asb-floor-canary-") as tmp:
            manifest_path = Path(tmp) / "manifest.json"
            out = Path(tmp) / "out"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "manifestId": "agentswitchboard.automated-test-floor.v1",
                        "proofLevel": "static-test",
                        "proofCeiling": "test",
                        "determinism": {
                            "pythonHashSeed": "0",
                            "timezone": "UTC",
                            "networkAllowed": False,
                            "mutationAllowed": False,
                        },
                        "failClosed": {"zeroUnittestCases": True},
                        "gates": [
                            {
                                "id": "script-canary-fail",
                                "runner": "python-script",
                                "path": CANARY,
                                "required": True,
                                "platforms": ["windows", "linux", "macos"],
                                "expectStdoutContains": ["PASS"],
                                "proof": "negative canary fixture",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            result = run_pwsh("-ManifestPath", str(manifest_path), "-OutputRoot", str(out))
            combined = (result.stdout or "") + (result.stderr or "")
            self.assertNotEqual(result.returncode, 0, combined)
            self.assertIn("script-canary-fail", combined)
            receipt = out / "automated-test-floor-receipt.json"
            self.assertTrue(receipt.is_file(), combined)
            payload = json.loads(receipt.read_text(encoding="utf-8-sig"))
            self.assertEqual(payload["result"], "FAIL")


if __name__ == "__main__":
    unittest.main()
