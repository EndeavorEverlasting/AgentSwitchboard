from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
BOOTSTRAP = H / "Invoke-AgentSwitchboardOpenCodeBootstrap.ps1"
RESOLVER = H / "Resolve-AgentSwitchboardCheckout.ps1"
MANIFEST = H / "manifest.json"
DOCS = ROOT / "docs" / "harness" / "opencode-lsp-workstation-setup.md"
WORKFLOW = ROOT / ".github" / "workflows" / "opencode-lsp-harness.yml"


class TestOpenCodeCwdIndependentBootstrap(unittest.TestCase):
    def test_bootstrap_has_no_local_repo_path_dependency(self) -> None:
        text = BOOTSTRAP.read_text(encoding="utf-8")
        lower = text.lower()

        for token in (
            "$canonicalUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'",
            "function Invoke-BoundedProcess",
            "$symrefLines = @(Invoke-GitLines -Arguments @('ls-remote','--symref',$canonicalUrl,'HEAD'))",
            "$headLines = @(Invoke-GitLines -Arguments @('ls-remote',$canonicalUrl,\"refs/heads/$defaultBranch\"))",
            "$resolverUri = \"$rawBase/$expectedHead/$relativeRoot/Resolve-AgentSwitchboardCheckout.ps1\"",
            "Save-BoundedRemoteFile -Uri $resolverUri -Destination $resolverPath",
            "$resolverText = [IO.File]::ReadAllText($resolverPath)",
            "$resolverSupportsBranchAdvance = $resolverText -match '\\[switch\\]\\$AllowRemoteBranchAdvance'",
            "BOOTSTRAP_RESOLVER_SUPPORTS_BRANCH_ADVANCE=",
            "'-ExpectedBranch',$defaultBranch",
            "'-ExpectedHead',$expectedHead",
            "$resolutionResult = Invoke-BoundedProcess -FilePath $pwshPath",
            "BOOTSTRAP_CHECKOUT_RECOVERY_TIMEOUT",
            "Set-Location -LiteralPath $verifiedRoot",
            'Join-Path $verifiedRoot "$relativeRoot/Recover-OpenCodeRuntime.ps1"',
            "$runtimeResult = Invoke-BoundedProcess -FilePath $pwshPath",
            "BOOTSTRAP_RUNTIME_RECOVERY_TIMEOUT",
            "BOOTSTRAP_CALLER_LOCATION=",
            "BOOTSTRAP_RESOLVED_ROOT=",
            "BOOTSTRAP_VERIFIED_ORIGIN=",
            "BOOTSTRAP_VERIFIED_HEAD=",
            "BOOTSTRAP_ACTIVE_LOCATION=",
        ):
            self.assertIn(token, text, token)

        capability_guard = text.index("if ($resolverSupportsBranchAdvance)")
        switch_add = text.index("[void]$resolverArguments.Add('-AllowRemoteBranchAdvance')")
        self.assertLess(capability_guard, switch_add)
        self.assertLess(
            text.index("Set-Location -LiteralPath $verifiedRoot"),
            text.index('Join-Path $verifiedRoot "$relativeRoot/Recover-OpenCodeRuntime.ps1"'),
        )
        self.assertNotIn("-PreferredPath", text)
        self.assertNotIn("Recover-AgentSwitchboardCheckout.ps1", text)
        self.assertNotIn("\nexit ", text.lower())
        for forbidden in (
            "onedrive",
            "desktop\\dev",
            "desktop/dev",
            "pa_rperez",
            "opencode-lsp-harness-36f4660d",
            "opencode-lsp-harness-c6ddeb35",
        ):
            self.assertNotIn(forbidden, lower, forbidden)

    def test_bootstrap_network_and_child_stages_are_bounded(self) -> None:
        text = BOOTSTRAP.read_text(encoding="utf-8")
        for token in (
            "[ValidateRange(5, 120)][int]$NetworkTimeoutSeconds = 30",
            "[ValidateRange(30, 300)][int]$CheckoutTimeoutSeconds = 120",
            "$process.WaitForExit($ProcessTimeoutSeconds * 1000)",
            "$process.Kill($true)",
            "$client.Timeout = [TimeSpan]::FromSeconds($NetworkTimeoutSeconds)",
            "BOOTSTRAP_GIT_TIMEOUT",
            "BOOTSTRAP_STAGE_DOWNLOAD_TIMEOUT",
            "BOOTSTRAP_CHECKOUT_RECOVERY_TIMEOUT",
            "BOOTSTRAP_RUNTIME_RECOVERY_TIMEOUT",
        ):
            self.assertIn(token, text, token)
        self.assertNotIn("@(& $gitPath", text)

    def test_bootstrap_staging_is_exact_head_and_ephemeral(self) -> None:
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("[IO.Path]::GetTempPath()", text)
        self.assertIn("[IO.File]::WriteAllBytes($Destination, $bytes)", text)
        self.assertIn("Remove-Item -LiteralPath $stageRoot -Recurse -Force", text)
        self.assertIn("BOOTSTRAP_STAGE_DOWNLOAD_FAILED", text)
        self.assertIn("BOOTSTRAP_HEAD_MISMATCH", text)
        self.assertIn("BOOTSTRAP_WORKTREE_NOT_CLEAN", text)
        self.assertNotIn("git reset", text.lower())
        self.assertNotIn("git clean", text.lower())
        self.assertNotIn("git stash", text.lower())
        self.assertNotIn("push --force", text.lower())

    def test_resolver_preserves_selected_snapshot_across_normal_branch_advance(self) -> None:
        text = RESOLVER.read_text(encoding="utf-8")
        for token in (
            "[switch]$AllowRemoteBranchAdvance",
            "if (-not $AllowRemoteBranchAdvance)",
            "merge-base --is-ancestor $ExpectedHead",
            "EXPECTED_HEAD_NO_LONGER_REACHABLE",
            "$remoteAdvancedAfterSnapshot = $true",
            "allowRemoteBranchAdvance = [bool]$AllowRemoteBranchAdvance",
            "remoteHeadAtResolution = $remoteHeadAtResolution",
            "remoteAdvancedAfterSnapshot = $remoteAdvancedAfterSnapshot",
        ):
            self.assertIn(token, text, token)
        self.assertIn("REMOTE_HEAD_MISMATCH", text, "strict existing callers must remain fail-closed")

    def test_manifest_registers_location_free_operator_entrypoint(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        recovery = manifest["repositoryRecovery"]
        self.assertEqual(17, manifest["schemaVersion"])
        self.assertEqual(
            "tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1",
            manifest["entrypoints"]["cwdIndependentBootstrap"],
        )
        self.assertTrue(recovery["operatorInvocationCwdIndependent"])
        self.assertFalse(recovery["knownLocalRepoPathRequired"])
        self.assertTrue(recovery["bootstrapStagesExactDefaultHeadResolver"])
        self.assertTrue(recovery["bootstrapResolvesRemoteHeadOnce"])
        self.assertEqual(30, recovery["bootstrapNetworkTimeoutSeconds"])
        self.assertEqual(120, recovery["bootstrapCheckoutTimeoutSeconds"])
        self.assertIn("current directory", recovery["proofRule"].lower())
        self.assertIn("remote identity", recovery["proofRule"].lower())
        self.assertIn("resolved once", recovery["proofRule"].lower())
        self.assertIn("bounded", recovery["proofRule"].lower())
        self.assertIn("ancestor", recovery["proofRule"].lower())

    def test_operator_guide_starts_with_location_free_bootstrap(self) -> None:
        text = DOCS.read_text(encoding="utf-8")
        lower = text.lower()
        self.assertIn("run from any powershell directory", lower)
        self.assertIn(
            "https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1",
            text,
        )
        self.assertIn("-TimeoutSec 30", text)
        self.assertIn("FromBase64String", text)
        self.assertIn("Set-Location -LiteralPath", text)
        self.assertIn("BOOTSTRAP_VERIFIED_ORIGIN", text)
        self.assertIn("BOOTSTRAP_VERIFIED_HEAD", text)
        self.assertIn("exact head once", lower)
        self.assertIn("ancestor", lower)

    def test_windows_smoke_normalizes_git_and_powershell_paths(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("[IO.Path]::GetFullPath([string](Get-Location).Path)", text)
        self.assertIn("[IO.Path]::GetFullPath(([string](git rev-parse --show-toplevel)).Trim())", text)
        self.assertIn("[StringComparison]::OrdinalIgnoreCase", text)
        self.assertNotIn("if ($active -ne $top)", text)
        self.assertIn("if ($origin -ne $canonical)", text)
        self.assertIn("if ($head -notmatch '^[0-9a-f]{40}$')", text)
        self.assertNotIn("git ls-remote $canonical HEAD", text)
        self.assertNotIn("if ($head -ne $remoteHead)", text)


if __name__ == "__main__":
    unittest.main()
