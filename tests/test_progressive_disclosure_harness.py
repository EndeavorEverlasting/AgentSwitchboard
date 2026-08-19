from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "tooling/harness/context/context.routes.json"
VALIDATOR = ROOT / "scripts/Test-ProgressiveDisclosureHarness.py"


def git(*args: str) -> str:
    result = subprocess.run(["git", "-C", str(ROOT), *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {result.stderr}")
    return result.stdout.strip()


def load_validator_module():
    spec = importlib.util.spec_from_file_location("progressive_disclosure_validator", VALIDATOR)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load progressive disclosure validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
        self.assertEqual("docs/governance/agent-operating-details.md", deep["path"])
        self.assertEqual("c94b797bef04942636af61b980c478919710e067", deep["expectedGitBlobSha"])
        self.assertEqual(27896, deep["expectedBytes"])
        actual_sha = git("rev-parse", "HEAD:docs/governance/agent-operating-details.md")
        actual_size = int(git("cat-file", "-s", actual_sha))
        self.assertEqual("c94b797bef04942636af61b980c478919710e067", actual_sha)
        self.assertEqual(27896, actual_size)

    def test_measure_keeps_missing_routes_structured(self):
        module = load_validator_module()
        result = module.measure(["__missing_progressive_route__"], 4)
        self.assertEqual(["__missing_progressive_route__"], result["missing"])
        self.assertEqual(0, result["bytes"])
        self.assertEqual(0, result["estimatedTokens"])

    def test_validator_has_independent_governance_anchor(self):
        text = VALIDATOR.read_text(encoding="utf-8")
        self.assertIn('CANONICAL_GOVERNANCE_PATH = "docs/governance/agent-operating-details.md"', text)
        self.assertIn('CANONICAL_GOVERNANCE_BLOB = "c94b797bef04942636af61b980c478919710e067"', text)
        self.assertIn('deep.get("path") == CANONICAL_GOVERNANCE_PATH', text)
        self.assertIn('tracked_blob(CANONICAL_GOVERNANCE_PATH)', text)

    def test_cmd_propagates_failures_outside_parenthesized_runtime_branch(self):
        cmd = (ROOT / "Test-ProgressiveDisclosureHarness.cmd").read_text(encoding="utf-8")
        self.assertIn("goto :run_python", cmd)
        self.assertIn("if errorlevel 1 set \"R=%ERRORLEVEL%\"", cmd)
        self.assertIn(":fail", cmd)
        self.assertIn("endlocal & exit /b %R%", cmd)

    def test_ci_checks_committed_range(self):
        ci = (ROOT / ".github/workflows/progressive-disclosure-harness.yml").read_text(encoding="utf-8")
        self.assertIn("fetch-depth: 0", ci)
        self.assertIn("github.event.pull_request.base.sha", ci)
        self.assertIn("github.event.pull_request.head.sha", ci)
        self.assertIn("github.event.before", ci)
        self.assertNotIn("run: git diff --check\n", ci)

    def test_validator_measures_three_retrieval_simulations(self):
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / "progressive-disclosure-validation.json"
            result = subprocess.run([sys.executable, str(VALIDATOR), "--output", str(report)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            data = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual("PASS", data["status"])
            self.assertLessEqual(data["after"]["orientation50k"]["estimatedTokens"], 1000)
            self.assertLessEqual(data["after"]["domain30k"]["estimatedTokens"], 2000)
            self.assertLessEqual(data["after"]["workflow15k"]["estimatedTokens"], 4000)
            self.assertGreaterEqual(data["reductions"]["orientation50kPercent"], 80)


if __name__ == "__main__":
    unittest.main()
