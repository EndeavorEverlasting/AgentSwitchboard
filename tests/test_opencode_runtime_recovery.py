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
INSTALLER_COMMIT = "3a31c4ea801915c0b050df4b3842997ea62b6e93"


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


def post_install_health_script(probe_timeout: str = "2", kill_after: str = "1") -> str:
    return (
        literal_here_string(read(ROUTER), "postInstallDiscoveryScript")
        .replace("__RUNTIME_PROBE_TIMEOUT__", probe_timeout)
        .replace("__RUNTIME_KILL_AFTER__", kill_after)
    )


class TestOpenCodeRuntimeRecovery(unittest.TestCase):
    def test_runtime_recovery_is_opencode_only(self) -> None:
        text = read(ROUTER)
        executable = executable_powershell(text)

        self.assertIn("[ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180", text)
        self.assertIn("$Distribution = 'Ubuntu'", text)
        self.assertIn(INSTALLER_COMMIT, text)
        self.assertIn("raw.githubusercontent.com/anomalyco/opencode", text)
        self.assertIn("AgentSwitchboard\\bin\\opencode.cmd", text)
        self.assertIn("requires LOCALAPPDATA", text)
        self.assertIn("'inspect-handoff'", text)
        self.assertIn("exit 0", text)

        self.assertNotIn("Repair-Technician-Command-Shims.cmd", executable)
        self.assertNotIn("AGENT_SWITCHBOARD_NO_PAUSE", executable)
        self.assertNotIn("Setup-TechnicianAgentSwitchboard.ps1", executable)
        self.assertNotIn("antigravity.google", text.lower())
        self.assertNotIn(" agy ", executable.lower())

    def test_network_install_is_dual_bounded_and_pinned(self) -> None:
        text = read(ROUTER)

        for token in (
            "function Invoke-BoundedProcess",
            "$process.WaitForExit($ProcessTimeoutSeconds * 1000)",
            "$process.Kill($true)",
            "function ConvertTo-WslBashPayload",
            "function Invoke-WslBash",
            f"$installerSourceCommit = '{INSTALLER_COMMIT}'",
            "https://raw.githubusercontent.com/anomalyco/opencode/__INSTALLER_COMMIT__/install",
            ".Replace('__INSTALLER_COMMIT__', $installerSourceCommit)",
            "timeout --signal=TERM --kill-after=10s __INSTALL_TIMEOUT__s curl",
            "curl --connect-timeout 15 --max-time __INSTALL_TIMEOUT__",
            "grep -Fq 'INSTALL_DIR=$HOME/.opencode/bin'",
            "grep -Fq -- '--no-modify-path'",
            'bash "$installer" --no-modify-path',
            "OPENCODE_INSTALLER_CONTRACT_DRIFT",
            "-TimeoutSeconds ($InstallTimeoutSeconds + 30)",
            "OPENCODE_INSTALL_WINDOWS_TIMEOUT",
            "OPENCODE_INSTALL_WSL_TIMEOUT",
        ):
            self.assertIn(token, text, token)

        self.assertNotIn("OPENCODE_INSTALL_DIR", text)
        self.assertLess(
            text.index("$installScript = @'"),
            text.index("$installResult = Invoke-WslBash -Script $installScript"),
        )

    def test_initial_discovery_remains_bounded_but_post_install_uses_official_path(self) -> None:
        text = read(ROUTER)
        self.assertIn(
            '$initialVersionScript = "set -u`n$($script:initialOpenCodePath) --version"',
            text,
        )
        self.assertIn(
            '$postVersionScript = "set -u`n$($script:openCodePath) --version"',
            text,
        )
        self.assertNotIn("$versionScript", text)

        discovery_block = text[
            text.index("$discoveryScript = @'") : text.index("$discovery = Invoke-WslBash -Script $discoveryScript")
        ]
        for candidate in (
            '"$HOME/.opencode/bin/opencode"',
            '"${XDG_BIN_DIR:-}/opencode"',
            '"$HOME/bin/opencode"',
            '"$HOME/.local/bin/opencode"',
        ):
            self.assertIn(candidate, discovery_block)
        self.assertNotIn("command -v opencode", discovery_block)
        self.assertNotIn(":$PATH", discovery_block)

        post_block = text[
            text.index("$postInstallDiscoveryScript = @'") : text.index("$postDiscovery = Invoke-WslBash -Script $postInstallDiscoveryScript")
        ]
        self.assertIn('managed="$HOME/.opencode/bin/opencode"', post_block)
        self.assertNotIn("candidates=(", post_block)
        self.assertIn(
            'timeout --signal=TERM --kill-after=__RUNTIME_KILL_AFTER__s __RUNTIME_PROBE_TIMEOUT__s "$managed" --version',
            post_block,
        )
        self.assertIn("illegal-instruction", post_block)
        self.assertIn("bus-error", post_block)
        self.assertIn("segmentation-fault", post_block)
        self.assertNotIn("core dumped'", post_block)
        self.assertIn("STATE=healthy", post_block)

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_initial_discovery_ignores_unregistered_inherited_path(self) -> None:
        script = literal_here_string(read(ROUTER), "discoveryScript")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            home = root / "home"
            home.mkdir()
            system_bin = root / "system-bin"
            system_bin.mkdir()
            unregistered = system_bin / "opencode"
            unregistered.write_text("#!/usr/bin/env bash\nprintf '1.18.21\\n'\n", encoding="utf-8")
            unregistered.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            env.pop("XDG_BIN_DIR", None)
            env["PATH"] = f"{system_bin}:{env.get('PATH', '')}"
            completed = subprocess.run(
                ["bash", "-c", script], env=env, capture_output=True, text=True, check=False
            )

            self.assertEqual(44, completed.returncode, completed.stderr)
            self.assertEqual("", completed.stdout.strip())

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_post_install_health_payload_accepts_official_path(self) -> None:
        script = post_install_health_script()

        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            target = home / ".opencode" / "bin" / "opencode"
            target.parent.mkdir(parents=True)
            target.write_text("#!/usr/bin/env bash\nprintf '1.18.21\\n'\n", encoding="utf-8")
            target.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                ["bash", "-c", script], env=env, capture_output=True, text=True, check=False
            )

            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertIn(f"PATH={target}", completed.stdout)
            self.assertIn("STATE=healthy", completed.stdout)
            self.assertIn("EXIT=0", completed.stdout)
            self.assertIn("CLASS=none", completed.stdout)
            self.assertIn("VERSION=1.18.21", completed.stdout)

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_post_install_health_payload_classifies_illegal_instruction_without_raw_stderr(self) -> None:
        script = post_install_health_script()

        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            target = home / ".opencode" / "bin" / "opencode"
            target.parent.mkdir(parents=True)
            target.write_text(
                "#!/usr/bin/env bash\necho 'Illegal instruction (core dumped)' >&2\nexit 132\n",
                encoding="utf-8",
            )
            target.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                ["bash", "-c", script], env=env, capture_output=True, text=True, check=False
            )

            self.assertEqual(47, completed.returncode)
            self.assertIn(f"PATH={target}", completed.stdout)
            self.assertIn("STATE=unhealthy", completed.stdout)
            self.assertIn("EXIT=132", completed.stdout)
            self.assertIn("CLASS=illegal-instruction", completed.stdout)
            self.assertNotIn("Illegal instruction", completed.stdout)
            self.assertEqual("", completed.stderr.strip())

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_post_install_health_payload_keeps_segmentation_core_dump_native(self) -> None:
        script = post_install_health_script()

        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            target = home / ".opencode" / "bin" / "opencode"
            target.parent.mkdir(parents=True)
            target.write_text(
                "#!/usr/bin/env bash\necho 'Segmentation fault (core dumped)' >&2\nexit 139\n",
                encoding="utf-8",
            )
            target.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                ["bash", "-c", script], env=env, capture_output=True, text=True, check=False
            )

            self.assertEqual(47, completed.returncode)
            self.assertIn(f"PATH={target}", completed.stdout)
            self.assertIn("STATE=unhealthy", completed.stdout)
            self.assertIn("EXIT=139", completed.stdout)
            self.assertIn("CLASS=segmentation-fault", completed.stdout)
            self.assertNotIn("Segmentation fault", completed.stdout)
            self.assertEqual("", completed.stderr.strip())

    @unittest.skipIf(os.name == "nt", "Bash payload semantics are exercised on Ubuntu CI")
    def test_post_install_health_payload_forces_kill_after_sigterm_ignore(self) -> None:
        script = post_install_health_script(probe_timeout="1", kill_after="1")

        with tempfile.TemporaryDirectory() as temp_dir:
            home = Path(temp_dir)
            target = home / ".opencode" / "bin" / "opencode"
            target.parent.mkdir(parents=True)
            target.write_text(
                "#!/usr/bin/env bash\ntrap '' TERM\nwhile :; do sleep 0.1; done\n",
                encoding="utf-8",
            )
            target.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            completed = subprocess.run(
                ["bash", "-c", script],
                env=env,
                capture_output=True,
                text=True,
                check=False,
                timeout=6,
            )

            self.assertEqual(47, completed.returncode)
            self.assertIn("STATE=unhealthy", completed.stdout)
            self.assertRegex(completed.stdout, r"EXIT=(124|137)")
            self.assertIn("CLASS=timeout", completed.stdout)
            self.assertEqual("", completed.stderr.strip())

    def test_final_reproof_owns_typed_health_evidence(self) -> None:
        text = read(ROUTER)
        for token in (
            "$script:postInstallHealthState = 'unhealthy'",
            "$script:postInstallFailureClass = 'reproof-timeout'",
            "$script:postInstallFailureClass = 'reproof-version-failed'",
            "$script:postInstallHealthState = 'healthy'",
            "$script:postInstallVersionExitCode = 0",
            "$script:postInstallFailureClass = 'none'",
        ):
            self.assertIn(token, text, token)
        self.assertLess(
            text.index("$script:postInstallFailureClass = 'reproof-timeout'"),
            text.index("$script:stage = 'shim-write'"),
        )

    def test_generated_windows_shim_uses_native_cmd_quotes(self) -> None:
        text = read(ROUTER)
        self.assertIn(
            "('\"{0}\" -d \"{1}\" --exec \"{2}\" %*' -f $wslPath, $Distribution, $script:openCodePath)",
            text,
        )

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
            "OPENCODE_POST_INSTALL_CPU_INCOMPATIBLE",
            "OPENCODE_POST_INSTALL_NATIVE_CRASH",
            "OPENCODE_POST_INSTALL_VERSION_FAILED",
        ):
            self.assertIn(token, text, token)

        install_block = text[
            text.index("$installScript = @'") : text.index("$installResult = Invoke-WslBash -Script $installScript")
        ]
        self.assertNotIn("command -v opencode", install_block)

    def test_runtime_recovery_writes_typed_post_install_evidence(self) -> None:
        text = read(ROUTER)
        artifacts = json.loads(read(ARTIFACTS))
        ids = {item["artifactId"] for item in artifacts["artifacts"]}

        for token in (
            "opencode-runtime-recovery.json",
            "opencode-runtime-recovery.md",
            "function Write-RecoveryEvidence",
            "Write-RecoveryEvidence",
            "installerSourceCommit",
            "officialInstallPath",
            "postInstallHealthState",
            "postInstallVersionExitCode",
            "postInstallFailureClass",
            "lastStdoutPresent",
            "lastStderrPresent",
            "secretOrEnvironmentDumpPersisted = $false",
            "OPENCODE_RUNTIME_RECOVERY_STAGE=",
            "OPENCODE_RUNTIME_RECOVERY_FAILURE_CODE=",
            "No environment dump, provider credential, raw OpenCode stderr",
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

    def test_runtime_recovery_fails_closed_on_missing_prerequisites(self) -> None:
        text = read(ROUTER)
        for token in (
            "exit 61",
            "exit 62",
            "exit 63",
            "OPENCODE_INSTALL_CURL_MISSING",
            "OPENCODE_INSTALL_TIMEOUT_TOOL_MISSING",
            "OPENCODE_INSTALL_GREP_MISSING",
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
        self.assertEqual("Ubuntu", recovery["distribution"])
        self.assertEqual(180, recovery["defaultInstallTimeoutSeconds"])
        self.assertEqual("$HOME/.opencode/bin/opencode", recovery["officialInstallerExecutablePath"])
        self.assertEqual("anomalyco/opencode", recovery["installerSourceRepository"])
        self.assertEqual(INSTALLER_COMMIT, recovery["installerSourceCommit"])
        self.assertEqual(
            f"https://raw.githubusercontent.com/anomalyco/opencode/{INSTALLER_COMMIT}/install",
            recovery["installerSourceUrl"],
        )
        self.assertTrue(recovery["installerSourceImmutable"])
        self.assertEqual(30, recovery["postInstallVersionProbeTimeoutSeconds"])
        self.assertEqual(10, recovery["postInstallKillAfterSeconds"])
        self.assertTrue(recovery["installerContractVerificationRequired"])
        self.assertTrue(recovery["localAppDataRequired"])
        self.assertFalse(recovery["inheritedPathDiscoveryAllowed"])
        self.assertFalse(recovery["shellProfileMutationAllowed"])
        self.assertFalse(recovery["unrelatedToolInstallationAllowed"])
        self.assertTrue(recovery["unhealthyExistingRuntimeRepairAllowed"])
        self.assertTrue(recovery["recoveryEvidenceBeforeInspectRequired"])
        self.assertFalse(recovery["sameStateRetryAllowed"])
        self.assertIn("immutable", recovery["proofRule"].lower())
        self.assertIn("forced-kill", recovery["proofRule"].lower())
        self.assertIn("final shim-creation health gate", recovery["proofRule"].lower())
        self.assertIn("raw stderr", recovery["proofRule"].lower())

    def test_failure_workflow_requires_unhealthy_repair_and_preinspect_evidence(self) -> None:
        workflow = json.loads(read(WORKFLOW))
        text = " ".join(workflow["steps"]).lower()
        self.assertIn("existing but unhealthy opencode command", text)
        self.assertIn("one bounded opencode-only install", text)
        self.assertIn("opencode-runtime-recovery.json", text)
        self.assertIn("failures before inspect", text)

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
