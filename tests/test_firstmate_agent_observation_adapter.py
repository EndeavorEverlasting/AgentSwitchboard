#!/usr/bin/env python3
"""Behavior tests for the FirstMate → ASB observation adapter."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "tooling/firstmate/harness/observation/emit_agent_observation.py"
FIXTURE = ROOT / ".ai/harness/fixtures/fm-asb-promptkit/firstmate-fleet-snapshot.valid.json"
BASE_ARGS = [
    sys.executable,
    str(ADAPTER),
    "--snapshot",
    str(FIXTURE),
    "--repository-full-name",
    "EndeavorEverlasting/example-repo",
    "--branch",
    "feat/example",
    "--head-sha",
    "a" * 40,
    "--correlation-id",
    "corr_example_mission_0001",
    "--grounding-episode-id",
    "ge_example_grounding_0001",
]
EVENT_RE = re.compile(r"^evt_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
IDEM_RE = re.compile(r"^idem_[a-f0-9]{64}$")


def canonical_json(value) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def semantic_sha(message: dict) -> str:
    payload = {
        key: value
        for key, value in message.items()
        if key not in {"eventId", "createdAt", "idempotency"}
    }
    return hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def idem_key(*parts: str) -> str:
    return "idem_" + hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()


class ObservationAdapterTests(unittest.TestCase):
    maxDiff = None

    def run_adapter(self, task_id: str, *, snapshot: Path | None = None, args: list[str] | None = None):
        command = list(BASE_ARGS if args is None else args)
        if snapshot is not None:
            command[command.index(str(FIXTURE))] = str(snapshot)
        command.extend(["--task-id", task_id])
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def run_with_snapshot_data(self, data: dict, task_id: str = "ship-task"):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "snapshot.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            return self.run_adapter(task_id, snapshot=path)

    def output_for(self, task_id: str) -> dict:
        result = self.run_adapter(task_id)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_working_task_emits_contract_shape_without_raw_or_private_state(self):
        observation = self.output_for("ship-task")
        self.assertEqual(observation["schema"], "asb.agent-observation/v1")
        self.assertRegex(observation["eventId"], EVENT_RE)
        self.assertEqual(observation["correlationId"], "corr_example_mission_0001")
        self.assertIsNone(observation["causationId"])
        self.assertEqual(observation["producer"]["component"], "firstmate-observation-adapter")
        self.assertEqual(observation["source"]["system"], "firstmate")
        self.assertEqual(observation["source"]["taskId"], "ship-task")
        self.assertEqual(observation["source"]["taskKind"], "ship")
        self.assertEqual(observation["source"]["harness"], "claude")
        self.assertEqual(observation["source"]["backend"], "tmux")
        self.assertEqual(observation["source"]["generation"], 4)
        self.assertEqual(
            observation["state"],
            {"phase": "running", "terminal": False, "statusKey": "firstmate:running"},
        )
        self.assertEqual(observation["output"]["format"], "none")
        self.assertFalse(observation["output"]["rawIncluded"])
        self.assertIsNone(observation["contextPressure"])
        self.assertRegex(observation["idempotency"]["key"], IDEM_RE)
        self.assertEqual(
            observation["idempotency"]["key"],
            idem_key(
                "asb.agent-observation/v1",
                observation["source"]["taskId"],
                observation["source"]["eventKey"],
            ),
        )
        self.assertEqual(observation["idempotency"]["semanticSha256"], semantic_sha(observation))

        rendered = json.dumps(observation)
        for forbidden in (
            "SENSITIVE_DETAIL_MUST_NOT_ESCAPE",
            "RAW_TRANSCRIPT_MUST_NOT_ESCAPE",
            "RAW_EVENT_MUST_NOT_ESCAPE",
            "/fixture/worktrees/secret-example",
        ):
            self.assertNotIn(forbidden, rendered)
        self.assertTrue(observation["repository"]["worktreeId"].startswith("fm_ship-task_"))
        self.assertFalse(observation["evidence"][0]["containsRawUserText"])
        self.assertFalse(observation["evidence"][0]["containsSecrets"])

    def test_adapter_is_deterministic_for_same_snapshot_and_inputs(self):
        self.assertEqual(self.output_for("ship-task"), self.output_for("ship-task"))

    def test_pending_decision_maps_without_summary_text(self):
        observation = self.output_for("decision-task")
        self.assertEqual(observation["state"]["phase"], "needs-decision")
        self.assertFalse(observation["state"]["terminal"])
        self.assertEqual(observation["source"]["eventType"], "needs-decision")
        self.assertNotIn("choose API", json.dumps(observation))

    def test_done_task_maps_to_terminal_completed(self):
        observation = self.output_for("scout-task")
        self.assertEqual(observation["state"]["phase"], "completed")
        self.assertTrue(observation["state"]["terminal"])
        self.assertEqual(observation["source"]["eventType"], "task-terminal")

    def test_unknown_state_maps_to_unknown_without_inventing_runtime_state(self):
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        data["tasks"][0]["current_state"]["state"] = "future-firstmate-state"
        result = self.run_with_snapshot_data(data)
        self.assertEqual(result.returncode, 0, result.stderr)
        observation = json.loads(result.stdout)
        self.assertEqual(observation["state"]["phase"], "unknown")
        self.assertFalse(observation["state"]["terminal"])

    def test_rejects_wrong_snapshot_schema(self):
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        data["schema"] = "not-firstmate"
        result = self.run_with_snapshot_data(data)
        self.assertEqual(result.returncode, 2)
        self.assertIn("snapshot.schema", result.stderr)

    def test_rejects_noncanonical_rfc3339_timestamp(self):
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        data["generated"] = "2026-09-14 20:30:00+00:00"
        result = self.run_with_snapshot_data(data)
        self.assertEqual(result.returncode, 2)
        self.assertIn("canonical RFC3339", result.stderr)

    def test_boolean_generation_never_serializes_as_boolean(self):
        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        data["tasks"][0]["spawn_gen"] = True
        result = self.run_with_snapshot_data(data)
        self.assertEqual(result.returncode, 0, result.stderr)
        observation = json.loads(result.stdout)
        self.assertIsNone(observation["source"]["generation"])

    def test_rejects_harness_or_backend_that_exceeds_schema_bound(self):
        for field in ("harness", "backend"):
            with self.subTest(field=field):
                data = json.loads(FIXTURE.read_text(encoding="utf-8"))
                data["tasks"][0][field] = "x" * 65
                result = self.run_with_snapshot_data(data)
                self.assertEqual(result.returncode, 2)
                self.assertIn(f"task.{field} exceeds 64 characters", result.stderr)

    def test_rejects_branch_that_exceeds_schema_bound(self):
        args = list(BASE_ARGS)
        args[args.index("feat/example")] = "b" * 256
        result = self.run_adapter("ship-task", args=args)
        self.assertEqual(result.returncode, 2)
        self.assertIn("branch exceeds 255 characters", result.stderr)

    def test_rejects_missing_or_duplicate_task(self):
        missing = self.run_adapter("does-not-exist")
        self.assertEqual(missing.returncode, 2)
        self.assertIn("found 0", missing.stderr)

        data = json.loads(FIXTURE.read_text(encoding="utf-8"))
        data["tasks"].append(dict(data["tasks"][0]))
        duplicate = self.run_with_snapshot_data(data)
        self.assertEqual(duplicate.returncode, 2)
        self.assertIn("found 2", duplicate.stderr)

    def test_rejects_invalid_protocol_identifiers(self):
        args = list(BASE_ARGS)
        args[args.index("corr_example_mission_0001")] = "bad-correlation"
        result = self.run_adapter("ship-task", args=args)
        self.assertEqual(result.returncode, 2)
        self.assertIn("correlation_id", result.stderr)

    def test_no_firstmate_invocation_or_watcher_surface_is_embedded(self):
        source = ADAPTER.read_text(encoding="utf-8")
        for forbidden in (
            "subprocess.",
            "fm-watch",
            "fm-send",
            "fm-control",
            "capture-pane",
        ):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
