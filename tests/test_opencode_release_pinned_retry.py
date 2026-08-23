from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
RETRY = H / "Retry-OpenCodeRuntimeWithPinnedRelease.ps1"
MANIFEST = H / "manifest.json"
FAILURE_WORKFLOW = H / "workflows" / "failure-recovery.workflow.json"
ROOT_CMD = ROOT / "Test-OpenCodeLspHarness.cmd"
CI = ROOT / ".github" / "workflows" / "opencode-lsp-harness.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class TestOpenCodeReleasePinnedRetry(unittest.TestCase):
    def test_retry_is_evidence_gated_before_network_or_mutation(self) -> None:
        text = read(RETRY)
        for token in (
            "opencode-runtime-recovery.json",
            "OPENCODE_POST_INSTALL_MISSING",
            "installAttempted",
            "installerExitCode",
            "OPENCODE_PINNED_RETRY_NOT_APPLICABLE",
        ):
            self.assertIn(token, text, token)
        gate = text.index("if ([string]$priorReceipt.failureCode")
        release = text.index("$releaseApiUrl =")
        bootstrap = text.index("$bootstrapApiUrl =")
        self.assertLess(gate, release)
        self.assertLess(release, bootstrap)

    def test_release_is_selected_on_windows_and_forwarded_to_wsl(self) -> None:
        text = read(RETRY)
        for token in (
            "https://api.github.com/repos/anomalyco/opencode/releases/latest",
            "Invoke-RestMethod -Uri $releaseApiUrl",
            "-TimeoutSec $NetworkTimeoutSeconds",
            "^v(?<version>[0-9]+(?:\\.[0-9]+){2}",
            "$env:VERSION = $selectedVersion",
            "$env:WSLENV = ($wslEntries -join ':')",
            "$wslEntries += 'VERSION'",
            "OPENCODE_PINNED_RETRY_RELEASE_SOURCE=windows-github-api",
        ):
            self.assertIn(token, text, token)
        self.assertNotIn("OPENCODE_INSTALL_DIR", text)

    def test_retry_reenters_current_canonical_bootstrap_and_restores_environment(self) -> None:
        text = read(RETRY)
        for token in (
            "Invoke-AgentSwitchboardOpenCodeBootstrap.ps1",
            "FromBase64String",
            "& ([scriptblock]::Create($bootstrapText))",
            "finally {",
            "if ($hadVersion)",
            "Remove-Item Env:VERSION",
            "if ($hadWslEnv)",
            "Remove-Item Env:WSLENV",
        ):
            self.assertIn(token, text, token)
        self.assertLess(text.index("$env:VERSION = $selectedVersion"), text.index("& ([scriptblock]::Create($bootstrapText))"))
        self.assertLess(text.index("& ([scriptblock]::Create($bootstrapText))"), text.index("finally {"))

    def test_retry_does_not_expand_into_broad_workstation_setup(self) -> None:
        lower = read(RETRY).lower()
        for forbidden in (
            "setup-technicianagentswitchboard",
            "repair-technician-command-shims",
            "winget",
            "choco ",
            "scoop ",
            "apt install",
            "npm install",
            "git reset",
            "git clean",
            "push --force",
            "apikey",
            "password=",
        ):
            self.assertNotIn(forbidden, lower, forbidden)

    def test_manifest_and_failure_workflow_register_one_bounded_retry(self) -> None:
        manifest = json.loads(read(MANIFEST))
        recovery = manifest["runtimeRecovery"]
        self.assertEqual(
            "tooling/harness/operational/opencode-lsp-setup/Retry-OpenCodeRuntimeWithPinnedRelease.ps1",
            manifest["entrypoints"]["releasePinnedRuntimeRetry"],
        )
        self.assertEqual("windows-github-api", recovery["releaseSelectionOwner"])
        self.assertEqual(
            "https://api.github.com/repos/anomalyco/opencode/releases/latest",
            recovery["releaseMetadataUrl"],
        )
        self.assertEqual(30, recovery["releaseMetadataTimeoutSeconds"])
        self.assertTrue(recovery["releaseVersionForwardedThroughWslEnv"])
        self.assertTrue(recovery["releasePinnedRetryRequiresPriorMissingReceipt"])
        self.assertIn("moving latest-release discovery", recovery["proofRule"].lower())

        workflow = json.loads(read(FAILURE_WORKFLOW))
        joined = " ".join(workflow["steps"]).lower()
        self.assertIn("opencode_post_install_missing", joined)
        self.assertIn("release-pinned retry", joined)
        self.assertIn("windows host", joined)
        policy = workflow["failurePolicy"].lower()
        self.assertIn("release-pinned retry", policy)
        self.assertIn("attempted once", policy)

    def test_local_and_hosted_harnesses_run_this_contract_and_parse_retry(self) -> None:
        module = "tests.test_opencode_release_pinned_retry"
        self.assertIn(module, read(ROOT_CMD))
        ci = read(CI)
        self.assertIn("tests/test_opencode_release_pinned_retry.py", ci)
        self.assertIn(module, ci)
        self.assertIn("Retry-OpenCodeRuntimeWithPinnedRelease.ps1", ci)
        self.assertIn("Parser]::ParseFile", ci)


if __name__ == "__main__":
    unittest.main()
