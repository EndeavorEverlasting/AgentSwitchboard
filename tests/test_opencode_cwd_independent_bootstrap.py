from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
BOOTSTRAP = H / "Invoke-AgentSwitchboardOpenCodeBootstrap.ps1"
MANIFEST = H / "manifest.json"
DOCS = ROOT / "docs" / "harness" / "opencode-lsp-workstation-setup.md"


class TestOpenCodeCwdIndependentBootstrap(unittest.TestCase):
    def test_bootstrap_has_no_local_repo_path_dependency(self) -> None:
        text = BOOTSTRAP.read_text(encoding="utf-8")
        lower = text.lower()

        for token in (
            "$canonicalUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'",
            "git @Arguments",
            "$symrefLines = @(Invoke-GitLines -Arguments @('ls-remote','--symref',$canonicalUrl,'HEAD'))",
            "$headLines = @(Invoke-GitLines -Arguments @('ls-remote',$canonicalUrl,\"refs/heads/$defaultBranch\"))",
            "$rawBase/$expectedHead/$relativeRoot/$name",
            "'Recover-AgentSwitchboardCheckout.ps1'",
            "'Resolve-AgentSwitchboardCheckout.ps1'",
            "$resolutionLine = & pwsh -NoLogo -NoProfile -File $checkoutRouter",
            "git -C $resolved rev-parse --show-toplevel",
            "git -C $verifiedRoot remote get-url origin",
            "git -C $verifiedRoot rev-parse HEAD",
            "git -C $verifiedRoot status --porcelain=v1",
            "Set-Location -LiteralPath $verifiedRoot",
            'Join-Path $verifiedRoot "$relativeRoot/Recover-OpenCodeRuntime.ps1"',
            "BOOTSTRAP_CALLER_LOCATION=",
            "BOOTSTRAP_RESOLVED_ROOT=",
            "BOOTSTRAP_VERIFIED_ORIGIN=",
            "BOOTSTRAP_VERIFIED_HEAD=",
            "BOOTSTRAP_ACTIVE_LOCATION=",
        ):
            self.assertIn(token, text, token)

        self.assertLess(
            text.index("Set-Location -LiteralPath $verifiedRoot"),
            text.index('Join-Path $verifiedRoot "$relativeRoot/Recover-OpenCodeRuntime.ps1"'),
        )
        self.assertNotIn("-PreferredPath", text)
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

    def test_bootstrap_staging_is_exact_head_and_ephemeral(self) -> None:
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("[IO.Path]::GetTempPath()", text)
        self.assertIn("Invoke-WebRequest -Uri $uri -OutFile $destination", text)
        self.assertIn("Remove-Item -LiteralPath $stageRoot -Recurse -Force", text)
        self.assertIn("BOOTSTRAP_STAGE_DOWNLOAD_FAILED", text)
        self.assertIn("BOOTSTRAP_HEAD_MISMATCH", text)
        self.assertIn("BOOTSTRAP_WORKTREE_NOT_CLEAN", text)
        self.assertNotIn("git reset", text.lower())
        self.assertNotIn("git clean", text.lower())
        self.assertNotIn("git stash", text.lower())
        self.assertNotIn("push --force", text.lower())

    def test_manifest_registers_location_free_operator_entrypoint(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        recovery = manifest["repositoryRecovery"]
        self.assertEqual(
            "tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1",
            manifest["entrypoints"]["cwdIndependentBootstrap"],
        )
        self.assertTrue(recovery["operatorInvocationCwdIndependent"])
        self.assertFalse(recovery["knownLocalRepoPathRequired"])
        self.assertTrue(recovery["bootstrapStagesExactDefaultHeadRouters"])
        self.assertIn("current directory", recovery["proofRule"].lower())
        self.assertIn("remote identity", recovery["proofRule"].lower())

    def test_operator_guide_starts_with_location_free_bootstrap(self) -> None:
        text = DOCS.read_text(encoding="utf-8")
        lower = text.lower()
        self.assertIn("run from any powershell directory", lower)
        self.assertIn(
            "https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1",
            text,
        )
        self.assertIn("FromBase64String", text)
        self.assertIn("Set-Location -LiteralPath", text)
        self.assertIn("BOOTSTRAP_VERIFIED_ORIGIN", text)
        self.assertIn("BOOTSTRAP_VERIFIED_HEAD", text)


if __name__ == "__main__":
    unittest.main()
