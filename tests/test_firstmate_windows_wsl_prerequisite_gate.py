from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHYSICAL = ROOT / "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1"
BRIDGE = ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1"
HARNESS = ROOT / "tooling" / "firstmate" / "harness" / "operational"
INTEGRATION = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"
RUNBOOK = ROOT / "docs" / "harness" / "firstmate-wsl-physical-floor-runbook.md"
WORK_QUEUE = ROOT / ".ai" / "WORK_QUEUE.md"
OCD_VALIDATOR = ROOT / "scripts" / "Test-OperatorCommandDeliveryHarnessCompleteness.ps1"


class FirstMateWindowsWslPrerequisiteGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.physical = PHYSICAL.read_text(encoding="utf-8")
        cls.bridge = BRIDGE.read_text(encoding="utf-8")
        cls.runbook = RUNBOOK.read_text(encoding="utf-8")
        cls.artifacts = json.loads((HARNESS / "artifact-registry.json").read_text(encoding="utf-8"))
        cls.integration = json.loads(INTEGRATION.read_text(encoding="utf-8"))

    def test_prerequisite_gate_is_registered_and_uses_explicit_distribution(self) -> None:
        ids = {item["id"] for item in self.artifacts["artifacts"]}
        self.assertIn("windows-wsl-prerequisite-proof", ids)
        self.assertIn("windows-wsl-prerequisite-stderr", ids)
        self.assertEqual("Ubuntu", self.integration["platform_contract"]["wsl_distribution"])
        self.assertIn("--distribution", self.physical)
        self.assertIn("$WslDistribution", self.physical)

    def test_gate_checks_required_tools_and_github_auth(self) -> None:
        for tool in ("git", "gh", "tmux", "python3"):
            self.assertIn(tool, self.physical)
        self.assertIn("gh auth status --hostname github.com", self.physical)
        self.assertIn("STATUS=BLOCKED_MISSING_TOOLS", self.physical)
        self.assertIn("STATUS=BLOCKED_GITHUB_AUTH", self.physical)
        self.assertIn("STATUS=PASS", self.physical)

    def test_gate_reports_recovery_without_silently_executing_it(self) -> None:
        self.assertIn("NEXT_ACTION=sudo apt-get update && sudo apt-get install -y", self.physical)
        self.assertIn("NEXT_ACTION=gh auth login --hostname github.com --git-protocol https --web", self.physical)
        for executable_form in (
            "Start-Process sudo",
            "Start-Process gh",
            "Invoke-Expression $nextAction",
            "Invoke-Command $nextAction",
            "-FileName sudo",
            "-FileName gh",
        ):
            self.assertNotIn(executable_form, self.physical)
        self.assertIn("Write-Host \"NEXT_ACTION=$($nextAction.Groups[1].Value.Trim())\"", self.physical)
        self.assertIs(self.integration["windows_bridge"]["dependency_installation"], False)
        self.assertIs(self.integration["windows_bridge"]["credential_mutation"], False)

    def test_fm_wsl_12_execution_owner_has_bounded_package_repair_authority(self) -> None:
        recovery = self.integration["physical_floor_recovery"]
        self.assertEqual("FM-WSL-12", recovery["lane"])
        self.assertIs(recovery["execution_owner_may_install_missing_packages"], True)
        self.assertIs(recovery["additional_operator_confirmation_required"], False)
        self.assertEqual("Ubuntu", recovery["distribution"])
        self.assertEqual("apt-get", recovery["package_manager"])
        self.assertEqual(["git", "gh", "tmux", "python3"], recovery["package_allowlist"])
        self.assertIs(recovery["credential_mutation"], False)
        self.assertIs(recovery["github_authentication_requires_operator"], True)
        self.assertIn("NEXT_ACTION", recovery["authority_source"])
        self.assertIn("rerun", recovery["continuation_rule"].lower())
        self.assertEqual(
            "Invoke-FirstMatePhysicalFloorContinuation.ps1",
            recovery["continuation_entrypoint"],
        )
        self.assertEqual(
            "Invoke-FmWsl12AdminBoxLiveProof.ps1",
            recovery["admin_box_live_proof_entrypoint"],
        )
        self.assertEqual("physical-floor-continue", recovery["harness_mode"])
        self.assertIs(recovery["harness_remains_non_installing"], True)
        self.assertEqual(44, recovery["structured_prerequisite_exit_codes"]["missing_tools"])
        self.assertEqual(45, recovery["structured_prerequisite_exit_codes"]["github_auth"])
        self.assertEqual(46, recovery["structured_prerequisite_exit_codes"]["windows_wsl_required"])
        self.assertEqual(
            "BLOCKED_WINDOWS_WSL_REQUIRED",
            recovery["non_windows_live_attempt"]["status"],
        )
        self.assertEqual(
            "WINDOWS_WSL_REQUIRED",
            recovery["non_windows_live_attempt"]["failure_code"],
        )
        self.assertEqual(
            "LIVE_ATTEMPT_FAIL_CLOSED",
            recovery["non_windows_live_attempt"]["proof_level"],
        )
        self.assertIn("P08", recovery["p08_continuation_authority"])

        lower = self.runbook.lower()
        self.assertIn("without stopping for additional operator permission", lower)
        self.assertIn("bounded repair is authorized by fm-wsl-12", lower)
        self.assertIn("physical-floor-continue", self.runbook)
        self.assertIn("Invoke-FirstMatePhysicalFloorContinuation.ps1", self.runbook)
        self.assertIn("Invoke-FmWsl12AdminBoxLiveProof.ps1", self.runbook)
        self.assertIn("sudo apt-get update && sudo apt-get install -y gh", self.runbook)
        self.assertIn("gh auth login", self.runbook)
        self.assertIn("do not automate credential entry", lower)
        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", self.runbook)
        self.assertIn("WINDOWS_WSL_REQUIRED", self.runbook)
        self.assertIn("BLOCKED_SUDO", self.runbook)
        self.assertIn("exit 47", self.runbook)
        self.assertIn("BLOCKED_PRIMARY_HARNESS", self.runbook)
        self.assertIn("exit 48", self.runbook)
        self.assertIn("BLOCKED_FIRSTMATE_DIRTY", self.runbook)
        self.assertIn("exit 49", self.runbook)
        self.assertIn("BLOCKED_FIRSTMATE_PIN", self.runbook)
        self.assertIn("exit 50", self.runbook)

    def test_continuation_entrypoint_encodes_allowlist_and_auth_stop(self) -> None:
        continuation = (
            ROOT / "Invoke-FirstMatePhysicalFloorContinuation.ps1"
        ).read_text(encoding="utf-8")
        harness = (ROOT / "Test-AgentSwitchboard-FirstMate-Harness.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("Test-AllowlistedAptNextAction", continuation)
        self.assertIn("sudo apt-get update && sudo apt-get install -y ", continuation)
        self.assertIn("BLOCKED_MISSING_TOOLS", continuation)
        self.assertIn("BOUNDED_PACKAGE_REPAIR_EXHAUSTED", continuation)
        self.assertIn("BOUNDED_APT_REPAIR_FAILED", continuation)
        self.assertIn("STATUS=BLOCKED_MISSING_TOOLS", continuation)
        self.assertIn("BLOCKED_GITHUB_AUTH", continuation)
        self.assertIn("exit 45", continuation)
        self.assertIn("exit 46", continuation)
        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", continuation)
        self.assertIn("WINDOWS_WSL_REQUIRED", continuation)
        self.assertIn("MaxPackageRepairAttempts", continuation)
        self.assertIn("execution_owner_may_install_missing_packages", continuation)
        self.assertIn("Get-OperatorNextFromText", continuation)
        self.assertIn("sudo -n apt-get --version", continuation)
        self.assertIn("STATUS=BLOCKED_SUDO", continuation)
        self.assertIn("STATUS=BLOCKED_PREREQUISITE_TIMEOUT", continuation)
        self.assertIn("FAILURE_CODE=SUDO_PROBE_TIMEOUT", continuation)
        self.assertIn("FAILURE_CODE=BOUNDED_APT_REPAIR_TIMEOUT", continuation)
        self.assertLess(
            continuation.index("FAILURE_CODE=SUDO_PROBE_TIMEOUT"),
            continuation.index("FAILURE_CODE=PASSWORDLESS_SUDO_APT_REQUIRED"),
        )
        self.assertLess(
            continuation.index("FAILURE_CODE=BOUNDED_APT_REPAIR_TIMEOUT"),
            continuation.index("FAILURE_CODE=BOUNDED_APT_REPAIR_FAILED"),
        )
        self.assertIn("sudo-probe-stdout.txt", continuation)
        self.assertIn("SUDO_PROBE_TIMED_OUT=", continuation)
        self.assertIn("exit 47", continuation)
        self.assertIn("bridge-stderr.txt", continuation)
        self.assertNotIn("gh auth login --hostname github.com --web", continuation.split("ContractOnly")[0])
        for forbidden in (
            "Start-Process sudo",
            "Invoke-Expression $nextAction",
            "choco install",
            "winget install",
            "set-content ~/.config/gh",
        ):
            self.assertNotIn(forbidden.lower(), continuation.lower())
        self.assertIn("physical-floor-continue", harness)
        self.assertIn("Invoke-FirstMatePhysicalFloorContinuation.ps1", harness)
        self.assertIn("Invoke-FmWsl12AdminBoxLiveProof.ps1", harness)
        # Front door must preserve structured exits for Admin Box callers.
        self.assertIn("if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }", harness)
        # Continuation must surface Admin Box-visible blockers as STATUS/NEXT (no throw).
        self.assertIn("STATUS=BLOCKED_WSL_DISTRIBUTION", continuation)
        self.assertNotIn(
            'throw "WSL distribution mismatch. Contract=$canonicalDistribution Requested=$WslDistribution"',
            continuation,
        )
        self.assertIn("STATUS=BLOCKED_HARNESS_START", continuation)
        self.assertNotIn('throw "Unable to start $FileName."', continuation)
        self.assertIn("STATUS=BLOCKED_GIT_HEAD", continuation)
        self.assertNotIn(
            "throw 'Unable to resolve exact AgentSwitchboard HEAD.'",
            continuation,
        )
        self.assertIn("STATUS=BLOCKED_HEAD_MISMATCH", continuation)
        self.assertNotIn(
            'throw "Exact-head mismatch. Expected=$ExpectedHead Actual=$actualHead"',
            continuation,
        )
        self.assertIn("FAILURE_CODE=MISSING_TOOLS_WITHOUT_NEXT_ACTION", continuation)
        self.assertNotIn(
            "throw 'BLOCKED_MISSING_TOOLS without NEXT_ACTION; cannot perform bounded repair.'",
            continuation,
        )
        self.assertIn("FAILURE_CODE=NON_ALLOWLISTED_NEXT_ACTION", continuation)
        self.assertNotIn(
            'throw "Refusing non-allowlisted NEXT_ACTION under FM-WSL-12: $nextAction"',
            continuation,
        )
        # Truncated-child recovery: map structured exits to STATUS when STATUS= is missing.
        self.assertIn("ExitCode -eq 46", continuation)
        self.assertIn("ExitCode -eq 47", continuation)
        self.assertIn("ExitCode -eq 48", continuation)
        self.assertIn("ExitCode -eq 49", continuation)
        self.assertIn("ExitCode -eq 50", continuation)
        self.assertIn("ExitCode -eq 51", continuation)
        self.assertIn("ExitCode -eq 52", continuation)
        self.assertIn("ExitCode -eq 124", continuation)
        self.assertIn("'BLOCKED_WINDOWS_WSL_REQUIRED'", continuation)
        self.assertIn("'BLOCKED_PREREQUISITE_TIMEOUT'", continuation)
        # Fallthrough after the repair loop must stay structured (no bare exit 1).
        self.assertIn("STATUS=BLOCKED_CONTINUATION_EXHAUSTED", continuation)
        self.assertIn("FAILURE_CODE=CONTINUATION_LOOP_ENDED_WITHOUT_PASS", continuation)
        self.assertLess(
            continuation.index("STATUS=BLOCKED_CONTINUATION_EXHAUSTED"),
            continuation.rindex("exit 1"),
        )

    def test_physical_floor_preserves_structured_prerequisite_exit_codes(self) -> None:
        self.assertIn("exit $preflight.ExitCode", self.physical)
        self.assertIn("FIRSTMATE_WSL_PREREQUISITE_BLOCKED", self.physical)
        self.assertIn("exit 44", self.physical)
        self.assertIn("exit 45", self.physical)
        self.assertIn("exit 46", self.physical)
        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", self.physical)
        self.assertIn("WINDOWS_WSL_REQUIRED", self.physical)
        self.assertIn("STATUS=BLOCKED_PRIMARY_HARNESS", self.physical)
        self.assertIn("exit 48", self.physical)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_DIRTY", self.physical)
        self.assertIn("exit 49", self.physical)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", self.physical)
        self.assertIn("upstream-pin.json", self.physical)
        self.assertIn("__ASB_EXPECTED_FIRSTMATE_HEAD__", self.physical)
        self.assertIn("$expectedFirstMateHead", self.physical)
        self.assertIn("$upstreamPin.commit", self.physical)
        self.assertNotIn("EXPECTED_FIRSTMATE_HEAD='b182d0f908b78d08c7ccb8dce3775bdca8c5d657'", self.physical)
        self.assertIn("exit 50", self.physical)
        self.assertIn("PRIMARY_HARNESS=", self.physical)
        codes = self.integration["physical_floor_recovery"]["structured_prerequisite_exit_codes"]
        self.assertEqual(44, codes["missing_tools"])
        self.assertEqual(45, codes["github_auth"])
        self.assertEqual(46, codes["windows_wsl_required"])
        self.assertEqual(47, codes["blocked_sudo"])
        self.assertEqual(48, codes["blocked_primary_harness"])
        self.assertEqual(49, codes["blocked_firstmate_dirty"])
        self.assertEqual(50, codes["blocked_firstmate_pin"])
        # Missing/unrunnable Ubuntu must fail closed as exit 46 before apt/preflight.
        self.assertIn("--distribution", self.physical)
        self.assertIn("--exec", self.physical)
        self.assertIn("firstmate-wsl-distribution-probe.txt", self.physical)
        self.assertIn("Required WSL distribution is not registered or not runnable", self.physical)
        self.assertLess(
            self.physical.index("firstmate-wsl-distribution-probe.txt"),
            self.physical.index("firstmate-wsl-prerequisites.txt"),
        )
        # Primary harness / dirty FirstMate preflight must run before STATUS=PASS.
        self.assertLess(
            self.physical.index("STATUS=BLOCKED_PRIMARY_HARNESS"),
            self.physical.index("STATUS=PASS"),
        )
        # -FirstMatePath must drive dirty/pin preflight and skip $HOME/firstmate.
        self.assertIn("ASB_FIRSTMATE_PATH", self.physical)
        self.assertIn("FIRSTMATE_CHECK_PATH", self.physical)
        self.assertIn("PathEnvironmentNames", self.physical)
        self.assertIn("WSLENV", self.physical)
        self.assertLess(
            self.physical.index('FIRSTMATE_CHECK_PATH="${ASB_FIRSTMATE_PATH:-}"'),
            self.physical.index('elif [[ -e "$HOME/firstmate" ]]; then'),
        )
        self.assertIn("pass -FirstMatePath to a clean audited", self.physical)

    def test_gate_is_bounded_and_uses_unique_evidence(self) -> None:
        self.assertIn("[int]$PrerequisiteTimeoutSeconds = 60", self.physical)
        self.assertIn("WaitForExit($TimeoutSeconds * 1000)", self.physical)
        self.assertIn("ExitCode = if ($timedOut) { 124 }", self.physical)
        self.assertIn("STATUS=BLOCKED_PREREQUISITE_TIMEOUT", self.physical)
        self.assertIn("exit 124", self.physical)
        self.assertNotIn('throw "FirstMate WSL prerequisite probe timed out', self.physical)
        self.assertIn("STATUS=BLOCKED_HEAD_MISMATCH", self.physical)
        self.assertIn("STATUS=BLOCKED_WSL_DISTRIBUTION", self.physical)
        self.assertNotIn('throw "WSL distribution mismatch', self.physical)
        self.assertIn("STATUS=BLOCKED_GIT_HEAD", self.physical)
        self.assertNotIn("throw 'Unable to resolve exact AgentSwitchboard HEAD.'", self.physical)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", self.physical)
        self.assertNotIn('throw "upstream-pin.json commit must be a 40-character lowercase hex SHA', self.physical)
        self.assertIn("STATUS=BLOCKED_HARNESS_START", self.physical)
        self.assertNotIn('throw "Unable to start $FileName."', self.physical)
        self.assertIn("process Start threw", self.physical)
        self.assertIn("STATUS=BLOCKED_PREREQUISITE_TIMEOUT", self.physical)
        self.assertIn("distroProbe.TimedOut", self.physical)
        self.assertIn("NEXT=ff-only refresh main", self.physical)
        self.assertIn("$nextMatch = [regex]::Match($preflight.Stdout", self.physical)
        self.assertIn("(?m)^NEXT=", self.physical)
        self.assertIn("Get-Date -Format 'yyyyMMdd-HHmmss'", self.physical)
        self.assertIn("[guid]::NewGuid()", self.physical)
        self.assertIn("firstmate-wsl-prerequisites.txt", self.physical)
        self.assertIn("firstmate-wsl-prerequisites-stderr.log", self.physical)

    def test_gate_propagates_lower_bridge_failure(self) -> None:
        self.assertIn("Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1", self.physical)
        self.assertIn("bridge-stdout.txt", self.physical)
        self.assertIn("bridge-stderr.txt", self.physical)
        self.assertIn("FIRSTMATE_LOWER_BRIDGE_FAILED", self.physical)
        bridge = (ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1").read_text(encoding="utf-8")
        self.assertIn("FIRSTMATE_INTEROP_PROBE_FAILED", bridge)
        self.assertIn("exit $(if ($probe.ExitCode -ne 0) { $probe.ExitCode } else { 1 })", bridge)
        self.assertIn("STATUS=BLOCKED_WSL_BOOTSTRAP", bridge)
        self.assertIn("exit 51", bridge)
        self.assertIn("STATUS=BLOCKED_HARNESS_CONTRACT", bridge)
        self.assertIn("exit 52", bridge)
        self.assertNotIn('throw "WSL could not create the standalone exact-head', bridge)
        self.assertIn("STATUS=BLOCKED_HEAD_MISMATCH", bridge)
        self.assertNotIn('throw "Exact-head mismatch', bridge)
        self.assertNotIn("throw 'WSL is unavailable", bridge)
        self.assertIn("STATUS=BLOCKED_WSL_DISTRIBUTION", bridge)
        self.assertNotIn('throw "WSL distribution mismatch', bridge)
        self.assertIn("STATUS=BLOCKED_GIT_HEAD", bridge)
        self.assertNotIn('throw "Source repository is not a Git working tree', bridge)
        self.assertNotIn("throw 'Unable to start wsl.exe.'", bridge)
        self.assertNotIn(
            "Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Resolve exact AgentSwitchboard HEAD'",
            bridge,
        )
        self.assertNotIn(
            "Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Verify exact AgentSwitchboard commit in source repository'",
            bridge,
        )
        self.assertIn("exit $(if ($bridge.ExitCode -ne 0) { $bridge.ExitCode } else { 1 })", self.physical)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR", self.physical)
        self.assertIn("Write-Host $bridge.Stderr.TrimEnd()", self.physical)
        self.assertIn('Write-Host "NEXT=$operatorNext"', self.physical)

    def test_contract_only_does_not_require_live_wsl(self) -> None:
        contract_index = self.physical.index("if ($ContractOnly)")
        wsl_index = self.physical.index("Get-Command wsl.exe")
        self.assertLess(contract_index, wsl_index)
        self.assertIn("FIRSTMATE_WINDOWS_WSL_PREREQUISITE_GATE_CONTRACT", self.physical)

    def test_harness_still_avoids_unbounded_dependency_or_credential_mutation(self) -> None:
        lowered = self.physical.lower()
        for forbidden in (
            "invoke-webrequest",
            "choco install",
            "winget install",
            "wsl --install",
            "npm install",
            "pip install",
            "set-content ~/.config/gh",
        ):
            self.assertNotIn(forbidden, lowered)

    def test_asq017_admin_box_next_action_is_ocd_safe_and_durable_entrypoint_bound(self) -> None:
        """ASQ-017 paste must keep the parent shell open and call the durable floor entrypoint."""
        text = WORK_QUEUE.read_text(encoding="utf-8")
        start = text.find("## ASQ-017")
        self.assertGreaterEqual(start, 0, "ASQ-017 missing from work ledger")
        rest = text[start:]
        end = rest.find("\n## ", 1)
        block = rest if end < 0 else rest[:end]
        self.assertIn("`Invoke-Asq017AdminBoxLiveFloor.ps1`", block)
        next_line = next(
            (line for line in block.splitlines() if line.startswith("- **Next action:**")),
            None,
        )
        self.assertIsNotNone(next_line, "ASQ-017 Next action missing")
        assert next_line is not None
        idx = next_line.find("$ErrorActionPreference")
        self.assertGreaterEqual(idx, 0, "ASQ-017 Next action missing PowerShell body")
        command = next_line[idx:].strip().strip("`")
        self.assertIn("Invoke-Asq017AdminBoxLiveFloor.ps1", command)
        self.assertIn("CHILD_EXIT_CODE=", command)
        self.assertIn("$childExit=$LASTEXITCODE", command)
        self.assertIn("throw", command)
        self.assertIn("$childExit -eq 44", command)
        self.assertIn("$childExit -eq 45", command)
        self.assertIn("$childExit -eq 47", command)
        self.assertIn("$childExit -eq 48", command)
        self.assertIn("$childExit -eq 49", command)
        self.assertIn("$childExit -eq 50", command)
        self.assertIn("$childExit -eq 51", command)
        self.assertIn("$childExit -eq 52", command)
        self.assertIn("$childExit -eq 124", command)
        self.assertIn("$childExit -eq 1", command)
        self.assertIn("BLOCKED_WSL_BOOTSTRAP", command)
        self.assertIn("BLOCKED_HARNESS_CONTRACT", command)
        self.assertIn("BLOCKED_PREREQUISITE_TIMEOUT", command)
        self.assertIn("BLOCKED_CONTINUATION_EXHAUSTED", command)
        self.assertIn("BLOCKED_FIRSTMATE_PIN", command)
        self.assertIn("BLOCKED_PRIMARY_HARNESS", command)
        self.assertIn("Test-Path -LiteralPath", command)
        self.assertIn("checkout root", command)
        self.assertNotIn("(git rev-parse HEAD).Trim()", command)
        self.assertIn("LIVE_RUNTIME_PROOF:UNPROVEN", block)
        self.assertIn("BLOCKED_WINDOWS_WSL_REQUIRED", block)
        self.assertIn("Invoke-Asq017AdminBoxLiveFloor.ps1", self.runbook)
        self.assertIn("CHILD_EXIT_CODE", self.runbook)
        self.assertIn("$childExit -eq 44", self.runbook)
        self.assertIn("$childExit -eq 51", self.runbook)
        self.assertIn("$childExit -eq 52", self.runbook)
        self.assertIn("$childExit -eq 124", self.runbook)
        self.assertIn("$childExit -eq 1", self.runbook)
        self.assertIn("BLOCKED_WSL_BOOTSTRAP", self.runbook)
        self.assertIn("BLOCKED_PREREQUISITE_TIMEOUT", self.runbook)
        self.assertIn("BLOCKED_CONTINUATION_EXHAUSTED", self.runbook)
        self.assertIn("BLOCKED_MISSING_TOOLS", self.runbook)
        self.assertIn("throw", self.runbook)
        self.assertIn("Test-Path -LiteralPath", self.runbook)
        self.assertIn("upstream-pin.json", self.runbook)
        self.assertNotIn("git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657", self.runbook)
        self.assertIn("inside Ubuntu", self.runbook)

        durable = ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1"
        self.assertTrue(durable.is_file(), durable)
        durable_text = durable.read_text(encoding="utf-8")
        self.assertIn("Invoke-FmWsl12AdminBoxLiveProof.ps1", durable_text)
        self.assertIn("$headRaw = git rev-parse HEAD", durable_text)
        self.assertIn("STATUS=BLOCKED_GIT_REFRESH", durable_text)
        self.assertIn("Write-Asq017GitRefreshBlocker", durable_text)
        self.assertIn('Write-Host ("git {0} failed with exit {1}" -f $Operation, $GitExitCode)', durable_text)
        self.assertIn("-Operation 'fetch'", durable_text)
        self.assertIn("-Operation 'switch'", durable_text)
        self.assertIn("-Operation 'pull'", durable_text)
        self.assertNotIn('throw "git fetch failed with exit', durable_text)
        self.assertNotIn('throw "git switch failed with exit', durable_text)
        self.assertNotIn('throw "git pull failed with exit', durable_text)
        self.assertIn("STATUS=BLOCKED_GIT_HEAD", durable_text)
        self.assertIn("Unable to resolve HEAD", durable_text)
        self.assertNotIn("throw 'Unable to resolve HEAD'", durable_text)
        # Capture → native exit check → Trim (never Trim before LASTEXITCODE).
        head_raw_idx = durable_text.find("$headRaw = git rev-parse HEAD")
        self.assertGreaterEqual(head_raw_idx, 0)
        after_head = durable_text[head_raw_idx:]
        exit_idx = after_head.find("if ($LASTEXITCODE -ne 0)")
        trim_idx = after_head.find('("$headRaw").Trim()')
        self.assertGreaterEqual(exit_idx, 0, "HEAD capture missing LASTEXITCODE check")
        self.assertGreaterEqual(trim_idx, 0, "HEAD capture missing Trim after exit check")
        self.assertLess(exit_idx, trim_idx, "Trim must follow LASTEXITCODE validation")
        self.assertNotIn("(git rev-parse HEAD).Trim()", durable_text)
        self.assertNotIn("$head=(git rev-parse HEAD).Trim()", durable_text)
        self.assertIn("[switch]$ContractOnly", durable_text)
        self.assertIn("STATUS=CONTRACT_FAIL", durable_text)
        self.assertIn("ASQ017_RESULT", durable_text)
        # ContractOnly failure must stay structured (no throw → unstructured exit 1).
        contract_block = durable_text.split("if ($ContractOnly)", 1)[1].split(
            "Set-Location -LiteralPath $Root", 1
        )[0]
        self.assertIn("STATUS=CONTRACT_FAIL", contract_block)
        self.assertIn("CHILD_EXIT_CODE", contract_block)
        self.assertNotIn('throw "', contract_block)
        self.assertNotIn("throw '", contract_block)
        self.assertNotIn('throw "ASQ-017 ContractOnly', durable_text)

        self.assertIn("[string]$FirstMatePath", durable_text)
        self.assertIn("-FirstMatePath", durable_text)
        self.assertIn("LIVE_RUNTIME_PROOF", durable_text)
        self.assertIn("UNPROVEN", durable_text)
        self.assertEqual(
            "Invoke-Asq017AdminBoxLiveFloor.ps1",
            self.integration["physical_floor_recovery"]["asq017_admin_box_live_floor_entrypoint"],
        )

        interop = (ROOT / "tooling" / "firstmate" / "Test-FirstMateInterop.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("BOOTSTRAPPED_FIRSTMATE=", interop)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", interop)
        self.assertIn("STATUS=BLOCKED_PRIMARY_HARNESS", interop)
        self.assertIn("exit 48", interop)
        self.assertIn("STATUS=BLOCKED_GITHUB_AUTH", interop)
        self.assertIn("exit 45", interop)
        self.assertIn("exit 50", interop)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_DIRTY", interop)
        self.assertIn("exit 49", interop)
        self.assertIn("$HOME/firstmate", interop)
        self.assertIn("is_viable_discovered_firstmate", interop)
        self.assertIn("Skipping non-viable auto-discovery candidate", interop)
        # $HOME/firstmate preference must run before alternate viable-discovery loop.
        self.assertLess(
            interop.index('is_firstmate_clone "$HOME/firstmate"'),
            interop.index('if is_viable_discovered_firstmate "$candidate"; then'),
        )
        self.assertIn("NEXT=install one primary harness", interop)
        self.assertIn("NEXT=run gh auth login inside Ubuntu", interop)

        self.assertTrue(OCD_VALIDATOR.is_file(), OCD_VALIDATOR)
        with tempfile.TemporaryDirectory() as tmp:
            candidate = Path(tmp) / "asq017-admin-box-next.ps1"
            candidate.write_text(command.replace("; ", "\n") + "\n", encoding="utf-8")
            completed = subprocess.run(
                [
                    "pwsh",
                    "-NoLogo",
                    "-NoProfile",
                    "-File",
                    str(OCD_VALIDATOR),
                    "-CandidatePath",
                    str(candidate),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                0,
                completed.returncode,
                f"OCD validator failed:\n{completed.stdout}\n{completed.stderr}",
            )
            env = os.environ.copy()
            env["CANDIDATE"] = str(candidate)
            ast_probe = subprocess.run(
                [
                    "pwsh",
                    "-NoLogo",
                    "-NoProfile",
                    "-Command",
                    (
                        "$t = Get-Content -Raw -LiteralPath $env:CANDIDATE; "
                        "$tok = $null; $err = $null; "
                        "$ast = [System.Management.Automation.Language.Parser]::ParseInput("
                        "$t, [ref]$tok, [ref]$err); "
                        "$ex = @($ast.FindAll({ param($n) "
                        "$n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)); "
                        "if ($err.Count -gt 0) { Write-Output ('PARSE_ERRORS=' + $err.Count); exit 2 }; "
                        "Write-Output ('EXIT_STATEMENT_COUNT=' + $ex.Count); "
                        "if ($ex.Count -gt 0) { exit 1 }"
                    ),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(
                0,
                ast_probe.returncode,
                f"ExitStatementAst probe failed:\n{ast_probe.stdout}\n{ast_probe.stderr}",
            )
            self.assertIn("EXIT_STATEMENT_COUNT=0", ast_probe.stdout)



    def test_admin_box_floor_surfaces_operator_next_on_fail_closed(self) -> None:
        asq = (ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1").read_text(encoding="utf-8")
        self.assertIn("Key 'NEXT'", asq)
        self.assertIn("cloud/Linux hosts cannot prove physical floor", asq)
        self.assertIn("inspect child console for NEXT=", asq)
        self.assertIn("STATUS=BLOCKED_HARNESS_START", asq)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", asq)
        self.assertNotIn(
            'throw "upstream-pin.json commit must be a 40-character lowercase hex SHA',
            asq,
        )
        oneshot = (ROOT / "Invoke-FmWsl12AdminBoxLiveProof.ps1").read_text(encoding="utf-8")
        self.assertIn("NEXT=run on Windows Admin Box with wsl.exe and Ubuntu", oneshot)
        self.assertIn("STATUS=BLOCKED_HEAD_MISMATCH", oneshot)
        self.assertIn("NEXT=ff-only refresh main, re-resolve HEAD, and rerun with the recorded SHA", oneshot)
        self.assertNotIn('throw "Exact-head mismatch', oneshot)
        self.assertIn("STATUS=BLOCKED_WSL_DISTRIBUTION", oneshot)
        self.assertNotIn('throw "WSL distribution mismatch', oneshot)
        self.assertIn("STATUS=BLOCKED_GIT_HEAD", oneshot)
        self.assertNotIn("throw 'Unable to resolve exact AgentSwitchboard HEAD.'", oneshot)
        self.assertNotIn('throw "ExpectedHead must be a 40-character SHA', oneshot)
        self.assertIn("STATUS=BLOCKED_HARNESS_START", oneshot)
        self.assertIn("BLOCKED_HARNESS_CONTRACT", oneshot)
        self.assertIn("STATUS=$contractStatus", oneshot)
        self.assertIn("STATUS=$result", oneshot)
        self.assertIn("BLOCKED_PROTECTED_CONTROL", oneshot)
        self.assertIn("PROTECTED_CONTROL_FAILED", oneshot)
        self.assertIn("STATUS=$protectedStatus", oneshot)
        self.assertIn("RESULT=$protectedResult", oneshot)
        self.assertNotIn('throw "Unable to start harness mode=', oneshot)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", oneshot)
        self.assertNotIn(
            'throw "upstream-pin.json commit must be a 40-character lowercase hex SHA',
            oneshot,
        )
        self.assertIn("harness process Start threw", oneshot)
        self.assertIn("STATUS=BLOCKED_HARNESS_TIMEOUT", oneshot)
        self.assertIn("exit 124", oneshot)
        self.assertNotIn('throw "Harness mode=$Mode timed out', oneshot)
        # Child exit 124 from contract/continue/protected must surface as timeout, not contract/generic fail.
        self.assertIn("ExitCode -eq 124", oneshot)
        self.assertIn("BLOCKED_PREREQUISITE_TIMEOUT", oneshot)
        self.assertIn(
            "repair hung WSL/sudo/apt prerequisite or increase host capacity",
            oneshot,
        )
        self.assertLess(
            oneshot.index("elseif ($continue.ExitCode -eq 124)"),
            oneshot.index("'PHYSICAL_FLOOR_CONTINUE_FAILED'"),
        )
        # Unknown continue exits must prefer child STATUS=BLOCKED_* (e.g. CONTINUATION_EXHAUSTED).
        self.assertIn("Get-StatusFromEvidence", oneshot)
        self.assertIn("Get-AttemptEvidenceBlob", oneshot)
        self.assertIn("^BLOCKED_", oneshot)
        self.assertIn("BLOCKED_CONTINUATION_EXHAUSTED", oneshot)
        self.assertLess(
            oneshot.index("Get-StatusFromEvidence -Attempt $continue"),
            oneshot.index("'PHYSICAL_FLOOR_CONTINUE_FAILED'"),
        )
        self.assertIn("$contract.ExitCode -eq 124", oneshot)
        self.assertIn(
            "contract step timed out",
            oneshot,
        )
        self.assertIn("$protected.ExitCode -eq 124", oneshot)
        self.assertIn(
            "protected physical-floor step timed out after continuation PASS",
            oneshot,
        )
        bridge = (ROOT / "Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1").read_text(encoding="utf-8")
        self.assertIn("STDERR<<", bridge)
        self.assertIn("Write-Host $probe.Stderr.TrimEnd()", bridge)
        self.assertIn("STATUS=BLOCKED_PREREQUISITE_TIMEOUT", bridge)
        self.assertIn("wsl.exe Start threw", bridge)
        self.assertIn("FAILURE_CODE=WINDOWS_WSL_REQUIRED", bridge)
        continuation = (ROOT / "Invoke-FirstMatePhysicalFloorContinuation.ps1").read_text(encoding="utf-8")
        self.assertIn("Get-OperatorNextFromText", continuation)
        self.assertIn("sudo -n apt-get --version", continuation)
        self.assertIn("STATUS=BLOCKED_SUDO", continuation)
        self.assertIn("sudo-probe-stdout.txt", continuation)
        self.assertIn("exit 47", continuation)
        self.assertIn("process Start threw", continuation)
        self.assertIn("BLOCKED_SUDO", asq)
        self.assertIn("-ExitCode 47", asq)
        self.assertIn("BLOCKED_PRIMARY_HARNESS", asq)
        self.assertIn("-ExitCode 48", asq)
        self.assertIn("BLOCKED_FIRSTMATE_DIRTY", asq)
        self.assertIn("-ExitCode 49", asq)
        self.assertIn("BLOCKED_FIRSTMATE_PIN", asq)
        self.assertIn("-ExitCode 50", asq)
        self.assertIn("BLOCKED_WSL_BOOTSTRAP", asq)
        self.assertIn("-ExitCode 51", asq)
        self.assertIn("BLOCKED_HARNESS_CONTRACT", asq)
        self.assertIn("-ExitCode 52", asq)
        self.assertIn("BLOCKED_MISSING_TOOLS", asq)
        self.assertIn("$childExit -eq 44", asq)
        self.assertIn("-ExitCode 44", asq)
        self.assertIn("BLOCKED_SUDO", oneshot)
        self.assertIn("BLOCKED_PRIMARY_HARNESS", oneshot)
        self.assertIn("Get-OperatorNextFromEvidence", oneshot)
        # Child NEXT= must win over hardcoded $HOME/firstmate fallbacks for 49/50.
        self.assertIn("$preservedNext = Get-OperatorNextFromEvidence -Attempt $continue", oneshot)
        self.assertLess(
            oneshot.index("$preservedNext = Get-OperatorNextFromEvidence -Attempt $continue"),
            oneshot.index("or the -FirstMatePath override"),
        )
        self.assertIn("-FirstMatePath override", oneshot)
        self.assertIn("ExitCode -eq 48", oneshot)
        self.assertIn("ExitCode -eq 49", oneshot)
        self.assertIn("ExitCode -eq 50", oneshot)
        self.assertIn("BLOCKED_FIRSTMATE_PIN", oneshot)

        work_queue = (ROOT / ".ai" / "WORK_QUEUE.md").read_text(encoding="utf-8")
        asq_section = work_queue.split("## ASQ-017", 1)[1].split("\n## ", 1)[0]
        next_action = asq_section.split("- **Next action:**", 1)[1].split("- **Updated:**", 1)[0]
        self.assertIn("upstream-pin.json", next_action)
        self.assertIn("$childExit -eq 50", next_action)
        self.assertNotIn("git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657", next_action)
        # Exit-50 NEXT fallbacks must load pin from upstream-pin.json (same source as PhysicalFloor).
        self.assertIn("upstream-pin.json", asq)
        self.assertIn("$upstreamPin.commit", asq)
        self.assertIn("$expectedFirstMateHead", asq)
        self.assertIn("Get-Asq017ExpectedFirstMateHead", asq)
        self.assertIn("Get-Asq017OperatorNextFromText", asq)
        self.assertIn("$preservedNext = Get-Asq017OperatorNextFromText -Text $oneshotBlob", asq)
        self.assertIn("Get-Asq017StatusFromText", asq)
        self.assertIn("$preservedStatus = Get-Asq017StatusFromText -Text $oneshotBlob", asq)
        self.assertIn("^BLOCKED_", asq)
        # Generic nonzero path must prefer preserved BLOCKED_* STATUS before FAILED.
        self.assertLess(
            asq.index("$preservedStatus = Get-Asq017StatusFromText -Text $oneshotBlob"),
            asq.index("Write-Asq017Blocker -Result 'FAILED'"),
        )
        self.assertIn("Write-Asq017Blocker", asq)
        self.assertIn("$childExit -eq 124", asq)
        self.assertIn("BLOCKED_PREREQUISITE_TIMEOUT", asq)
        self.assertIn('Write-Host ("STATUS={0}" -f $Result)', asq)
        blocker_fn = asq.split("function Write-Asq017Blocker", 1)[1].split("\nfunction ", 1)[0]
        self.assertIn('Write-Host ("STATUS={0}" -f $Result)', blocker_fn)
        self.assertIn("Write-Asq017Status -Key 'ASQ017_RESULT' -Value $Result", blocker_fn)
        self.assertLess(
            blocker_fn.index('Write-Host ("STATUS={0}" -f $Result)'),
            blocker_fn.index("Write-Asq017Status -Key 'ASQ017_RESULT' -Value $Result"),
        )
        self.assertIn("Prefer child NEXT=", asq)
        self.assertLess(
            asq.index("$preservedNext = Get-Asq017OperatorNextFromText -Text $oneshotBlob"),
            asq.index("Write-Asq017Blocker"),
        )
        self.assertIn("Reload pin after ff-only refresh", asq)
        self.assertLess(
            asq.index("git pull --ff-only"),
            asq.index("$expectedFirstMateHead = Get-Asq017ExpectedFirstMateHead"),
        )
        self.assertLess(
            asq.index("$expectedFirstMateHead = Get-Asq017ExpectedFirstMateHead"),
            asq.index("$childExit -eq 50"),
        )
        self.assertNotIn("git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657", asq)
        self.assertIn("upstream-pin.json", oneshot)
        self.assertIn("$upstreamPin.commit", oneshot)
        self.assertIn("$expectedFirstMateHead", oneshot)
        self.assertNotIn("git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657", oneshot)
        physical = (ROOT / "Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1").read_text(encoding="utf-8")
        self.assertIn("Write-Host $bridge.Stderr.TrimEnd()", physical)
        self.assertIn('Write-Host "NEXT=$operatorNext"', physical)
        self.assertIn("STATUS=BLOCKED_PRIMARY_HARNESS", physical)
        self.assertIn("exit 48", physical)

    def test_asq017_helpers_prefer_last_next_and_read_pin_json(self) -> None:
        """Behavioral proof for Asq017 helpers (not source-order only)."""
        asq_path = ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1"
        pin_path = ROOT / "tooling" / "firstmate" / "harness" / "upstream-pin.json"
        self.assertTrue(asq_path.is_file())
        self.assertTrue(pin_path.is_file())
        expected_pin = json.loads(pin_path.read_text(encoding="utf-8"))["commit"]
        completed = subprocess.run(
            [
                "pwsh",
                "-NoLogo",
                "-NoProfile",
                "-Command",
                (
                    "$ErrorActionPreference = 'Stop'; "
                    f"$asqPath = '{asq_path.as_posix()}'; "
                    f"$UpstreamPinPath = '{pin_path.as_posix()}'; "
                    "$raw = Get-Content -LiteralPath $asqPath -Raw; "
                    "$nextFn = [regex]::Match($raw, '(?s)function Get-Asq017OperatorNextFromText \\{.*?\\n\\}'); "
                    "$pinFn = [regex]::Match($raw, '(?s)function Get-Asq017ExpectedFirstMateHead \\{.*?\\n\\}'); "
                    "if (-not $nextFn.Success -or -not $pinFn.Success) { "
                    "Write-Output 'EXTRACT_FAIL'; exit 2 }; "
                    "Invoke-Expression $nextFn.Value; "
                    "Invoke-Expression $pinFn.Value; "
                    "$blob = \"STATUS=BLOCKED_FIRSTMATE_PIN`nNEXT=first-guidance`n"
                    "OTHER=1`nNEXT=child-path-specific-guidance`n\"; "
                    "$got = Get-Asq017OperatorNextFromText -Text $blob; "
                    "$pin = Get-Asq017ExpectedFirstMateHead; "
                    "Write-Output ('NEXT=' + $got); "
                    "Write-Output ('PIN=' + $pin); "
                    "if ($got -ne 'child-path-specific-guidance') { exit 3 }; "
                    "if ($pin -notmatch '^[0-9a-f]{40}$') { exit 4 }"
                ),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            0,
            completed.returncode,
            f"Asq017 helper behavioral probe failed:\n{completed.stdout}\n{completed.stderr}",
        )
        self.assertIn("NEXT=child-path-specific-guidance", completed.stdout)
        self.assertIn(f"PIN={expected_pin}", completed.stdout)


if __name__ == "__main__":
    unittest.main()
