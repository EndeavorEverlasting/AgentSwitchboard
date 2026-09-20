#!/usr/bin/env python3
"""Tests for the FirstMate prompt-dispatch scout."""

from __future__ import annotations

import json
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCOUT = ROOT / "tooling/firstmate/harness/dispatch/scout_prompt_dispatch.py"
DECISION_FIXTURE = ROOT / ".ai/harness/fixtures/fm-asb-promptkit/routing-decision.valid.json"
DISPATCH_FIXTURE = ROOT / ".ai/harness/fixtures/fm-asb-promptkit/prompt-dispatch.valid.json"


class PromptDispatchScoutTests(unittest.TestCase):
    """Test suite for scout_prompt_dispatch.py."""

    maxDiff = None

    def setUp(self):
        """Set up test fixtures."""
        self.decision = json.loads(DECISION_FIXTURE.read_text(encoding="utf-8"))
        self.dispatch = json.loads(DISPATCH_FIXTURE.read_text(encoding="utf-8"))
        self._temp_dirs = []

    def tearDown(self):
        """Clean up temporary directories."""
        for temp_dir in self._temp_dirs:
            if temp_dir.exists():
                shutil.rmtree(temp_dir, ignore_errors=True)

    def run_scout(self, args: list[str], decision: dict | None = None) -> subprocess.CompletedProcess:
        """Run scout with given arguments."""
        # Create a persistent temp directory that won't be cleaned up automatically
        tmp_path = Path(tempfile.mkdtemp())
        self._temp_dirs.append(tmp_path)

        # Write decision fixture
        decision_path = tmp_path / "decision.json"
        decision_path.write_text(
            json.dumps(decision if decision is not None else self.decision),
            encoding="utf-8",
        )

        # Use temp evidence root
        evidence_root = tmp_path / "evidence"

        command = [
            sys.executable,
            str(SCOUT),
            "--decision",
            str(decision_path),
            "--firstmate-task-id",
            "scout-task-01",
            "--instruction-summary",
            "Scout test summary",
            "--proof-gate",
            "Scout test proof gate",
            "--evidence-root",
            str(evidence_root),
        ]
        command.extend(args)

        result = subprocess.run(command, text=True, capture_output=True, check=False)

        # Attach evidence root and temp path for inspection
        result.evidence_root = evidence_root
        result.tmp_path = tmp_path

        return result

    def test_scout_exists_and_is_read_only(self):
        """Scout module exists and contains no live FirstMate invocation."""
        self.assertTrue(SCOUT.is_file())
        source = SCOUT.read_text(encoding="utf-8")

        # Scout should import build_prompt_dispatch
        self.assertIn("from build_prompt_dispatch import", source)

        # Scout should not contain subprocess invocations of FirstMate commands
        # (Check for actual invocation patterns, not documentation mentions)
        for forbidden in ("subprocess.run", "subprocess.Popen", "os.system"):
            if forbidden in source:
                # Make sure it's not calling FirstMate commands
                for fm_cmd in ("fm-send", "fm-control", "capture-pane"):
                    self.assertNotIn(f'"{fm_cmd}"', source, f"Scout must not invoke {fm_cmd}")
                    self.assertNotIn(f"'{fm_cmd}'", source, f"Scout must not invoke {fm_cmd}")

    def test_dry_run_mode_succeeds_and_writes_artifact(self):
        """Dry-run mode builds dispatch and writes artifact to evidence root."""
        result = self.run_scout(["--mode", "dry-run"])

        self.assertEqual(result.returncode, 0, result.stderr)

        # Parse result
        scout_result = json.loads(result.stdout)
        self.assertEqual(scout_result["status"], "DRY_RUN_PASS")
        self.assertEqual(scout_result["mode"], "dry-run")
        self.assertEqual(scout_result["proofCeiling"], "SCOUT_CONTRACT_STATIC")
        self.assertIn("artifactPath", scout_result)
        self.assertIn("dispatchEventId", scout_result)
        self.assertIn("deliveryId", scout_result)

        # Check artifact exists
        artifact_path = Path(scout_result["artifactPath"])
        self.assertTrue(artifact_path.exists(), f"Artifact not found: {artifact_path}")

        # Validate artifact structure
        dispatch = json.loads(artifact_path.read_text(encoding="utf-8"))
        self.assertEqual(dispatch["schema"], "asb.prompt-dispatch/v1")
        self.assertEqual(dispatch["target"]["firstMateTaskId"], "scout-task-01")
        self.assertEqual(dispatch["target"]["deliveryPlane"], "durable-inbox")
        self.assertEqual(dispatch["prompt"]["deliveryMode"], "reference")
        self.assertIsNone(dispatch["prompt"]["inlineText"])

        # Check receipt exists
        receipt_path = artifact_path.parent / "scout-receipt.json"
        self.assertTrue(receipt_path.exists())
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertEqual(receipt["mode"], "dry-run")
        self.assertEqual(receipt["proofCeiling"], "SCOUT_CONTRACT_STATIC")
        self.assertIn("No live FirstMate delivery was attempted", str(receipt["notes"]))

    def test_dry_run_default_mode_when_not_specified(self):
        """Dry-run is the default mode when --mode is omitted."""
        result = self.run_scout([])

        self.assertEqual(result.returncode, 0, result.stderr)
        scout_result = json.loads(result.stdout)
        self.assertEqual(scout_result["mode"], "dry-run")

    def test_live_delivery_blocked_on_linux(self):
        """Live-delivery mode is blocked on Linux with BLOCKED_LINUX_WSL_REQUIRED."""
        result = self.run_scout(["--mode", "live-delivery"])

        # Exit code 1 for blocked/unimplemented
        self.assertEqual(result.returncode, 1, result.stderr)

        scout_result = json.loads(result.stdout)
        self.assertEqual(scout_result["mode"], "live-delivery")
        self.assertEqual(scout_result["proofCeiling"], "SCOUT_CONTRACT_STATIC")

        # On Linux, expect BLOCKED_LINUX_WSL_REQUIRED
        # On other platforms, expect UNIMPLEMENTED
        if platform.system() == "Linux":
            self.assertEqual(scout_result["status"], "BLOCKED_LINUX_WSL_REQUIRED")
            self.assertIn("Windows Admin Box", scout_result["reason"])
            self.assertEqual(scout_result["blockerType"], "HOST_CAPABILITY")
        else:
            self.assertEqual(scout_result["status"], "UNIMPLEMENTED")
            self.assertIn("not implemented", scout_result["reason"])

    def test_scout_accepts_resolved_variables(self):
        """Scout accepts and passes resolved variables to build_prompt_dispatch."""
        result = self.run_scout([
            "--mode", "dry-run",
            "--var", "repo=EndeavorEverlasting/AgentSwitchboard",
            "--var", "branch=main",
            "--var", "generation=1",
        ])

        self.assertEqual(result.returncode, 0, result.stderr)
        scout_result = json.loads(result.stdout)

        # Check artifact contains variables
        artifact_path = Path(scout_result["artifactPath"])
        dispatch = json.loads(artifact_path.read_text(encoding="utf-8"))
        self.assertEqual(dispatch["resolvedVariables"]["repo"], "EndeavorEverlasting/AgentSwitchboard")
        self.assertEqual(dispatch["resolvedVariables"]["branch"], "main")
        self.assertEqual(dispatch["resolvedVariables"]["generation"], 1)

    def test_scout_accepts_authority_configuration(self):
        """Scout accepts allowMutation and scope configurations."""
        result = self.run_scout([
            "--mode", "dry-run",
            "--allowed-scope", "owned-scope",
            "--forbidden-scope", "main",
            "--forbidden-scope", "protected/**",
        ])

        self.assertEqual(result.returncode, 0, result.stderr)
        scout_result = json.loads(result.stdout)

        # Check artifact contains authority fields
        artifact_path = Path(scout_result["artifactPath"])
        dispatch = json.loads(artifact_path.read_text(encoding="utf-8"))
        self.assertTrue(dispatch["authority"]["allowMutation"])
        self.assertEqual(dispatch["authority"]["allowedScopes"], ["owned-scope"])
        self.assertEqual(dispatch["authority"]["forbiddenScopes"], ["main", "protected/**"])

    def test_scout_rejects_invalid_decision(self):
        """Scout fails with ScoutError when decision cannot be loaded."""
        # Create invalid JSON
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            bad_decision = tmp_path / "bad-decision.json"
            bad_decision.write_text("{invalid json", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCOUT),
                    "--decision",
                    str(bad_decision),
                    "--firstmate-task-id",
                    "test",
                    "--instruction-summary",
                    "Test",
                    "--proof-gate",
                    "Test",
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 2)
            self.assertIn("Cannot load decision", result.stderr)

    def test_scout_propagates_contract_errors_from_builder(self):
        """Scout propagates ContractError from build_prompt_dispatch."""
        # Create decision with NO_ROUTE action (cannot be dispatched)
        bad_decision = {
            **self.decision,
            "decision": {
                **self.decision["decision"],
                "routeAction": "NO_ROUTE",
                "primaryPrompt": None,
            },
        }

        result = self.run_scout(["--mode", "dry-run"], decision=bad_decision)

        self.assertEqual(result.returncode, 2)
        self.assertIn("Cannot build dispatch", result.stderr)
        self.assertIn("NO_ROUTE", result.stderr)

    def test_scout_deterministic_for_same_inputs(self):
        """Scout produces same deliveryId and idempotency key for same inputs."""
        result1 = self.run_scout(["--mode", "dry-run"])
        result2 = self.run_scout(["--mode", "dry-run"])

        self.assertEqual(result1.returncode, 0)
        self.assertEqual(result2.returncode, 0)

        scout1 = json.loads(result1.stdout)
        scout2 = json.loads(result2.stdout)

        # Same deliveryId
        self.assertEqual(scout1["deliveryId"], scout2["deliveryId"])

        # Load artifacts and check idempotency keys
        dispatch1 = json.loads(Path(scout1["artifactPath"]).read_text())
        dispatch2 = json.loads(Path(scout2["artifactPath"]).read_text())

        self.assertEqual(
            dispatch1["idempotency"]["key"],
            dispatch2["idempotency"]["key"],
        )
        self.assertEqual(
            dispatch1["delivery"]["deliveryId"],
            dispatch2["delivery"]["deliveryId"],
        )

    def test_scout_writes_artifacts_to_timestamped_directory(self):
        """Scout writes artifacts to timestamped evidence directory."""
        result = self.run_scout(["--mode", "dry-run"])

        self.assertEqual(result.returncode, 0)
        scout_result = json.loads(result.stdout)

        artifact_path = Path(scout_result["artifactPath"])

        # Check directory structure: evidence_root / YYYYMMDDTHHMMSSZ / prompt-dispatch.json
        self.assertEqual(artifact_path.name, "prompt-dispatch.json")

        timestamp_dir = artifact_path.parent
        self.assertRegex(timestamp_dir.name, r"^\d{8}T\d{6}Z$")

        # Check both artifacts exist
        self.assertTrue((timestamp_dir / "prompt-dispatch.json").exists())
        self.assertTrue((timestamp_dir / "scout-receipt.json").exists())

    def test_scout_proof_ceiling_is_always_contract_static(self):
        """Scout always reports SCOUT_CONTRACT_STATIC proof ceiling."""
        for mode in ["dry-run", "live-delivery"]:
            with self.subTest(mode=mode):
                result = self.run_scout(["--mode", mode])

                # Both modes should complete (exit 0 or 1)
                self.assertIn(result.returncode, (0, 1), result.stderr)

                scout_result = json.loads(result.stdout)
                self.assertEqual(scout_result["proofCeiling"], "SCOUT_CONTRACT_STATIC")

    def test_scout_reports_blocked_type_for_linux(self):
        """Scout reports blockerType=HOST_CAPABILITY when blocked on Linux."""
        if platform.system() != "Linux":
            self.skipTest("This test only runs on Linux")

        result = self.run_scout(["--mode", "live-delivery"])

        self.assertEqual(result.returncode, 1)
        scout_result = json.loads(result.stdout)
        self.assertEqual(scout_result["status"], "BLOCKED_LINUX_WSL_REQUIRED")
        self.assertEqual(scout_result["blockerType"], "HOST_CAPABILITY")


if __name__ == "__main__":
    unittest.main()
