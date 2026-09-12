import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SYNC = ROOT / "tooling" / "profiles" / "windows" / "Sync-PromptKitWebsite.ps1"
MANAGER = ROOT / "tooling" / "profiles" / "windows" / "Manage-PromptKitWebsiteSchedule.ps1"
MANIFEST = ROOT / "tooling" / "profiles" / "windows" / "harness" / "prompt-kit-sync" / "prompt-kit-sync.manifest.json"
MAP = ROOT / "tooling" / "profiles" / "windows" / "harness" / "prompt-kit-sync" / "codebase-map.json"
CMD = ROOT / "PromptKit-Website-Sync.cmd"
DOC = ROOT / "docs" / "harness" / "prompt-kit-scheduled-sync.md"


class PromptKitScheduledSyncContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sync = SYNC.read_text(encoding="utf-8")
        cls.manager = MANAGER.read_text(encoding="utf-8")
        cls.manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        cls.codebase_map = json.loads(MAP.read_text(encoding="utf-8"))
        cls.cmd = CMD.read_text(encoding="utf-8")
        cls.doc = DOC.read_text(encoding="utf-8")

    def test_required_files_and_manifest_identity(self):
        for path in (SYNC, MANAGER, MANIFEST, MAP, CMD, DOC):
            self.assertTrue(path.is_file(), path)
        self.assertEqual(self.manifest["id"], "prompt-kit-scheduled-sync")
        self.assertFalse(self.manifest["consent"]["defaultEnabled"])
        self.assertTrue(self.manifest["consent"]["networkRequiresEnabledToggle"])
        self.assertEqual(self.manifest["schedule"]["runLevel"], "limited")
        self.assertEqual(self.manifest["source"]["versionIdentity"], "remote-default-branch-commit-sha")

    def test_network_poll_is_guarded_by_enabled_toggle(self):
        disabled_gate = self.sync.index("if (-not [bool]$config.enabled)")
        remote_poll_call = self.sync.index("$remote = Get-RemoteDefaultHead")
        self.assertLess(disabled_gate, remote_poll_call)
        self.assertIn("No network request was made.", self.sync)
        self.assertIn("git ls-remote --symref", self.doc)

    def test_remote_default_branch_and_exact_sha_are_version_identity(self):
        self.assertIn("'ls-remote', '--symref', $RepositoryUrl, 'HEAD'", self.sync)
        self.assertRegex(self.sync, r"refs/heads/\(\?<branch>")
        self.assertIn("[0-9a-fA-F]{40}", self.sync)
        self.assertNotIn("$DefaultBranch = 'main'", self.sync)
        self.assertEqual(self.manifest["source"]["versionIdentity"], "remote-default-branch-commit-sha")

    def test_managed_checkout_is_fail_closed_and_fast_forward_only(self):
        required = [
            "'status', '--porcelain'",
            "'fetch', 'origin', $Branch, '--prune'",
            "'merge-base', '--is-ancestor'",
            "'merge', '--ff-only'",
            "No reset, clean, checkout overwrite, or discard was attempted.",
        ]
        for token in required:
            self.assertIn(token, self.sync)
        forbidden = ["git reset", "git clean", "reset --hard", "checkout -f", "push --force"]
        lowered = self.sync.lower()
        for token in forbidden:
            self.assertNotIn(token, lowered)
        self.assertTrue(self.manifest["safety"]["developerCheckoutUntouched"])
        self.assertEqual(self.manifest["safety"]["dirtyManagedCheckoutBehavior"], "fail-closed")

    def test_upstream_generator_is_the_validation_owner(self):
        self.assertIn("scripts\\build_prompt_kit_registry.py", self.sync)
        self.assertIn("web\\prompt-kit\\index.html", self.sync)
        self.assertIn("'--check'", self.sync)
        self.assertEqual(
            self.manifest["source"]["upstreamValidation"],
            "scripts/build_prompt_kit_registry.py --output web/prompt-kit/index.html --check",
        )

    def test_published_artifact_is_sha_addressed_and_hash_verified(self):
        self.assertIn("Get-FileHash", self.sync)
        self.assertIn("-Algorithm SHA256", self.sync)
        self.assertIn("Join-Path $ReleaseRoot $SourceSha", self.sync)
        self.assertIn("website\\releases\\<source-sha>\\index.html", self.doc)
        self.assertEqual(self.manifest["localState"]["defaultRetentionCount"], 2)

    def test_scheduler_is_explicit_limited_and_reversible(self):
        enable = self.manager.index("'Enable' {")
        register = self.manager.index("Register-ScheduledTask", enable)
        self.assertLess(enable, register)
        self.assertIn("-LogonType Interactive -RunLevel Limited", self.manager)
        self.assertIn("-MultipleInstances IgnoreNew", self.manager)
        self.assertIn("-ExecutionTimeLimit (New-TimeSpan -Minutes 10)", self.manager)

        disable = self.manager.index("'Disable' {")
        disable_toggle = self.manager.index("Write-Config -Enabled $false", disable)
        unregister = self.manager.index("Unregister-ScheduledTask", disable)
        self.assertLess(disable_toggle, unregister)
        self.assertIn("Copy-Item -LiteralPath $SourceSyncScript -Destination $RuntimeSyncScript", self.manager)

    def test_schedule_cannot_be_installed_by_status_or_poll(self):
        self.assertNotIn("Register-ScheduledTask", self.sync)
        self.assertEqual(self.manager.count("Register-ScheduledTask -TaskName"), 1)
        self.assertIn("[string]$Action = 'Status'", self.manager)
        self.assertIn("PromptKit-Website-Sync.cmd Enable", self.doc)
        self.assertIn("PromptKit-Website-Sync.cmd Disable", self.doc)

    def test_state_is_committed_before_old_release_pruning(self):
        state_write = self.sync.index("Write-JsonAtomic -Value $newState -Path $StatePath")
        prune = self.sync.index("Prune-PromptKitReleases -CurrentSourceSha $sourceSha")
        self.assertLess(state_write, prune)
        self.assertIn("known-good website intact", self.sync)

    def test_enable_consent_is_committed_after_task_registration(self):
        enable = self.manager.index("'Enable' {")
        register = self.manager.index("Register-ScheduledTask -TaskName", enable)
        enabled_write = self.manager.index("Write-Config -Enabled $true", enable)
        self.assertLess(register, enabled_write)

    def test_root_front_door_propagates_exit_code(self):
        self.assertIn("Manage-PromptKitWebsiteSchedule.ps1", self.cmd)
        self.assertIn("Status", self.cmd)
        self.assertIn("exit /b %ERRORLEVEL%", self.cmd)

    def test_no_embedded_secret_or_machine_specific_profile(self):
        joined = "\n".join((self.sync, self.manager, self.cmd, self.doc))
        secret_patterns = [r"ghp_[A-Za-z0-9]", r"github_pat_", r"BEGIN (?:RSA|OPENSSH) PRIVATE KEY"]
        for pattern in secret_patterns:
            self.assertIsNone(re.search(pattern, joined))
        for machine_name in ("admin-box-1", "admin-box-2", "p-top", "ptop"):
            self.assertNotIn(machine_name, joined.lower())
        self.assertIn("machine-local and user-local", self.doc)

    def test_codebase_map_exposes_all_operator_journeys(self):
        self.assertEqual(
            set(self.codebase_map["operatorJourneys"]),
            {"enable", "status", "pollNow", "open", "disable"},
        )
        self.assertEqual(self.codebase_map["callStack"][0], "PromptKit-Website-Sync.cmd")


if __name__ == "__main__":
    unittest.main()
