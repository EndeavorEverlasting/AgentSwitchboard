#!/usr/bin/env python3
"""Behavior tests for the routing-decision → prompt-dispatch builder."""

from __future__ import annotations

import copy
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tooling/firstmate/harness/dispatch/build_prompt_dispatch.py"
DECISION_FIXTURE = ROOT / ".ai/harness/fixtures/fm-asb-promptkit/routing-decision.valid.json"
DISPATCH_FIXTURE = ROOT / ".ai/harness/fixtures/fm-asb-promptkit/prompt-dispatch.valid.json"

EVENT_RE = re.compile(r"^evt_[A-Za-z0-9][A-Za-z0-9._-]{7,95}$")
IDEM_RE = re.compile(r"^idem_[a-f0-9]{64}$")
SHA_RE = re.compile(r"^[a-f0-9]{64}$")
DELIVERY_ID_RE = re.compile(r"^[a-f0-9]{16,64}$")


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


def delivery_id(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:16]


class PromptDispatchBuilderTests(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.decision = json.loads(DECISION_FIXTURE.read_text(encoding="utf-8"))
        self.dispatch = json.loads(DISPATCH_FIXTURE.read_text(encoding="utf-8"))

    def run_builder(self, decision: dict, args: list[str] | None = None) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "decision.json"
            path.write_text(json.dumps(decision), encoding="utf-8")

            command = [
                sys.executable,
                str(BUILDER),
                "--decision",
                str(path),
                "--firstmate-task-id",
                "task-42",
                "--instruction-summary",
                "Test summary",
                "--proof-gate",
                "Test proof gate",
            ]
            if args:
                command.extend(args)
            return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_builder_exists_and_is_read_only(self):
        """Builder module exists and contains no subprocess/network/tmux surface."""
        self.assertTrue(BUILDER.is_file())
        source = BUILDER.read_text(encoding="utf-8")
        for forbidden in ("subprocess.", "fm-send", "fm-control", "capture-pane", "tmux"):
            self.assertNotIn(forbidden, source, f"Builder must not contain {forbidden}")

    def test_builds_valid_dispatch_for_switch_prompt_decision(self):
        """Builder emits valid asb.prompt-dispatch/v1 from SWITCH_PROMPT decision."""
        result = self.run_builder(self.decision)
        self.assertEqual(result.returncode, 0, result.stderr)

        dispatch = json.loads(result.stdout)
        self.assertEqual(dispatch["schema"], "asb.prompt-dispatch/v1")
        self.assertRegex(dispatch["eventId"], EVENT_RE)
        self.assertEqual(dispatch["correlationId"], self.decision["correlationId"])
        self.assertEqual(dispatch["causationId"], self.decision["eventId"])
        self.assertEqual(dispatch["routingDecisionEventId"], self.decision["eventId"])
        self.assertEqual(dispatch["producer"]["component"], "firstmate-dispatch-adapter")

        # Target
        self.assertEqual(dispatch["target"]["firstMateTaskId"], "task-42")
        self.assertEqual(dispatch["target"]["deliveryPlane"], "durable-inbox")

        # Prompt - reference mode, inlineText null
        self.assertEqual(dispatch["prompt"]["ref"], self.decision["decision"]["primaryPrompt"])
        self.assertEqual(dispatch["prompt"]["deliveryMode"], "reference")
        self.assertIsNone(dispatch["prompt"]["inlineText"])

        # Delivery
        self.assertRegex(dispatch["delivery"]["deliveryId"], DELIVERY_ID_RE)
        self.assertTrue(dispatch["delivery"]["expectsReply"])
        self.assertEqual(dispatch["delivery"]["resolveKeys"], [])

        # Idempotency
        self.assertRegex(dispatch["idempotency"]["key"], IDEM_RE)
        self.assertRegex(dispatch["idempotency"]["semanticSha256"], SHA_RE)
        self.assertEqual(dispatch["idempotency"]["semanticSha256"], semantic_sha(dispatch))

    def test_idempotency_key_matches_protocol_identity(self):
        """Idempotency key follows asb.prompt-dispatch/v1 identity pattern."""
        result = self.run_builder(self.decision)
        self.assertEqual(result.returncode, 0, result.stderr)

        dispatch = json.loads(result.stdout)
        expected_key = idem_key(
            "asb.prompt-dispatch/v1",
            dispatch["routingDecisionEventId"],
            dispatch["target"]["firstMateTaskId"],
            dispatch["prompt"]["ref"]["promptSha256"],
        )
        self.assertEqual(dispatch["idempotency"]["key"], expected_key)

    def test_delivery_id_is_deterministic_from_identity_components(self):
        """DeliveryId is deterministic and reused for retries of same identity."""
        result1 = self.run_builder(self.decision)
        result2 = self.run_builder(self.decision)
        self.assertEqual(result1.returncode, 0)
        self.assertEqual(result2.returncode, 0)

        dispatch1 = json.loads(result1.stdout)
        dispatch2 = json.loads(result2.stdout)

        # Same identity → same deliveryId
        self.assertEqual(dispatch1["delivery"]["deliveryId"], dispatch2["delivery"]["deliveryId"])

        expected_delivery = delivery_id(
            "asb.prompt-dispatch/v1",
            dispatch1["routingDecisionEventId"],
            dispatch1["target"]["firstMateTaskId"],
            dispatch1["prompt"]["ref"]["promptSha256"],
        )
        self.assertEqual(dispatch1["delivery"]["deliveryId"], expected_delivery)

    def test_fails_closed_for_no_route_action(self):
        """Builder rejects NO_ROUTE action with ContractError."""
        decision = copy.deepcopy(self.decision)
        decision["decision"]["routeAction"] = "NO_ROUTE"
        decision["decision"]["primaryPrompt"] = None

        result = self.run_builder(decision)
        self.assertEqual(result.returncode, 2)
        self.assertIn("NO_ROUTE", result.stderr)
        self.assertIn("no prompt is routed", result.stderr.lower())

    def test_fails_closed_for_blocked_action(self):
        """Builder rejects BLOCKED action with ContractError."""
        decision = copy.deepcopy(self.decision)
        decision["decision"]["routeAction"] = "BLOCKED"
        decision["decision"]["primaryPrompt"] = None

        result = self.run_builder(decision)
        self.assertEqual(result.returncode, 2)
        self.assertIn("BLOCKED", result.stderr)
        self.assertIn("no prompt is routed", result.stderr.lower())

    def test_fails_closed_when_primary_prompt_null_for_switch_prompt(self):
        """Builder rejects SWITCH_PROMPT with null primaryPrompt."""
        decision = copy.deepcopy(self.decision)
        decision["decision"]["routeAction"] = "SWITCH_PROMPT"
        decision["decision"]["primaryPrompt"] = None

        result = self.run_builder(decision)
        self.assertEqual(result.returncode, 2)
        self.assertIn("primaryPrompt must not be null", result.stderr)

    def test_fails_closed_when_primary_prompt_null_for_keep_current_prompt(self):
        """Builder rejects KEEP_CURRENT_PROMPT with null primaryPrompt."""
        decision = copy.deepcopy(self.decision)
        decision["decision"]["routeAction"] = "KEEP_CURRENT_PROMPT"
        decision["decision"]["primaryPrompt"] = None

        result = self.run_builder(decision)
        self.assertEqual(result.returncode, 2)
        self.assertIn("primaryPrompt must not be null", result.stderr)

    def test_accepts_keep_current_prompt_with_valid_primary(self):
        """Builder accepts KEEP_CURRENT_PROMPT when primaryPrompt is present."""
        decision = copy.deepcopy(self.decision)
        decision["decision"]["routeAction"] = "KEEP_CURRENT_PROMPT"

        result = self.run_builder(decision)
        self.assertEqual(result.returncode, 0, result.stderr)

        dispatch = json.loads(result.stdout)
        self.assertEqual(dispatch["prompt"]["deliveryMode"], "reference")
        self.assertIsNone(dispatch["prompt"]["inlineText"])

    def test_rejects_invalid_prompt_ref_structure(self):
        """Builder rejects malformed promptRef with ContractError."""
        for label, mutate in [
            ("missing id", lambda p: p.pop("id")),
            ("invalid id pattern", lambda p: p.update({"id": "BAD"})),
            ("missing promptSha256", lambda p: p.pop("promptSha256")),
            ("invalid promptSha256", lambda p: p.update({"promptSha256": "not-a-sha"})),
            ("invalid executionSurface", lambda p: p.update({"executionSurface": "shell"})),
            ("extra field", lambda p: p.update({"unexpected": "value"})),
        ]:
            with self.subTest(label=label):
                decision = copy.deepcopy(self.decision)
                mutate(decision["decision"]["primaryPrompt"])
                result = self.run_builder(decision)
                self.assertEqual(result.returncode, 2, f"Expected failure for {label}")
                self.assertIn("primaryPrompt", result.stderr)

    def test_rejects_invalid_task_id_pattern(self):
        """Builder rejects invalid FirstMate task ID."""
        result = self.run_builder(
            self.decision,
            args=[
                "--firstmate-task-id",
                "invalid task id with spaces",
                "--instruction-summary",
                "Test",
                "--proof-gate",
                "Test",
            ],
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("firstmate_task_id", result.stderr)

    def test_rejects_invalid_instruction_summary_bounds(self):
        """Builder rejects instruction summary outside 1..4000 bounds."""
        for bad_summary in ["", "x" * 4001]:
            result = self.run_builder(
                self.decision,
                args=[
                    "--firstmate-task-id",
                    "task-42",
                    "--instruction-summary",
                    bad_summary,
                    "--proof-gate",
                    "Test",
                ],
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("instruction_summary", result.stderr)

    def test_rejects_invalid_proof_gate_bounds(self):
        """Builder rejects proof gate outside 1..4000 bounds."""
        for bad_gate in ["", "x" * 4001]:
            result = self.run_builder(
                self.decision,
                args=[
                    "--firstmate-task-id",
                    "task-42",
                    "--instruction-summary",
                    "Test",
                    "--proof-gate",
                    bad_gate,
                ],
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("proof_gate", result.stderr)

    def test_accepts_resolved_variables_with_protocol_types(self):
        """Builder accepts string, number, boolean, null variable values."""
        result = self.run_builder(
            self.decision,
            args=[
                "--firstmate-task-id",
                "task-42",
                "--instruction-summary",
                "Test",
                "--proof-gate",
                "Test",
                "--var",
                "stringVar=hello",
                "--var",
                "numberVar=42",
                "--var",
                "boolVar=true",
                "--var",
                'nullVar=null',
            ],
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        dispatch = json.loads(result.stdout)
        self.assertEqual(dispatch["resolvedVariables"]["stringVar"], "hello")
        self.assertEqual(dispatch["resolvedVariables"]["numberVar"], 42)
        self.assertTrue(dispatch["resolvedVariables"]["boolVar"])
        self.assertIsNone(dispatch["resolvedVariables"]["nullVar"])

    def test_rejects_invalid_expected_generation(self):
        """Builder rejects negative expected generation."""
        result = self.run_builder(
            self.decision,
            args=[
                "--firstmate-task-id",
                "task-42",
                "--instruction-summary",
                "Test",
                "--proof-gate",
                "Test",
                "--expected-generation",
                "-1",
            ],
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("expected_generation", result.stderr)

    def test_rejects_invalid_rfc3339_timestamp(self):
        """Builder rejects non-RFC3339 createdAt."""
        result = self.run_builder(
            self.decision,
            args=[
                "--firstmate-task-id",
                "task-42",
                "--instruction-summary",
                "Test",
                "--proof-gate",
                "Test",
                "--created-at",
                "2026-09-19 12:00:00",
            ],
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("createdAt", result.stderr)

    def test_builder_is_deterministic_for_same_inputs(self):
        """Builder produces identical output for identical inputs."""
        result1 = self.run_builder(self.decision)
        result2 = self.run_builder(self.decision)
        self.assertEqual(result1.returncode, 0)
        self.assertEqual(result2.returncode, 0)
        self.assertEqual(json.loads(result1.stdout), json.loads(result2.stdout))

    def test_authority_fields_are_configurable(self):
        """Builder accepts allowMutation and scope configurations."""
        result = self.run_builder(
            self.decision,
            args=[
                "--firstmate-task-id",
                "task-42",
                "--instruction-summary",
                "Test",
                "--proof-gate",
                "Test",
                "--allowed-scope",
                "owned-scope",
                "--forbidden-scope",
                "main",
                "--forbidden-scope",
                "protected/**",
            ],
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        dispatch = json.loads(result.stdout)
        self.assertTrue(dispatch["authority"]["allowMutation"])
        self.assertEqual(dispatch["authority"]["allowedScopes"], ["owned-scope"])
        self.assertEqual(dispatch["authority"]["forbiddenScopes"], ["main", "protected/**"])

    def test_expected_result_fields_are_protocol_compliant(self):
        """Builder sets expected result with all protocol states and validation required."""
        result = self.run_builder(self.decision)
        self.assertEqual(result.returncode, 0, result.stderr)

        dispatch = json.loads(result.stdout)
        self.assertEqual(
            set(dispatch["expectedResult"]["acceptedStates"]),
            {"running", "needs-decision", "blocked", "completed", "failed"},
        )
        self.assertTrue(dispatch["expectedResult"]["coordinatorValidationRequired"])


if __name__ == "__main__":
    unittest.main()
