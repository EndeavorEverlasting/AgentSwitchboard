import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tooling" / "harness" / "operational" / "opinion-ledger" / "opinion_ledger.py"
MANIFEST = ROOT / "tooling" / "harness" / "operational" / "opinion-ledger" / "manifest.json"
POLICY = ROOT / "tooling" / "harness" / "operational" / "opinion-ledger" / "opinion-ledger.policy.json"
SCHEMA = ROOT / "tooling" / "harness" / "operational" / "opinion-ledger" / "opinion-entry.schema.json"
OPERATIONAL_MANIFEST = ROOT / "tooling" / "harness" / "operational" / "manifest.json"
WORKFLOW_REGISTRY = ROOT / "tooling" / "harness" / "operational" / "workflow-registry.json"
STATUS_REPORTER = ROOT / "tooling" / "harness" / "operational" / "Get-OperationalHarnessStatus.py"


def invoke(state_root, *args, env=None):
    command = [sys.executable, str(RUNNER), "--state-root", str(state_root), *args]
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, env=env)


def load_status_reporter():
    spec = importlib.util.spec_from_file_location("agentswitchboard_operational_status", STATUS_REPORTER)
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load operational status reporter")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class OpinionLedgerTracerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state_root = pathlib.Path(self.temp.name) / "state"

    def tearDown(self):
        self.temp.cleanup()

    def test_record_then_search_preserves_advisory_boundary(self):
        recorded = invoke(
            self.state_root,
            "record",
            "--text", "Phone UX should use native interaction paths.",
            "--scope", "prompt-kit",
            "--source-type", "operator",
            "--confidence", "high",
            "--tag", "mobile",
            "--tag", "ux",
        )
        self.assertEqual(recorded.returncode, 0, recorded.stderr)
        payload = json.loads(recorded.stdout)
        entry = payload["entry"]
        self.assertTrue(payload["recorded"])
        self.assertEqual(entry["visibility"], "local-only")
        self.assertEqual(entry["status"], "candidate")
        self.assertTrue(entry["advisory_only"])
        self.assertFalse(entry["execution_authority"])
        self.assertIsNone(entry["promoted_owner"])

        searched = invoke(self.state_root, "search", "--query", "phone")
        self.assertEqual(searched.returncode, 0, searched.stderr)
        results = json.loads(searched.stdout)
        self.assertEqual(results["count"], 1)
        self.assertEqual(results["results"][0]["opinion_id"], entry["opinion_id"])

    def test_search_matches_tags_and_is_case_insensitive(self):
        result = invoke(
            self.state_root,
            "record",
            "--text", "Prefer bounded proof.",
            "--scope", "engineering",
            "--tag", "Evidence-First",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        searched = invoke(self.state_root, "search", "--query", "evidence-first")
        self.assertEqual(searched.returncode, 0, searched.stderr)
        self.assertEqual(json.loads(searched.stdout)["count"], 1)

    def test_empty_text_fails_without_creating_state(self):
        result = invoke(self.state_root, "record", "--text", "   ", "--scope", "engineering")
        self.assertEqual(result.returncode, 2)
        self.assertIn("text must not be empty", result.stderr)
        self.assertFalse((self.state_root / "opinions.jsonl").exists())

    def test_corrupt_state_fails_closed(self):
        self.state_root.mkdir(parents=True)
        (self.state_root / "opinions.jsonl").write_text("{not-json\n", encoding="utf-8")
        result = invoke(self.state_root, "search", "--query", "anything")
        self.assertEqual(result.returncode, 2)
        self.assertIn("malformed JSON", result.stderr)

    def test_tampered_entry_fails_closed(self):
        recorded = invoke(
            self.state_root,
            "record",
            "--text", "Keep evidence immutable.",
            "--scope", "engineering",
        )
        self.assertEqual(recorded.returncode, 0, recorded.stderr)
        ledger = self.state_root / "opinions.jsonl"
        entry = json.loads(ledger.read_text(encoding="utf-8"))
        entry["text"] = "Tampered after record."
        ledger.write_text(json.dumps(entry) + "\n", encoding="utf-8")
        searched = invoke(self.state_root, "search", "--query", "tampered")
        self.assertEqual(searched.returncode, 2)
        self.assertIn("opinion_id does not match entry content", searched.stderr)

    def test_state_root_command_is_read_only(self):
        result = invoke(self.state_root, "state-root")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(pathlib.Path(payload["state_root"]), self.state_root)
        self.assertFalse(self.state_root.exists())

    def test_state_root_inside_checkout_is_rejected(self):
        tracked_candidate = ROOT / ".opinion-ledger-test-state"
        result = invoke(tracked_candidate, "state-root")
        self.assertEqual(result.returncode, 2)
        self.assertIn("inside the Git checkout", result.stderr)
        self.assertFalse(tracked_candidate.exists())

    def test_environment_override_is_supported_without_username_literal(self):
        override = pathlib.Path(self.temp.name) / "override"
        env = os.environ.copy()
        env["AGENTSWITCHBOARD_OPINION_STATE_ROOT"] = str(override)
        result = subprocess.run(
            [sys.executable, str(RUNNER), "state-root"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(pathlib.Path(json.loads(result.stdout)["state_root"]), override)

    def test_contract_forbids_remote_sync_and_personal_history_ownership(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.assertFalse(manifest["safety"]["remoteSyncAllowed"])
        self.assertFalse(manifest["safety"]["trackedOpinionContentAllowed"])
        self.assertFalse(policy["boundaries"]["personalAccomplishmentHistoryOwned"])
        self.assertFalse(policy["boundaries"]["healthOrSensitivePersonalHistoryOwned"])
        self.assertFalse(policy["boundaries"]["mcpOwned"])
        self.assertFalse(policy["boundaries"]["sqliteOwned"])
        self.assertFalse(policy["boundaries"]["automaticPromotionAllowed"])
        self.assertIs(schema["properties"]["execution_authority"]["const"], False)
        self.assertEqual(schema["properties"]["visibility"]["const"], "local-only")
        self.assertEqual(schema["properties"]["status"]["const"], "candidate")

    def test_operational_router_selects_opinion_tracer(self):
        operational_manifest = json.loads(OPERATIONAL_MANIFEST.read_text(encoding="utf-8"))
        workflow_registry = json.loads(WORKFLOW_REGISTRY.read_text(encoding="utf-8"))
        reporter = load_status_reporter()
        workflow, specialized = reporter.select_route(
            "record a reusable engineering opinion for later agents",
            workflow_registry,
        )
        self.assertEqual(workflow, "task-intake")
        self.assertEqual(specialized, ".ai/skills/opinion-ledger-tracer/SKILL.md")
        self.assertEqual(
            operational_manifest["entrypoints"]["opinionLedgerTracerHarness"],
            "tooling/harness/operational/opinion-ledger/manifest.json",
        )
        matching_routes = [
            item for item in workflow_registry["specializedRouting"]
            if item["skill"] == ".ai/skills/opinion-ledger-tracer/SKILL.md"
        ]
        self.assertEqual(len(matching_routes), 1)
        self.assertEqual(
            matching_routes[0]["workflowRoot"],
            "tooling/harness/operational/opinion-ledger/workflows/",
        )


if __name__ == "__main__":
    unittest.main()
