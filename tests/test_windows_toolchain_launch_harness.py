import json
import os
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HARNESS_ROOT = os.path.join(REPO_ROOT, "tooling", "profiles", "windows", "harness", "technician-live-cert")
MANIFEST = os.path.join(HARNESS_ROOT, "manifest.json")
ARTIFACTS = os.path.join(HARNESS_ROOT, "artifact-registry.json")
MAP = os.path.join(HARNESS_ROOT, "codebase-map.json")
FAILURE_WORKFLOW = os.path.join(HARNESS_ROOT, "workflows", "field-failure-repair.workflow.json")
SCRIPT = os.path.join(REPO_ROOT, "scripts", "Test-WindowsToolchainLaunch.ps1")
CMD = os.path.join(REPO_ROOT, "Test-Technician-Toolchain-Preflight.cmd")


def text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def data(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


class TestWindowsToolchainLaunchHarness(unittest.TestCase):
    def test_manifest_registers_preflight_and_guard(self):
        manifest = data(MANIFEST)
        self.assertEqual("Test-Technician-Toolchain-Preflight.cmd", manifest["entrypoints"]["toolchainPreflightCmd"])
        self.assertEqual("scripts/Test-WindowsToolchainLaunch.ps1", manifest["entrypoints"]["toolchainPreflightValidator"])
        ids = {item["id"] for item in manifest["components"]}
        self.assertIn("toolchain-preflight-cmd", ids)
        self.assertIn("toolchain-preflight-validator", ids)
        guards = {item["id"] for item in manifest["knownFailureGuards"]}
        self.assertIn("git-executable-launch-blocked", guards)

    def test_preflight_executes_concrete_git_with_bounded_wait(self):
        script = text(SCRIPT)
        for token in [
            "Get-Command git.exe -All",
            "System.Diagnostics.ProcessStartInfo",
            "$psi.UseShellExecute = $false",
            "$psi.RedirectStandardOutput = $true",
            "$process.WaitForExit($TimeoutSeconds * 1000)",
            "$psi.Arguments = '--version'",
            "windows-toolchain-launch-preflight.json",
            "windows-toolchain-launch-preflight.md",
            "git-executable-launch-and-version-observed",
        ]:
            self.assertIn(token, script)
        self.assertIn("[ValidateRange(1,30)][int]$TimeoutSeconds = 5", script)

    def test_cmd_wrapper_preserves_child_exit(self):
        wrapper = text(CMD)
        for token in [
            'set "ERRORLEVEL="',
            'set "RESULT=0"',
            "where pwsh.exe",
            "scripts\\Test-WindowsToolchainLaunch.ps1",
            'set "RESULT=%ERRORLEVEL%"',
            "endlocal & exit /b %RESULT%",
        ]:
            self.assertIn(token, wrapper)

    def test_artifacts_are_local_untracked_diagnostics(self):
        registry = data(ARTIFACTS)
        by_id = {item["artifactId"]: item for item in registry["artifacts"]}
        for artifact_id in ["toolchain-launch-preflight-json", "toolchain-launch-preflight-report"]:
            artifact = by_id[artifact_id]
            self.assertFalse(artifact["tracked"])
            self.assertEqual("local-operational", artifact["sensitivity"])
            self.assertIn("Git executable", artifact["proofCeiling"])

    def test_map_and_failure_workflow_block_fetch_until_launch_proof(self):
        mapping = data(MAP)
        self.assertIn("Test-Technician-Toolchain-Preflight.cmd", json.dumps(mapping["entrypoints"]))
        self.assertIn("PATH resolution does not prove Windows can launch", "\n".join(mapping["knownTraps"]))
        workflow = json.dumps(data(FAILURE_WORKFLOW))
        self.assertIn("before any fetch, pull, or worktree operation", workflow)
        self.assertIn("PATH/Get-Command presence alone is insufficient", workflow)
        self.assertIn("Windows cannot launch any concrete Git executable", workflow)


if __name__ == "__main__":
    unittest.main()
