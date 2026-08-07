from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CMD = ROOT / "Open-AgentSwitchboard-Tmux.cmd"
PS1 = ROOT / "Open-AgentSwitchboard-Tmux.ps1"
PWSH_PROBE = ROOT / "scripts" / "Test-OperatorChildExecutableLaunch.ps1"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class TestTmuxLiveProofContract(unittest.TestCase):
    def test_owned_entrypoints_exist(self) -> None:
        self.assertTrue(CMD.is_file())
        self.assertTrue(PS1.is_file())
        self.assertTrue(PWSH_PROBE.is_file())

    def test_cmd_requires_concrete_powershell_launch_proof_without_closing_parent_shell(self) -> None:
        text = read(CMD)
        for token in (
            "Test-OperatorChildExecutableLaunch.ps1",
            "%ProgramFiles%\\PowerShell\\7\\pwsh.exe",
            "where pwsh.exe",
            "Microsoft.PowerShell",
            "Open-AgentSwitchboard-Tmux.ps1",
            "call :try_pwsh",
            "-ArgumentList --version",
            'set "RESULT=%ERRORLEVEL%"',
            "endlocal & exit /b %RESULT%",
        ):
            self.assertIn(token, text)
        self.assertNotRegex(
            text,
            r"for /f[^\n]*where pwsh\.exe[^\n]*set \"PWSH=%%I\"",
            "where/Get-Command discovery must not be promoted directly into the selected PowerShell executable",
        )
        probe_call = text.index('call :try_pwsh "%ProgramFiles%\\PowerShell\\7\\pwsh.exe"')
        runtime_call = text.index('"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*')
        self.assertLess(probe_call, runtime_call)
        self.assertIn("Refusing to treat path discovery as PowerShell launch proof.", text)
        self.assertIn("none passed concrete process-start proof", text)
        self.assertNotIn("taskkill", text.lower())
        self.assertNotIn("exit ", text.lower().replace("exit /b", ""))

    def test_child_launch_probe_uses_process_creation_not_discovery_only(self) -> None:
        text = read(PWSH_PROBE)
        for token in (
            "ProcessStartInfo",
            "UseShellExecute = $false",
            ".Start()",
            "child-executable-launch-result.json",
            "child-executable-launch-blocked",
        ):
            self.assertIn(token, text, token)

    def test_runtime_is_idempotent_and_only_installs_missing_owned_prerequisites(self) -> None:
        text = read(PS1)
        for token in (
            "Resolve-WezTermCli",
            "$wezTermState = 'reused'",
            "$wezTermState = 'installed'",
            "$tmuxState = 'reused'",
            "$tmuxState = 'installed'",
            "command -v tmux",
            "apt-get install -y tmux",
            "$sessionState = 'reused'",
            "$sessionState = 'created'",
            "tmux has-session",
            "tmux new-session -d",
        ):
            self.assertIn(token, text, token)
        self.assertIn("'-u', 'root'", text)
        self.assertNotIn("wsl --unregister", text.lower())
        self.assertNotIn("apt-get remove", text.lower())

    def test_success_requires_real_tmux_client_attachment(self) -> None:
        text = read(PS1)
        for token in (
            "tmux list-clients",
            "tmuxClientAttachedObserved = $true",
            "$proof.launch.status = 'tmux-client-attached'",
            "$proof.proofLevel = 'tmux-client-attached'",
            "[PASS] TMUX IS LIVE.",
            "tmux-live-proof.json",
        ):
            self.assertIn(token, text, token)
        self.assertRegex(text, r"if \(\$clientEvidence\.Count -lt 1\)\s*\{")
        self.assertIn("throw \"WezTerm launched, but tmux did not report an attached client", text)

    def test_surface_mode_is_non_mutating_for_ci(self) -> None:
        text = read(PS1)
        surface = text.index("if ($SurfaceOnly)")
        wez_install = text.index("winget.Source install")
        tmux_install = text.index("apt-get install -y tmux")
        self.assertLess(surface, wez_install)
        self.assertLess(surface, tmux_install)
        self.assertIn("status = 'surface-passed'", text)
        self.assertIn("proofLevel = 'surface-only'", text)

    def test_no_destructive_or_repo_mutation_commands(self) -> None:
        deployable = "\n".join((read(CMD), read(PS1), read(PWSH_PROBE))).lower()
        for forbidden in (
            "git reset",
            "git clean",
            "git stash",
            "push --force",
            "remove-item -recurse",
            "wsl --unregister",
            "tmux kill-server",
        ):
            self.assertNotIn(forbidden, deployable)


if __name__ == "__main__":
    unittest.main()
