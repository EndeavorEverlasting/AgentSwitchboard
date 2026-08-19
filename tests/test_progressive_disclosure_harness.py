from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "tooling/harness/context/context.routes.json"


def git(*args: str) -> str:
    result = subprocess.run(["git", "-C", str(ROOT), *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {result.stderr}")
    return result.stdout.strip()


class ProgressiveDisclosureHarnessTests(unittest.TestCase):
    def test_router_and_glossary_parse(self):
        router = json.loads(ROUTER.read_text(encoding="utf-8"))
        glossary = json.loads((ROOT / router["glossary"]["path"]).read_text(encoding="utf-8"))
        self.assertEqual("agentswitchboard.progressive-disclosure.v1", router["routerId"])
        self.assertGreaterEqual(len(glossary["terms"]), 10)

    def test_orientation_is_router_not_encyclopedia(self):
        router = json.loads(ROUTER.read_text(encoding="utf-8"))
        self.assertEqual(["HARNESS.md"], router["orientation"]["defaultLoad"])
        harness = (ROOT / "HARNESS.md").read_text(encoding="utf-8")
        self.assertIn("50k Entry", harness)
        self.assertIn("Do not preload", harness)
        self.assertLessEqual(len(harness.encode("utf-8")), 4000)

    def test_opencode_domain_routes_one_workflow_without_implementation_preload(self):
        router = json.loads(ROUTER.read_text(encoding="utf-8"))
        domain = next(x for x in router["domains"] if x["domainId"] == "opencode-lsp")
        workflow = next(x for x in router["workflows"] if x["workflowId"] == "opencode-lsp.configure")
        self.assertEqual(["tooling/harness/context/domains/opencode-lsp.domain.json"], domain["defaultLoad"])
        self.assertNotIn("tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1", workflow["defaultLoad"])
        self.assertIn("tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1", workflow["onDemand"])

    def test_old_governance_is_preserved_exactly_as_triggered_detail(self):
        router = json.loads(ROUTER.read_text(encoding="utf-8"))
        deep = router["preservedGovernance"]
        actual_sha = git("rev-parse", f"HEAD:{deep['path']}")
        actual_size = int(git("cat-file", "-s", actual_sha))
        self.assertEqual(deep["expectedGitBlobSha"], actual_sha)
        self.assertEqual(deep["expectedBytes"], actual_size)

    def test_validator_measures_three_retrieval_simulations(self):
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / "progressive-disclosure-validation.json"
            result = subprocess.run([sys.executable, str(ROOT / "scripts/Test-ProgressiveDisclosureHarness.py"), "--output", str(report)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            data = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual("PASS", data["status"])
            self.assertLessEqual(data["after"]["orientation50k"]["estimatedTokens"], 1000)
            self.assertLessEqual(data["after"]["domain30k"]["estimatedTokens"], 2000)
            self.assertLessEqual(data["after"]["workflow15k"]["estimatedTokens"], 4000)
            self.assertGreaterEqual(data["reductions"]["orientation50kPercent"], 80)


if __name__ == "__main__":
    unittest.main()
