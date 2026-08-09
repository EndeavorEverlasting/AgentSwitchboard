import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
MANIFEST = HARNESS / "manifest.json"
SELECTOR = HARNESS / "Select-FirstMateWorkflow.py"
REPORT_BUILDER = HARNESS / "Build-FirstMateHarnessReport.py"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class FirstMateOperationalHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = load(MANIFEST)
        cls.codebase = load(HARNESS / "codebase-map.json")
        cls.workflows = load(HARNESS / "workflow-registry.json")
        cls.artifacts = load(HARNESS / "artifact-registry.json")
        cls.validators = load(HARNESS / "validator-registry.json")

    def test_manifest_components_exist(self):
        for name, relative in self.manifest["components"].items():
            self.assertTrue((ROOT / relative).exists(), f"{name}: {relative}")

    def test_codebase_map_is_operational(self):
        structure = {entry["path"] for entry in self.codebase["structure"]}
        for expected in (".ai/skills", "tooling/harness", "tooling/firstmate", "tooling/profiles", "tests", "docs/harness"):
            self.assertIn(expected, structure)
        self.assertIn("crew_harness", self.codebase["entrypoints"])
        self.assertIn("windows_harness", self.codebase["entrypoints"])
        self.assertIn("windows_wsl_bridge", self.codebase["entrypoints"])
        self.assertIn("origin_normalizer", self.codebase["entrypoints"])
        self.assertIn("focused_test", self.codebase["commands"])
        self.assertIn("windows_contract", self.codebase["commands"])
        self.assertIn("deploy", self.codebase["commands"])
        traps = "\n".join(self.codebase["known_traps"])
        self.assertIn("Android readiness", traps)
        self.assertIn("Herdr", traps)
        self.assertIn("worktrees use a .git file", traps)
        self.assertIn("bare bash", traps.lower())
        self.assertIn("Windows path", traps)

    def test_workflow_registry_points_to_complete_specs(self):
        ids = set()
        for entry in self.workflows["workflows"]:
            spec = ROOT / entry["spec"]
            self.assertTrue(spec.exists(), entry["spec"])
            parsed = load(spec)
            self.assertEqual(parsed["id"], entry["id"])
            self.assertTrue(parsed["inputs"])
            self.assertTrue(parsed["steps"])
            self.assertTrue(parsed["outputs"])
            self.assertTrue(parsed["failure_handling"])
            ids.add(parsed["id"])
        self.assertEqual(
            ids,
            {
                "task-intake",
                "windows-laptop-validation",
                "crew-local-only",
                "pre-commit-validation",
                "failure-recovery",
                "handoff",
            },
        )

    def test_artifact_registry_has_real_generators_and_forbidden_evidence(self):
        self.assertEqual(self.artifacts["default_root"], "OS temporary directory/agentswitchboard/firstmate-harness")
        generators = "\n".join(item["generator"] for item in self.artifacts["artifacts"])
        self.assertIn("Build-FirstMateHarnessReport.py", generators)
        self.assertIn("Select-FirstMateWorkflow.py", generators)
        self.assertIn("Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1", generators)
        self.assertIn("credentials", self.artifacts["forbidden_evidence"])
        self.assertIn("private SSH keys", self.artifacts["forbidden_evidence"])

    def test_validator_registry_and_optional_hooks_exist(self):
        commands = "\n".join(item["command"] for item in self.validators["validators"])
        self.assertIn("test_firstmate_integration_contract.py", commands)
        self.assertIn("test_firstmate_operational_harness.py", commands)
        self.assertIn("test_firstmate_windows_harness_portability.py", commands)
        self.assertIn("test_firstmate_windows_wsl_bridge.py", commands)
        self.assertIn("Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode contract", commands)
        self.assertIn("test_operational_harness.py", commands)
        self.assertIn("Invoke-FirstMateHarnessPreCommit.sh", commands)
        self.assertIn("Invoke-FirstMateHarnessPrePush.sh", commands)
        self.assertEqual(self.validators["hook_installation"], "manual-only; this harness never installs Git hooks implicitly")
        for relative in self.validators["hooks"].values():
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("set -euo pipefail", text)
            for forbidden in ("git clean", "reset --hard", "push --force", "git push -f"):
                self.assertNotIn(forbidden, text)

    def route(self, *args):
        completed = subprocess.run(
            [sys.executable, str(SELECTOR), *args],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_selector_keeps_single_writer_direct(self):
        result = self.route("--parallel-writers", "1", "--firstmate-floor", "unproved", "--platform", "linux-wsl")
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["route"], "direct-asb")
        self.assertEqual(result["session_backend"], "tmux")

    def test_selector_blocks_parallel_firstmate_until_floor_passes(self):
        result = self.route("--parallel-writers", "3", "--firstmate-floor", "unproved", "--platform", "linux-wsl")
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["blocker"], "firstmate-floor-unproved")
        self.assertIn("Test-FirstMateInterop.sh", result["next_command"])

    def test_selector_allows_only_local_only_firstmate_after_floor(self):
        result = self.route("--parallel-writers", "3", "--firstmate-floor", "pass", "--platform", "linux-wsl")
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["route"], "firstmate-local-only")
        self.assertEqual(result["delivery_mode"], "local-only")
        self.assertIs(result["yolo_enabled"], False)
        self.assertEqual(result["session_backend"], "tmux")

    def test_selector_blocks_herdr_promotion(self):
        result = self.route(
            "--parallel-writers", "3", "--firstmate-floor", "pass", "--platform", "linux-wsl", "--request-herdr"
        )
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["blocker"], "herdr-selection-disabled")
        self.assertEqual(result["session_backend"], "tmux")

    def test_selector_does_not_make_android_a_laptop_dependency(self):
        result = self.route("--parallel-writers", "3", "--firstmate-floor", "pass", "--platform", "android")
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["route"], "direct-asb")
        self.assertIn("platform=android", result["reason"])

    def test_report_builder_outputs_human_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.md"
            completed = subprocess.run(
                [sys.executable, str(REPORT_BUILDER), "--output", str(output)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(Path(completed.stdout.strip()), output.resolve())
            text = output.read_text(encoding="utf-8")
            for heading in ("## Role boundaries", "## Working", "## Broken or blocked", "## Missing proof", "## Proof ceiling"):
                self.assertIn(heading, text)
            self.assertIn("do not wait for Android or Herdr readiness", text)
            self.assertIn("yolo_enabled: false", text)

    def test_agent_facing_python_tools_normalize_output_write_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            for tool, args, error_id in (
                (SELECTOR, ["--output", tmp], "firstmate-route-operational-error"),
                (REPORT_BUILDER, ["--output", tmp], "firstmate-report-operational-error"),
            ):
                completed = subprocess.run(
                    [sys.executable, str(tool), *args],
                    cwd=ROOT,
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(completed.returncode, 2)
                payload = json.loads(completed.stderr)
                self.assertEqual(payload["status"], "error")
                self.assertEqual(payload["error"], error_id)
                self.assertIn("next_command", payload)

    def test_skill_and_status_report_expose_handoff_boundary(self):
        skill = (ROOT / ".ai/skills/firstmate-crew-orchestration/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("## Trigger", skill)
        self.assertIn("## Inputs", skill)
        self.assertIn("## Outputs", skill)
        self.assertIn("## Deterministic validation", skill)
        self.assertIn("## Forbidden scope", skill)
        self.assertIn("first_safe_sprint.yolo_enabled", skill)
        self.assertIn("Test-AgentSwitchboard-FirstMate-Harness.ps1", skill)
        status = (ROOT / "docs/reports/firstmate-operational-harness-status.md").read_text(encoding="utf-8")
        self.assertIn("## Working", status)
        self.assertIn("## Broken or blocked", status)
        self.assertIn("## Missing", status)
        self.assertIn("bare Bash", status)

    def test_root_entrypoints_have_platform_specific_contracts(self):
        entry = (ROOT / "Test-AgentSwitchboard-FirstMate-Harness.sh").read_text(encoding="utf-8")
        for mode in ("contract)", "report)", "route)", "probe)"):
            self.assertIn(mode, entry)
        self.assertIn("git diff --cached --check", entry)

        windows = (ROOT / "Test-AgentSwitchboard-FirstMate-Harness.ps1").read_text(encoding="utf-8")
        self.assertIn("FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS", windows)
        self.assertIn("runtime-floor", windows)
        self.assertNotIn("bash", windows.lower())


if __name__ == "__main__":
    unittest.main()
