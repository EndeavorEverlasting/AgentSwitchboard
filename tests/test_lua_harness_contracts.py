import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "lua" / "harness"
MANIFEST = HARNESS / "manifest.json"
CONTRACT = HARNESS / "lua-embedding.contract.json"
WORKFLOWS = HARNESS / "workflow-registry.json"
ARTIFACTS = HARNESS / "artifact-registry.json"
VALIDATORS = HARNESS / "validator-registry.json"
STATUS = ROOT / "tooling" / "lua" / "Get-LuaHarnessStatus.py"
SKILL = ROOT / ".ai" / "skills" / "lua-embedding-integration" / "SKILL.md"
GUIDE = ROOT / "docs" / "harness" / "lua-embedding-harness.md"
TRACKED_STATUS = ROOT / "docs" / "reports" / "lua-embedding-harness-status.md"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class LuaHarnessContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = load(MANIFEST)
        cls.contract = load(CONTRACT)
        cls.workflows = load(WORKFLOWS)
        cls.artifacts = load(ARTIFACTS)
        cls.validators = load(VALIDATORS)

    def test_manifest_components_exist(self):
        for name, relative in self.manifest["components"].items():
            self.assertTrue((ROOT / relative).exists(), f"{name}: {relative}")
        self.assertFalse(self.manifest["runtimeAuthority"]["productMutationAllowed"])
        self.assertFalse(self.manifest["runtimeAuthority"]["dependencyInstallationAllowed"])
        self.assertFalse(self.manifest["runtimeAuthority"]["runtimeExecutionAllowed"])

    def test_owner_supplied_design_principles_are_encoded(self):
        c = self.contract
        self.assertEqual(c["architecture"]["runtimeForm"], "embedded-library")
        self.assertTrue(c["architecture"]["hostOwnsMainLoop"])
        self.assertFalse(c["architecture"]["standaloneCliRequired"])
        self.assertTrue(c["stateIsolation"]["independentVmStatesRequired"])
        self.assertTrue(c["stateIsolation"]["explicitStateCloseRequired"])
        self.assertTrue(c["errorHandling"]["hostMustCatchScriptErrors"])
        self.assertTrue(c["errorHandling"]["protectedHostCallBoundaryRequired"])
        self.assertFalse(c["execution"]["jitRequired"])
        self.assertTrue(c["typeDiscipline"]["runtimeChecksAtHostBoundaryRequired"])
        self.assertEqual(c["sandbox"]["defaultLibraryPolicy"], "deny")
        self.assertEqual(c["sandbox"]["exposureModel"], "allow-list")
        self.assertEqual(set(c["sandbox"]["forbiddenLibrariesByDefault"]), {"os", "io", "package", "debug"})
        self.assertEqual(c["designPhilosophy"]["featureDefault"], "exclude")
        self.assertEqual(c["designPhilosophy"]["luaNativeIndexing"], "1-based")
        self.assertTrue(c["aiAuditability"]["humanReadableNonMagicalSnippetsRequired"])
        self.assertFalse(c["aiAuditability"]["implicitCapabilityAcquisitionAllowed"])

    def test_runtime_promotion_gate_is_not_handwaved(self):
        gates = "\n".join(self.contract["runtimePromotionGates"]).lower()
        for phrase in ("exact lua", "official embedding api", "create-run-close", "host catches script errors", "default sandbox denies", "resource limits", "teardown", "performance partition", "end-to-end runtime validation"):
            self.assertIn(phrase, gates)

    def test_workflow_registry_is_complete(self):
        expected = {"lua-task-intake", "lua-embedding-design-validation", "lua-sandbox-validation", "lua-failure-recovery", "lua-handoff"}
        actual = set()
        for entry in self.workflows["workflows"]:
            spec = ROOT / entry["spec"]
            self.assertTrue(spec.exists(), entry["spec"])
            parsed = load(spec)
            self.assertEqual(parsed["id"], entry["id"])
            self.assertTrue(parsed["trigger"])
            self.assertTrue(parsed["inputs"])
            self.assertTrue(parsed["steps"])
            self.assertTrue(parsed["outputs"])
            self.assertTrue(parsed["failureHandling"])
            self.assertTrue(parsed["proofCeiling"])
            actual.add(parsed["id"])
        self.assertEqual(actual, expected)

    def test_artifacts_are_local_and_proof_bounded(self):
        self.assertFalse(self.artifacts["generatedEvidenceTracked"])
        ids = {item["id"] for item in self.artifacts["artifacts"]}
        self.assertEqual(ids, {"operator-report", "readiness", "runtime-handoff"})
        text = "\n".join(item["proofCeiling"] for item in self.artifacts["artifacts"]).lower()
        self.assertIn("repository", text)
        self.assertIn("handoff", text)
        forbidden = set(self.artifacts["forbiddenEvidence"])
        self.assertIn("credentials", forbidden)
        self.assertIn("customer data", forbidden)

    def test_validator_registry_has_focused_and_repository_gates(self):
        commands = "\n".join(item["command"] for item in self.validators["validators"])
        self.assertIn("test_lua_harness_contracts.py", commands)
        self.assertIn("Test-LuaHarnessCompleteness.ps1", commands)
        self.assertIn("Get-LuaHarnessStatus.py --no-write", commands)
        self.assertIn("Test-AgentDocumentationContract.ps1", commands)
        self.assertIn("git diff --check", commands)
        self.assertEqual(self.validators["hookInstallation"], "manual-only; never installed implicitly")

    def test_safe_and_unsafe_fixtures_are_static_contract_inputs(self):
        safe = (HARNESS / "fixtures" / "sandbox-safe.lua").read_text(encoding="utf-8")
        unsafe = (HARNESS / "fixtures" / "sandbox-unsafe-os-access.lua").read_text(encoding="utf-8")
        for token in ("os.", "io.", "package.", "debug."):
            self.assertNotIn(token, safe)
        self.assertIn("os.", unsafe)
        self.assertIn("do not execute", unsafe.lower())

    def test_status_report_is_read_only_and_runtime_honest(self):
        completed = subprocess.run([sys.executable, str(STATUS), "--no-write", "--json"], cwd=ROOT, check=True, capture_output=True, text=True)
        payload = json.loads(completed.stdout)
        self.assertTrue(payload["contractReady"])
        self.assertFalse(payload["runtimeEmbedded"])
        self.assertFalse(payload["sandboxRuntimeProved"])
        self.assertFalse(payload["stateIsolationRuntimeProved"])
        self.assertIn("separately authorized", payload["nextAction"])

    def test_skill_and_operator_docs_expose_boundaries(self):
        skill = SKILL.read_text(encoding="utf-8")
        guide = GUIDE.read_text(encoding="utf-8")
        status = TRACKED_STATUS.read_text(encoding="utf-8")
        for heading in ("## Trigger", "## Inputs", "## Procedure", "## Outputs", "## Deterministic validation", "## Forbidden scope", "## Stop and escalate"):
            self.assertIn(heading, skill)
        for phrase in ("embedded library", "independent VM", "allow-list", "1-based", "AI"):
            self.assertIn(phrase.lower(), (skill + guide + status).lower())
        self.assertIn("runtime unproved", status.lower())
        self.assertIn("product code", skill.lower())

    def test_hooks_are_opt_in_and_do_not_install_themselves(self):
        for relative in self.validators["hooks"].values():
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertNotIn("git config core.hooksPath", text)
            self.assertNotIn("git clean", text)
            self.assertNotIn("reset --hard", text)
            self.assertNotIn("push --force", text)

    def test_source_attribution_is_not_overclaimed(self):
        basis = self.manifest["sourceBasis"]
        self.assertEqual(basis["kind"], "owner-supplied-technical-breakdown")
        self.assertFalse(basis["externallyVerifiedInThisSprint"])
        self.assertEqual(self.contract["basis"]["externalVerification"], "not-performed-in-this-harness-sprint")


if __name__ == "__main__":
    unittest.main()
