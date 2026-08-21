from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
ROUTER = H / "Recover-OpenCodeRuntime.ps1"
RUNNER = H / "Invoke-OpenCodeLspWorkstationSetup.ps1"
MANIFEST = H / "manifest.json"
WORKFLOW = H / "workflows" / "failure-recovery.workflow.json"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def executable_powershell(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


class TestOpenCodeRuntimeRecovery(unittest.TestCase):
    def test_runtime_recovery_is_opencode_only(self) -> None:
        text = read(ROUTER)
        executable = executable_powershell(text)

        self.assertIn("[ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180", text)
        self.assertIn("$Distribution = 'Ubuntu'", text)
        self.assertIn("https://opencode.ai/install", text)
        self.assertIn("AgentSwitchboard\\bin\\opencode.cmd", text)
        self.assertIn("-Mode Inspect", text)
        self.assertIn("exit $LASTEXITCODE", text)

        self.assertNotIn("Repair-Technician-Command-Shims.cmd", executable)
        self.assertNotIn("AGENT_SWITCHBOARD_NO_PAUSE", executable)
        self.assertNotIn("Setup-TechnicianAgentSwitchboard.ps1", executable)
        self.assertNotIn("antigravity.google", text.lower())
        self.assertNotIn(" agy ", executable.lower())

    def test_network_install_is_dual_bounded(self) -> None:
        text = read(ROUTER)

        for token in (
            "function Invoke-BoundedProcess",
            "$process.WaitForExit($ProcessTimeoutSeconds * 1000)",
            "$process.Kill($true)",
            "function ConvertTo-WslBashPayload",
            "function Invoke-WslBash",
            "timeout --signal=TERM --kill-after=10s __INSTALL_TIMEOUT__s",
            "curl --connect-timeout 15 --max-time __INSTALL_TIMEOUT__",
            "-TimeoutSeconds ($InstallTimeoutSeconds + 30)",
            "$runtimeProbe.ExitCode -eq 124 -or $runtimeProbe.ExitCode -eq 137",
        ):
            self.assertIn(token, text, token)

        self.assertLess(
            text.index("$installScript = @'"),
            text.index("$runtimeProbe = Invoke-WslBash -Script $installScript"),
        )

    def test_post_recovery_inspect_probes_are_bounded(self) -> None:
        text = read(RUNNER)

        for token in (
            "[ValidateRange(5, 120)][int]$ProbeTimeoutSeconds = 30",
            "function Invoke-BoundedProcess",
            "$process.WaitForExit($ProcessTimeoutSeconds * 1000)",
            "$process.Kill($true)",
            "$versionResult = Invoke-BoundedProcess -FilePath $openCode -ArgumentList @('--version')",
            "Stop-Setup 'OPENCODE_VERSION_TIMEOUT'",
            "$modelResult = Invoke-BoundedProcess -FilePath $openCode -ArgumentList @('models', $modelProvider)",
            "Stop-Setup 'MODEL_QUERY_TIMEOUT'",
            "-ProbeTimeoutSeconds $ProbeTimeoutSeconds",
        ):
            self.assertIn(token, text, token)

        self.assertNotIn("@(& $openCode --version 2>&1)", text)
        self.assertNotIn("@(& $openCode models $modelProvider 2>&1)", text)

    def test_runtime_recovery_fails_closed_on_missing_prerequisites(self) -> None:
        text = read(ROUTER)
        for token in (
            "exit 61",
            "exit 62",
            "requires curl inside WSL",
            "requires GNU timeout inside WSL",
            "unrelated technician tools will not be installed as a side effect",
            "WSL returned an unsafe OpenCode command path",
        ):
            self.assertIn(token, text, token)

    def test_manifest_declares_focused_recovery_contract(self) -> None:
        manifest = json.loads(read(MANIFEST))
        recovery = manifest["runtimeRecovery"]

        self.assertEqual(
            "tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1",
            recovery["repairEntrypoint"],
        )
        self.assertEqual(
            "tooling/harness/operational/opencode-lsp-setup",
            recovery["repairOwner"],
        )
        self.assertEqual("Ubuntu", recovery["distribution"])
        self.assertEqual(180, recovery["defaultInstallTimeoutSeconds"])
        self.assertFalse(recovery["unrelatedToolInstallationAllowed"])
        self.assertFalse(recovery["sameStateRetryAllowed"])
        self.assertIn("bounded OpenCode-only installation", recovery["proofRule"])

    def test_failure_workflow_forbids_broad_recovery_and_hangs(self) -> None:
        workflow = json.loads(read(WORKFLOW))
        text = " ".join(workflow["steps"]).lower()

        self.assertIn("do not delegate opencode_not_found to broad technician setup", text)
        self.assertIn("install unrelated agent tools such as agy", text)
        self.assertIn("bound network-backed opencode installation", text)
        self.assertIn("instead of hanging indefinitely", text)

    def test_router_contains_no_destructive_or_config_mutation(self) -> None:
        lower = read(ROUTER).lower()
        for forbidden in (
            "git reset",
            "git clean",
            "git stash",
            "push --force",
            "remove-item",
            "opencode_config_content",
            "set-content -literalpath $globalconfig",
        ):
            self.assertNotIn(forbidden, lower, forbidden)


if __name__ == "__main__":
    unittest.main()
