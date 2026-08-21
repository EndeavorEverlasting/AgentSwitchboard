from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
READY_CMD = ROOT / "Technician-AgentSwitchboard-Ready.cmd"
READY_ENGINE = ROOT / "tooling" / "profiles" / "windows" / "Invoke-TechnicianAgentSwitchboardReady.ps1"
COMPAT_SETUP = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
PROFILE_LAUNCHER = ROOT / "tooling" / "profiles" / "windows" / "Invoke-AgentSwitchboardOpenOrActivate.ps1"
P02 = ROOT / "tooling" / "profiles" / "windows" / "technician-live-cert" / "stages" / "P02-Pull-And-Setup.ps1"
P03 = ROOT / "tooling" / "profiles" / "windows" / "technician-live-cert" / "stages" / "P03-Verify-Commands.ps1"
SHORTCUTS = ROOT / "tooling" / "profiles" / "windows" / "technician-live-cert" / "Install-TechnicianLiveCertShortcuts.ps1"
EXACT_CMD = ROOT / "Validate-Technician-ExactHead.cmd"
EXACT_PS1 = ROOT / "scripts" / "Invoke-TechnicianExactHeadValidation.ps1"
PS_VALIDATOR = ROOT / "scripts" / "Test-TechnicianAgentSwitchboardReady.ps1"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parameter_block(text: str) -> str:
    marker = "Set-StrictMode"
    if marker not in text:
        raise AssertionError("PowerShell file is missing Set-StrictMode")
    return text.split(marker, 1)[0]


class TestTechnicianAgentSwitchboardReady(unittest.TestCase):
    def test_owned_files_exist(self) -> None:
        for path in (READY_CMD, READY_ENGINE, COMPAT_SETUP, PROFILE_LAUNCHER, P02, P03, SHORTCUTS, EXACT_CMD, EXACT_PS1, PS_VALIDATOR):
            self.assertTrue(path.is_file(), f"missing owned file: {path}")

    def test_active_powershell_has_no_ambiguous_nul_replace(self) -> None:
        forbidden = ".Replace([char]0, '')"
        for path in (READY_ENGINE, COMPAT_SETUP, PROFILE_LAUNCHER, P02, P03, EXACT_PS1):
            self.assertNotIn(forbidden, read(path), str(path))
        self.assertIn(".Replace(([char]0).ToString(), [string]::Empty)", read(READY_ENGINE))
        self.assertIn(".Replace(([char]0).ToString(), [string]::Empty)", read(PROFILE_LAUNCHER))

    def test_parameter_defaults_do_not_evaluate_psscriptroot(self) -> None:
        for path in (READY_ENGINE, COMPAT_SETUP, PROFILE_LAUNCHER, EXACT_PS1, PS_VALIDATOR):
            self.assertNotIn("$PSScriptRoot", parameter_block(read(path)), str(path))

    def test_ready_engine_builds_real_product_surface(self) -> None:
        text = read(READY_ENGINE)
        for token in ("Setup-AgentSwitchboard.ps1", "Get-AgentSwitchboardStartupReport.ps1", "AgentSwitchboard\\GnhfFleet", "state.json", "Write-CommandShim -Name 'AgentSwitchboard'", "AgentSwitchboard.lnk", "-ListAgents", "fresh-shell-agentswitchboard", "stateObserved", "not-configured", "verification-required", "proofCeiling", "TECHNICIAN_AGENTSWITCHBOARD_CI_SURFACE"):
            self.assertIn(token, text, token)
        self.assertIn("-SkipHermesInstall", text)
        self.assertIn("if ($Mode -ne 'hermes')", text)
        self.assertNotIn("git reset", text.lower())
        self.assertNotIn("git clean", text.lower())
        self.assertNotIn("git stash", text.lower())

    def test_multiline_wsl_bash_payloads_are_lf_normalized(self) -> None:
        text = read(READY_ENGINE)
        self.assertIn("function ConvertTo-WslBashPayload", text)
        self.assertIn('return $Script.Replace("`r`n", "`n").Replace("`r", "`n")', text)
        self.assertIn("$linuxSetup = ConvertTo-WslBashPayload -Script $linuxSetup", text)
        self.assertIn("$toolWindowScript = ConvertTo-WslBashPayload -Script $toolWindowScript", text)
        self.assertLess(
            text.index("$linuxSetup = ConvertTo-WslBashPayload -Script $linuxSetup"),
            text.index("& $wslPath -d $Distribution -- bash -lc $linuxSetup"),
        )
        self.assertLess(
            text.index("$toolWindowScript = ConvertTo-WslBashPayload -Script $toolWindowScript"),
            text.index("& $wslPath -d $Distribution -- bash -lc $toolWindowScript"),
        )
        self.assertEqual(2, text.count("set -euo pipefail"))

    def test_compatibility_entrypoint_delegates_to_ready_engine(self) -> None:
        text = read(COMPAT_SETUP)
        self.assertIn("Invoke-TechnicianAgentSwitchboardReady.ps1", text)
        self.assertIn("-TimeoutSeconds $HermesTimeoutSeconds", text)
        self.assertNotIn("curl -fsSL", text)

    def test_profile_launcher_is_runtime_safe(self) -> None:
        text = read(PROFILE_LAUNCHER)
        self.assertIn("if ([string]::IsNullOrWhiteSpace($ManifestPath))", text)
        self.assertIn("windows-profile-launch-plan.v2", text)
        self.assertIn("windows-profile-launch-result.v2", text)
        self.assertIn("Local\\AgentSwitchboard.TmuxNewInstance", text)
        self.assertIn("tmux kill-session", text)
        self.assertIn("ProcessStartInfo", text)

    def test_live_cert_setup_proves_fleet_and_command(self) -> None:
        p02 = read(P02)
        for token in ("Technician-AgentSwitchboard-Ready.cmd", "GnhfFleet\\state.json", "AgentSwitchboard\\bin\\AgentSwitchboard.cmd", "startupReadiness", "technician-ready-summary.json"):
            self.assertIn(token, p02)
        p03 = read(P03)
        self.assertIn("@('AgentSwitchboard', 'wezterm', 'tmux', 'agy', 'opencode')", p03)
        self.assertIn("AgentSwitchboard -ListAgents", p03)
        self.assertIn("not-configured|blocked", p03)
        self.assertIn("$commandNames.Count", p03)

    def test_operator_shortcuts_include_product_and_repair(self) -> None:
        text = read(SHORTCUTS)
        self.assertIn("AgentSwitchboard.lnk", text)
        self.assertIn("AgentSwitchboard Technician Ready.lnk", text)
        self.assertIn("Run Technician Live Cert.lnk", text)

    def test_exact_head_validation_is_file_owned_truthful_and_complete(self) -> None:
        text = read(EXACT_PS1)
        for token in (
            "FETCH_HEAD",
            "worktree add --detach",
            "verifiedHead = $fetchedHead",
            "verifiedHead = $actualHead",
            "LastWriteTimeUtc -ge $p00StartedUtc",
            "tests.test_technician_agentswitchboard_ready",
            "Test-TechnicianAgentSwitchboardReady.ps1",
            "exact-head-validation.json",
            "Verified HEAD:      $actualHead",
            "[switch]$RunReadiness",
            "Exact-head AgentSwitchboard readiness",
            "Technician-AgentSwitchboard-Ready.cmd",
            "LastWriteTimeUtc -ge $readinessStartedUtc",
            "readiness.startupReadiness.stateObserved",
            "readiness.commands.AgentSwitchboard.shim",
            "readinessArtifact",
            "exact-head-cross-shell-p00-and-agentswitchboard-readiness",
        ):
            self.assertIn(token, text, token)
        for forbidden in (r"\bgit(?:\.exe)?\s+(?:-C\s+\S+\s+)?reset\b", r"\bgit(?:\.exe)?\s+(?:-C\s+\S+\s+)?clean\b", r"\bgit(?:\.exe)?\s+(?:-C\s+\S+\s+)?stash\b", r"push\s+--force"):
            self.assertIsNone(re.search(forbidden, text, re.IGNORECASE), forbidden)

        cmd = read(EXACT_CMD)
        self.assertIn("Invoke-TechnicianExactHeadValidation.ps1", cmd)
        self.assertIn('set "FIELD_MODE=%~4"', cmd)
        self.assertIn('if /I not "%FIELD_MODE%"=="validate" if /I not "%FIELD_MODE%"=="ready"', cmd)
        self.assertIn("-RunReadiness", cmd)
        self.assertIn("Ready mode requires an explicit expected commit SHA", cmd)

    def test_no_prompt_or_transcript_markers_are_operator_commands(self) -> None:
        for path in (READY_CMD, EXACT_CMD, READY_ENGINE, EXACT_PS1):
            text = read(path)
            self.assertNotRegex(text, r"(?m)^\s*PS C:\\")
            self.assertNotRegex(text, r"(?m)^\s*>>")
            self.assertNotRegex(text, r"(?m)^\s*\+\s+CategoryInfo")


if __name__ == "__main__":
    unittest.main()
