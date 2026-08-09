import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py"
STATUS_REPORTER = ROOT / "tooling/harness/operational/Get-OperationalHarnessStatus.py"

REQUIRED = [
    "tooling/harness/operational/execution-actor-routing/manifest.json",
    "tooling/harness/operational/execution-actor-routing/codebase-map.json",
    "tooling/harness/operational/execution-actor-routing/artifact-registry.json",
    "tooling/harness/operational/execution-actor-routing/workflows/bind-execute-verify.workflow.json",
    "tooling/harness/operational/execution-actor-routing/schemas/execution-actor-binding.schema.json",
    "tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py",
    "tooling/harness/operational/execution-actor-routing/hooks/Invoke-ExecutionActorRoutingPreCommit.ps1",
    "tooling/harness/operational/execution-actor-routing/hooks/Invoke-ExecutionActorRoutingPrePush.ps1",
    ".ai/skills/execution-actor-routing/SKILL.md",
    "docs/harness/execution-actor-routing.md",
    "scripts/Test-ExecutionActorRoutingHarness.ps1",
    ".github/workflows/execution-actor-routing-harness.yml",
]


def digest_binding(path: Path) -> str:
    payload = json.loads(path.read_text(encoding="utf-8"))
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class ExecutionActorRoutingHarnessTests(unittest.TestCase):
    def test_required_components_exist(self):
        for relative in REQUIRED:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_json_contracts_parse(self):
        for relative in [
            "tooling/harness/operational/execution-actor-routing/manifest.json",
            "tooling/harness/operational/execution-actor-routing/codebase-map.json",
            "tooling/harness/operational/execution-actor-routing/artifact-registry.json",
            "tooling/harness/operational/execution-actor-routing/workflows/bind-execute-verify.workflow.json",
            "tooling/harness/operational/execution-actor-routing/schemas/execution-actor-binding.schema.json",
        ]:
            json.loads((ROOT / relative).read_text(encoding="utf-8"))

    def test_root_registries_route_actor_harness(self):
        self.assertIn("executionActorRoutingHarness", (ROOT / "tooling/harness/operational/manifest.json").read_text(encoding="utf-8"))
        self.assertIn("execution-actor-routing", (ROOT / "tooling/harness/operational/workflow-registry.json").read_text(encoding="utf-8"))
        self.assertIn("execution-actor-routing", (ROOT / "tooling/harness/operational/validator-registry.json").read_text(encoding="utf-8"))
        self.assertIn("execution-actor-binding", (ROOT / "tooling/harness/operational/execution-actor-routing/artifact-registry.json").read_text(encoding="utf-8"))

    def run_runner(self, *args):
        return subprocess.run([sys.executable, str(RUNNER), *args], cwd=ROOT, text=True, capture_output=True)

    def test_explicit_agentswitchboard_binding_passes_and_emits_digest(self):
        with tempfile.TemporaryDirectory() as td:
            result = self.run_runner(
                "bind", "--requested-actor", "agentswitchboard", "--selected-actor", "agentswitchboard",
                "--selection-source", "user-explicit", "--task", "merge validated PR", "--operation", "merge PR 123",
                "--output-root", td,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            binding_path = Path(td) / "execution-actor-binding.json"
            binding = json.loads(binding_path.read_text(encoding="utf-8"))
            self.assertEqual(binding["status"], "actor-bound")
            self.assertEqual(binding["selectedActor"], "agentswitchboard")
            self.assertIn(f"BINDING_SHA256={digest_binding(binding_path)}", result.stdout)

    def test_explicit_actor_substitution_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            result = self.run_runner(
                "bind", "--requested-actor", "agentswitchboard", "--selected-actor", "chatgpt",
                "--selection-source", "user-explicit", "--task", "merge validated PR", "--operation", "merge PR 123",
                "--output-root", td,
            )
            self.assertEqual(result.returncode, 9)
            binding = json.loads((Path(td) / "execution-actor-binding.json").read_text(encoding="utf-8"))
            self.assertEqual(binding["status"], "actor-mismatch")

    def test_auto_requires_reason(self):
        with tempfile.TemporaryDirectory() as td:
            result = self.run_runner(
                "bind", "--requested-actor", "auto", "--selected-actor", "chatgpt",
                "--selection-source", "context-inferred", "--task", "update PR metadata", "--operation", "edit PR body",
                "--output-root", td,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("selection-reason", result.stderr)

    def test_actual_actor_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            bind = self.run_runner(
                "bind", "--requested-actor", "agentswitchboard", "--selected-actor", "agentswitchboard",
                "--selection-source", "user-explicit", "--task", "merge validated PR", "--operation", "merge PR 123",
                "--output-root", td,
            )
            self.assertEqual(bind.returncode, 0, bind.stderr)
            binding_path = Path(td) / "execution-actor-binding.json"
            verify = self.run_runner(
                "verify", "--binding", str(binding_path), "--expected-binding-sha256", digest_binding(binding_path),
                "--actual-actor", "chatgpt", "--evidence", "github-connector-result:merged",
            )
            self.assertEqual(verify.returncode, 10)
            receipt = json.loads((Path(td) / "execution-actor-receipt.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "actor-mismatch")

    def test_matching_actual_actor_verifies(self):
        with tempfile.TemporaryDirectory() as td:
            bind = self.run_runner(
                "bind", "--requested-actor", "chatgpt", "--selected-actor", "chatgpt",
                "--selection-source", "user-explicit", "--task", "update repository", "--operation", "create PR",
                "--output-root", td,
            )
            self.assertEqual(bind.returncode, 0, bind.stderr)
            binding_path = Path(td) / "execution-actor-binding.json"
            verify = self.run_runner(
                "verify", "--binding", str(binding_path), "--expected-binding-sha256", digest_binding(binding_path),
                "--actual-actor", "chatgpt", "--evidence", "github-pr:123",
            )
            self.assertEqual(verify.returncode, 0, verify.stderr)
            receipt = json.loads((Path(td) / "execution-actor-receipt.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["status"], "actor-verified")
            self.assertEqual(receipt["bindingSha256"], digest_binding(binding_path))

    def test_tampered_binding_cannot_be_verified_with_original_digest(self):
        with tempfile.TemporaryDirectory() as td:
            bind = self.run_runner(
                "bind", "--requested-actor", "agentswitchboard", "--selected-actor", "agentswitchboard",
                "--selection-source", "user-explicit", "--task", "merge validated PR", "--operation", "merge PR 123",
                "--output-root", td,
            )
            self.assertEqual(bind.returncode, 0, bind.stderr)
            binding_path = Path(td) / "execution-actor-binding.json"
            original_digest = digest_binding(binding_path)
            payload = json.loads(binding_path.read_text(encoding="utf-8"))
            payload["requestedActor"] = "chatgpt"
            payload["selectedActor"] = "chatgpt"
            binding_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
            verify = self.run_runner(
                "verify", "--binding", str(binding_path), "--expected-binding-sha256", original_digest,
                "--actual-actor", "chatgpt", "--evidence", "github-pr:123",
            )
            self.assertEqual(verify.returncode, 2)
            self.assertIn("binding digest mismatch", verify.stderr)
            self.assertFalse((Path(td) / "execution-actor-receipt.json").exists())

    def test_status_reporter_routes_explicit_agentswitchboard_task(self):
        with tempfile.TemporaryDirectory() as td:
            result = subprocess.run(
                [sys.executable, str(STATUS_REPORTER), "--task", "have AgentSwitchboard merge PR 123", "--output-root", td],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            status = json.loads((Path(td) / "operational-harness-status.json").read_text(encoding="utf-8"))
            self.assertEqual(status["routing"]["specializedSkill"], ".ai/skills/execution-actor-routing/SKILL.md")

    def test_skill_forbids_silent_substitution(self):
        skill = (ROOT / ".ai/skills/execution-actor-routing/SKILL.md").read_text(encoding="utf-8").lower()
        self.assertIn("do not silently substitute", skill)
        self.assertIn("direct github connector evidence", skill)
        self.assertIn("expected-binding-sha256", skill)
        self.assertIn("agentswitchboard", skill)

    def test_no_destructive_git_in_new_harness(self):
        for relative in REQUIRED:
            text = (ROOT / relative).read_text(encoding="utf-8").lower()
            self.assertNotIn("git reset --hard", text)
            self.assertNotIn("git clean -fd", text)
            self.assertNotIn("git push --force", text)


if __name__ == "__main__":
    unittest.main()
