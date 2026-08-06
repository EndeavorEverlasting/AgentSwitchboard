import json
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/profiles/windows/harness/stale-checkout-exact-head"
MANIFEST = HARNESS / "manifest.json"
ENGINE = ROOT / "scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1"
CMD = ROOT / "Bootstrap-Technician-ExactHead.cmd"


class StaleCheckoutExactHeadBootstrapTests(unittest.TestCase):
    def test_manifest_registers_complete_tracked_harness(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        required_ids = {
            "bootstrap-cmd",
            "bootstrap-engine",
            "codebase-map",
            "artifact-registry",
            "workflow",
            "schema",
            "fixture",
            "operator-report-template",
            "status-reporter",
            "validator",
            "python-validator",
            "opt-in-hook",
            "skill",
            "operator-guide",
            "ci-workflow",
        }
        components = {item["id"]: item for item in manifest["components"]}
        self.assertEqual(required_ids, set(components))
        self.assertFalse(manifest["safety"]["sourceCheckoutMutationAllowed"])
        self.assertFalse(manifest["safety"]["forceFetchAllowed"])
        self.assertFalse(manifest["safety"]["generatedEvidenceTracked"])

        for item in components.values():
            path = ROOT / item["path"]
            self.assertTrue(path.is_file(), item["path"])
            tracked = subprocess.run(
                ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", item["path"]],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(0, tracked.returncode, item["path"])

    def test_json_contracts_parse_and_fixture_covers_failure_boundaries(self) -> None:
        paths = [
            HARNESS / "codebase-map.json",
            HARNESS / "artifact-registry.json",
            HARNESS / "workflows/bootstrap.workflow.json",
            HARNESS / "schemas/bootstrap-result.schema.json",
            HARNESS / "fixtures/bootstrap-cases.fixture.json",
        ]
        parsed = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
        fixtures = {case["expected"] for case in parsed[-1]["cases"]}
        self.assertEqual(
            {
                "PASS_EXACT_HEAD_DELEGATED",
                "BLOCKED_HEAD_MISMATCH",
                "BLOCKED_UNEXPECTED_ORIGIN",
                "PASS_SOURCE_PRESERVED",
                "BLOCKED_ARTIFACT_MISSING",
            },
            fixtures,
        )

    def test_engine_is_exact_ref_fail_closed_and_non_destructive(self) -> None:
        source = ENGINE.read_text(encoding="utf-8")
        required = [
            "ValidatePattern('^refs/heads/",
            "ValidatePattern('^[0-9a-fA-F]{40}$')",
            "'fetch', '--no-tags', 'origin', $RemoteRef",
            "'rev-parse', 'FETCH_HEAD'",
            "'show', $validatorSpec",
            "Invoke-TechnicianExactHeadValidation.ps1",
            "LastWriteTimeUtc -ge $startedUtc",
            "validation.verifiedHead",
            "validation.worktreeClean",
            "AGENT_SWITCHBOARD_NO_PAUSE",
            "Unexpected origin",
            "Remove-Item -LiteralPath $runnerPath",
        ]
        for token in required:
            self.assertIn(token, source)

        forbidden = [
            "git reset",
            "git clean",
            "git stash",
            "fetch --force",
            "checkout -f",
            "worktree remove --force",
            "StrictHostKeyChecking=no",
        ]
        lowered = source.lower()
        for token in forbidden:
            self.assertNotIn(token.lower(), lowered)

        self.assertNotIn("-Encoding utf8NoBOM", source)
        self.assertIn("New-Object Text.UTF8Encoding($false)", source)

    def test_engine_only_promotes_fresh_delegated_artifact(self) -> None:
        source = ENGINE.read_text(encoding="utf-8")
        self.assertRegex(source, r"Where-Object \{ \$_\.LastWriteTimeUtc -ge \$startedUtc \}")
        self.assertIn("$validation.status -ne 'passed'", source)
        self.assertIn("$Mode -eq 'ready' -and -not $validation.readinessRequested", source)
        self.assertIn("does not exceed the proof ceiling", source)

    def test_cmd_wrapper_uses_repo_owned_engine_and_propagates_exit(self) -> None:
        source = CMD.read_text(encoding="utf-8")
        self.assertIn("%~dp0scripts\\Invoke-StaleCheckoutExactHeadBootstrap.ps1", source)
        self.assertIn("where pwsh.exe", source)
        self.assertIn('set "RESULT=%ERRORLEVEL%"', source)
        self.assertIn("endlocal & exit /b %RESULT%", source)
        self.assertNotRegex(source, re.compile(r"(?im)^\s*PS\s+[^>]*>"))

    def test_operator_surfaces_are_privacy_safe(self) -> None:
        text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in ROOT.rglob("*")
            if path.is_file()
            and path != Path(__file__).resolve()
            and (
                "stale-checkout-exact-head" in path.as_posix()
                or path.name in {
                    "Bootstrap-Technician-ExactHead.cmd",
                    "Invoke-StaleCheckoutExactHeadBootstrap.ps1",
                    "Test-StaleCheckoutExactHeadBootstrap.ps1",
                    "test_stale_checkout_exact_head_bootstrap.py",
                }
            )
        )
        self.assertNotRegex(text, re.compile(r"(?i)C:\\Users\\[^\\\s]+"))
        self.assertNotIn("pa_rperez26", text.lower())
        self.assertNotIn("northwell", text.lower())


if __name__ == "__main__":
    unittest.main()
