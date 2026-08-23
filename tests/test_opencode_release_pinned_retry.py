from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
RETRY = H / "Retry-OpenCodeRuntimeWithPinnedRelease.ps1"
MANIFEST = H / "manifest.json"
ARTIFACTS = H / "artifact-registry.json"
FAILURE_WORKFLOW = H / "workflows" / "failure-recovery.workflow.json"
DOCS = ROOT / "docs" / "harness" / "opencode-lsp-workstation-setup.md"
ROOT_CMD = ROOT / "Test-OpenCodeLspHarness.cmd"
CI = ROOT / ".github" / "workflows" / "opencode-lsp-harness.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class TestOpenCodeReleasePinnedRetry(unittest.TestCase):
    def test_retry_is_distribution_bound_and_evidence_gated(self) -> None:
        text = read(RETRY)
        for token in (
            "function Get-RuntimeReceiptsForDistribution",
            "RequestedDistribution",
            "receipt.distribution",
            "OPENCODE_PINNED_RETRY_DISTRIBUTION_MISMATCH",
            "OPENCODE_POST_INSTALL_MISSING",
            "installAttempted",
            "installerExitCode",
            "OPENCODE_PINNED_RETRY_NOT_APPLICABLE",
        ):
            self.assertIn(token, text, token)
        selection = text.index("$selectedEvidence = $distributionReceipts[0]")
        gate = text.index("if ([string]$priorReceipt.failureCode")
        release = text.index("$releaseApiUrl =")
        self.assertLess(selection, gate)
        self.assertLess(gate, release)

    def test_retry_claim_is_atomic_and_precedes_network_mutation(self) -> None:
        text = read(RETRY)
        for token in (
            "$claimRoot = Join-Path $stateRoot 'retry-claims'",
            "$claimPath = Join-Path $claimRoot \"$priorRunId.claim\"",
            "[IO.FileMode]::CreateNew",
            "[IO.FileShare]::None",
            "OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED",
            "agentswitchboard.opencode-release-pinned-retry-claim.v1",
            "secretOrEnvironmentDumpPersisted = $false",
        ):
            self.assertIn(token, text, token)
        claim = text.index("[IO.File]::Open($claimPath")
        release = text.index("Invoke-RestMethod -Uri $releaseApiUrl")
        dispatch = text.index("& ([scriptblock]::Create($bootstrapText))")
        self.assertLess(claim, release)
        self.assertLess(claim, dispatch)

    def test_retry_artifact_is_isolated_and_binds_all_new_result_runs(self) -> None:
        text = read(RETRY)
        for token in (
            "opencode-release-pinned-retry.json",
            "$retryRunId =",
            "$retryRunRoot = Join-Path $runtimeRunsRoot $retryRunId",
            "New-Item -ItemType Directory -Path $retryRunRoot -Force",
            "$attemptPath = Join-Path $retryRunRoot 'opencode-release-pinned-retry.json'",
            "retryRunId = $retryRunId",
            "sourceRunId",
            "resultRunId",
            "resultRunIds",
            "completed-with-runtime-receipt",
            "completed-with-ambiguous-runtime-receipts",
            "completed-without-new-runtime-receipt",
            "OPENCODE_PINNED_RETRY_SOURCE_STALE",
        ):
            self.assertIn(token, text, token)
        marker_write = text.index("$attemptReceipt | ConvertTo-Json")
        dispatch = text.index("& ([scriptblock]::Create($bootstrapText))")
        self.assertLess(marker_write, dispatch)
        self.assertIn("$resultRunIds -contains $priorRunId", text)
        self.assertIn("$_ -notin $preexistingRunIds", text)
        self.assertNotIn("Join-Path (Split-Path -Parent $latestReceiptPath) 'opencode-release-pinned-retry.json'", text)

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
        dispatch = text.index("& ([scriptblock]::Create($bootstrapText))")
        cleanup = text.index("finally {", dispatch)
        version_restore = text.index("if ($hadVersion)", cleanup)
        wslenv_restore = text.index("if ($hadWslEnv)", cleanup)
        self.assertLess(text.index("$env:VERSION = $selectedVersion"), dispatch)
        self.assertLess(dispatch, cleanup)
        self.assertLess(cleanup, version_restore)
        self.assertLess(cleanup, wslenv_restore)

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

    def test_manifest_artifacts_and_failure_workflow_register_one_bounded_retry(self) -> None:
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
        self.assertEqual("opencode-release-pinned-retry.json", recovery["releasePinnedRetryAttemptArtifact"])
        self.assertEqual(
            "%LOCALAPPDATA%/AgentSwitchboard/opencode-lsp/runs/<retry-run-id>",
            recovery["releasePinnedRetryAttemptRoot"],
        )
        self.assertTrue(recovery["releasePinnedRetrySingleAttemptEnforced"])
        self.assertTrue(recovery["releasePinnedRetryDistributionBound"])
        self.assertEqual(
            "%LOCALAPPDATA%/AgentSwitchboard/opencode-lsp/retry-claims/<source-run-id>.claim",
            recovery["releasePinnedRetryClaim"],
        )
        proof = recovery["proofRule"].lower()
        self.assertIn("moving latest-release discovery", proof)
        self.assertIn("requested distribution", proof)
        self.assertIn("atomic", proof)
        self.assertIn("retryrunid", proof)
        self.assertIn("sourcerunid", proof)
        self.assertIn("resultrunids", proof)
        self.assertIn("without mutating either runtime-recovery run", proof)
        self.assertIn("already_attempted", proof)

        artifacts = json.loads(read(ARTIFACTS))
        retry_artifacts = [a for a in artifacts["artifacts"] if a["artifactId"] == "release-pinned-retry-json"]
        self.assertEqual(1, len(retry_artifacts))
        self.assertEqual("opencode-release-pinned-retry.json", retry_artifacts[0]["fileName"])

        workflow = json.loads(read(FAILURE_WORKFLOW))
        joined = " ".join(workflow["steps"]).lower()
        self.assertIn("opencode_post_install_missing", joined)
        self.assertIn("release-pinned retry", joined)
        self.assertIn("windows host", joined)
        policy = workflow["failurePolicy"].lower()
        self.assertIn("release-pinned retry", policy)
        self.assertIn("attempted once", policy)

    def test_operator_guide_has_location_free_retry_and_stop_condition(self) -> None:
        docs = read(DOCS)
        lower = docs.lower()
        self.assertIn("release-pinned retry after a missing binary", lower)
        self.assertIn("Retry-OpenCodeRuntimeWithPinnedRelease.ps1", docs)
        self.assertIn(
            "https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Retry-OpenCodeRuntimeWithPinnedRelease.ps1",
            docs,
        )
        self.assertIn("OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED", docs)
        self.assertIn("opencode-release-pinned-retry.json", docs)
        self.assertIn("run it from any powershell directory", lower)
        self.assertIn("own retry run directory", lower)
        self.assertIn("requested wsl distribution", lower)
        self.assertIn("atomic claim", lower)

    def test_local_and_hosted_harnesses_run_this_contract_and_parse_retry(self) -> None:
        module = "tests.test_opencode_release_pinned_retry"
        self.assertIn(module, read(ROOT_CMD))
        ci = read(CI)
        self.assertIn("tests/test_opencode_release_pinned_retry.py", ci)
        self.assertIn(module, ci)
        self.assertIn("Retry-OpenCodeRuntimeWithPinnedRelease.ps1", ci)
        self.assertIn("Join-Path $env:GITHUB_WORKSPACE", ci)
        self.assertIn("Parser]::ParseFile", ci)


if __name__ == "__main__":
    unittest.main()
