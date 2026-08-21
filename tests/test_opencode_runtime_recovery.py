from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
H = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup"
ROUTER = H / "Recover-OpenCodeRuntime.ps1"
RUNNER = H / "Invoke-OpenCodeLspWorkstationSetup.ps1"
MANIFEST = H / "manifest.json"
WORKFLOW = H / "workflows" / "failure-recovery.workflow.json"
ARTIFACTS = H / "artifact-registry.json"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def executable_powershell(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


def literal_here_string(text: str, variable: str) -> str:
    marker = f"${variable} = @'\n"
    start = text.index(marker) + len(marker)
    end = text.index("\n'@", start)
    return text[start:end]


class TestOpenCodeRuntimeRecovery(unittest.TestCase):
    def test_runtime_recovery_is_opencode_only(self) -> None:
        text = read(ROUTER)
        executable = executable_powershell(text)

        self.assertIn("[ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180", text)
        self.assertIn("$Distribution = 'Ubuntu'", text)
        self.assertIn("https://opencode.ai/install", text)
        self.assertIn("AgentSwitchboard\\bin\\opencode.cmd", text)
        self.assertIn("requires LOCALAPPDATA", text)
        self.assertIn("'inspect-handoff'", text)
        self.assertIn("exit 0", text)

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
            "bash -s -- --no-modify-path",
            "-TimeoutSeconds ($InstallTimeoutSeconds + 30)",
            "OPENCODE_INSTALL_WINDOWS_TIMEOUT",
            "OPENCODE_INSTALL_WSL_TIMEOUT",
        ):
            self.assertIn(token, text, token)

        self.assertLess(
            text.index("$installScript = @'"),
            text.index("$installResult = Invoke-WslBash -Script $installScript"),
        )

    def test_repair_uses_bounded_user_local_install_paths(self) -> None:
        text = read(ROUTER)
        self.assertIn(
            'export PATH="$HOME/.opencode/bin:$XDG_BIN_DIR:$HOME/.local/bin:$HOME/bin:$PATH"',
            text,
        )
        self.assertIn(
            'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/bin:$PATH"',
            text,
        )
        self.assertIn('export OPENCODE_INSTALL_DIR="$HOME/.opencode/bin"', text)
        self.assertIn(
            '$initialVersionScript = "set -u`n$($script:initialOpenCodePath) --version"',
            text,
        )
        self.assertIn(
            '$postVersionScript = "set -u`n$($script:openCodePath) --version"',
            text,
        )
        self.assertNotIn("$versionScript", text)
        self.assertNotIn(".Replace('\\\"', '\"')", text)

        install_block = text[
            text.index("$installScript = @'") : text.index("$installResult = Invoke-WslBash -Script $installScript")
        ]
        self.assertIn('export OPENCODE_INSTALL_DIR="$HOME/.opencode/bin"', install_block)
        self.assertIn("bash -s -- --no-modify-path", install_block)

        post_discovery_block = text[
            text.index("$postInstallDiscoveryScript = @'") : text.index("$postDiscovery = Invoke-WslBash -Script $postInstallDiscoveryScript")
        ]
        for candidate in (
            '"$HOME/.opencode/bin/opencode"',
            '"${XDG_BIN_DIR:-}/opencode"',
            '"$HOME/bin/opencode"',
            '"$HOME/.local/bin/opencode"',
        ):
            self.assertIn(candidate, post_discovery_block)
        self.assertIn('for candidate in "${candidates[@]}"', post_discovery_block)
        self.assertNotIn("command -v opencode", post_discovery_block)
        self.assertIn(
            "Stop-Recovery 'OPENCODE_POST_INSTALL_NOT_FOUND' 'OpenCode installation returned success but no executable was found in the bounded WSL install locations.'",
            text,
        )

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_post_install_discovery_payload_resolves_linux_home(self) -> None:
        script = literal_here_string(read(ROUTER), "postInstallDiscoveryScript")

        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            target = home / ".opencode" / "bin" / "opencode"
            target.parent.mkdir(parents=True)
            target.write_text("#!/usr/bin/env bash\nprintf '1.18.19\\n'\n", encoding="utf-8")
            target.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            env.pop("XDG_BIN_DIR", None)
            completed = subprocess.run(
                ["bash", "-c", script],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(str(target), completed.stdout.strip())
            self.assertNotIn("C:\\Users\\", completed.stdout)

    def test_generated_windows_shim_uses_native_cmd_quotes(self) -> None:
        text = read(ROUTER)
        self.assertIn(
            "('\"{0}\" -d \"{1}\" --exec \"{2}\" %*' -f $wslPath, $Distribution, $script:openCodePath)",
            text,
        )
        self.assertNotIn(".Replace('\\\"', '\"')", text)

    def test_existing_but_unhealthy_runtime_advances_to_one_install(self) -> None:
        text = read(ROUTER)

        for token in (
            "$script:stage = 'opencode-command-discovery'",
            "$script:stage = 'opencode-version-probe'",
            "$script:installReason = 'existing-runtime-version-timeout'",
            "$script:installReason = 'existing-runtime-version-failed'",
            "$script:installReason = 'command-not-found'",
            "$script:stage = 'opencode-install'",
            "$script:installAttempted = $true",
            "$script:stage = 'post-install-command-discovery'",
            "$script:stage = 'post-install-version-probe'",
            "OPENCODE_POST_INSTALL_VERSION_FAILED",
        ):
            self.assertIn(token, text, token)

        install_block = text[
            text.index("$installScript = @'") : text.index("$installResult = Invoke-WslBash -Script $installScript")
        ]
        self.assertNotIn("command -v opencode", install_block)
        self.assertNotIn("if ! command -v opencode", install_block)

    def test_runtime_recovery_writes_stage_evidence_after_run_initialization(self) -> None:
        text = read(ROUTER)
        artifacts = json.loads(read(ARTIFACTS))
        ids = {item["artifactId"] for item in artifacts["artifacts"]}

        for token in (
            "opencode-runtime-recovery.json",
            "opencode-runtime-recovery.md",
            "function Write-RecoveryEvidence",
            "Write-RecoveryEvidence",
            "lastStdoutPresent",
            "lastStderrPresent",
            "secretOrEnvironmentDumpPersisted = $false",
            "OPENCODE_RUNTIME_RECOVERY_STAGE=",
            "OPENCODE_RUNTIME_RECOVERY_FAILURE_CODE=",
        ):
            self.assertIn(token, text, token)
        self.assertTrue({"runtime-recovery-json", "runtime-recovery-report"} <= ids)
        self.assertNotIn("lastStdout =", text)
        self.assertNotIn("lastStderr =", text)

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
            "OPENCODE_INSTALL_CURL_MISSING",
            "OPENCODE_INSTALL_TIMEOUT_TOOL_MISSING",
            "unrelated technician tools will not be installed as a side effect",
            "OPENCODE_PATH_UNSAFE",
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
        self.assertEqual("$HOME/.opencode/bin", recovery["wslPreferredInstallDirectory"])
        self.assertEqual(
            ["$HOME/.opencode/bin", "$XDG_BIN_DIR", "$HOME/bin", "$HOME/.local/bin"],
            recovery["wslAcceptedInstallLocations"],
        )
        self.assertTrue(recovery["localAppDataRequired"])
        self.assertFalse(recovery["shellProfileMutationAllowed"])
        self.assertFalse(recovery["unrelatedToolInstallationAllowed"])
        self.assertTrue(recovery["unhealthyExistingRuntimeRepairAllowed"])
        self.assertTrue(recovery["recoveryEvidenceBeforeInspectRequired"])
        self.assertFalse(recovery["sameStateRetryAllowed"])
        self.assertIn("exact command path", recovery["proofRule"])
        self.assertIn("receipt/report", recovery["proofRule"])
        self.assertIn("bounded user-local install locations", recovery["proofRule"])

    def test_failure_workflow_requires_unhealthy_repair_and_preinspect_evidence(self) -> None:
        workflow = json.loads(read(WORKFLOW))
        text = " ".join(workflow["steps"]).lower()

        self.assertIn("existing but unhealthy opencode command", text)
        self.assertIn("one bounded opencode-only install", text)
        self.assertIn("opencode-runtime-recovery.json", text)
        self.assertIn("failures before inspect", text)
        self.assertIn("do not delegate opencode_not_found or unhealthy runtime repair to broad technician setup", text)
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
