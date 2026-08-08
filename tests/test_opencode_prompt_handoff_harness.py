#!/usr/bin/env python3
"""Portable contract for the AgentSwitchboard OpenCode prompt-handoff harness."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def load(relative: str) -> dict:
    return json.loads(read(relative))


class OpenCodePromptHandoffHarnessTests(unittest.TestCase):
    def test_required_components_exist(self) -> None:
        required = [
            "tooling/harness/operational/opencode-prompt-handoff/manifest.json",
            "tooling/harness/operational/opencode-prompt-handoff/codebase-map.json",
            "tooling/harness/operational/opencode-prompt-handoff/artifact-registry.json",
            "tooling/harness/operational/opencode-prompt-handoff/workflows/materialize-preflight-execute.workflow.json",
            "tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1",
            "tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPreCommit.ps1",
            "tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPrePush.ps1",
            ".ai/skills/opencode-prompt-handoff/SKILL.md",
            "docs/harness/opencode-prompt-handoff.md",
            "scripts/Test-OpenCodePromptHandoffHarness.ps1",
            "tests/test_opencode_prompt_handoff_harness.py",
            ".github/workflows/opencode-prompt-handoff-harness.yml",
            "tooling/gnhf/Start-AgentSwitchboardOpenCode.ps1",
        ]
        for relative in required:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_manifest_is_harness_only_and_transport_is_bound(self) -> None:
        manifest = load("tooling/harness/operational/opencode-prompt-handoff/manifest.json")
        self.assertEqual(manifest["harnessId"], "agentswitchboard.opencode-prompt-handoff.v1")
        self.assertFalse(manifest["generatedEvidence"]["tracked"])
        self.assertFalse(manifest["hooks"]["implicitInstallationAllowed"])
        self.assertFalse(manifest["safety"]["productMutationAllowed"])
        self.assertFalse(manifest["safety"]["governanceMutationOwned"])
        self.assertFalse(manifest["safety"]["destructiveGitAllowed"])
        self.assertTrue(manifest["integration"]["preflightAndExecutionUseSamePromptPath"])
        self.assertFalse(manifest["integration"]["clipboardMayBridgePreflightToExecution"])
        for relative in manifest["entrypoints"].values():
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_artifact_contract_keeps_raw_prompt_out_of_receipts(self) -> None:
        registry = load("tooling/harness/operational/opencode-prompt-handoff/artifact-registry.json")
        self.assertFalse(registry["trackedGeneratedArtifacts"])
        by_id = {item["artifactId"]: item for item in registry["artifacts"]}
        self.assertEqual(set(by_id), {"bounded-sprint-prompt", "prompt-handoff-receipt", "prompt-handoff-operator-report"})
        self.assertTrue(by_id["bounded-sprint-prompt"]["containsRawPrompt"])
        self.assertFalse(by_id["prompt-handoff-receipt"]["containsRawPrompt"])
        self.assertFalse(by_id["prompt-handoff-operator-report"]["containsRawPrompt"])
        self.assertTrue(all(item["tracked"] is False for item in by_id.values()))

    def test_workflow_requires_materialize_preflight_rehash_execute(self) -> None:
        workflow = load("tooling/harness/operational/opencode-prompt-handoff/workflows/materialize-preflight-execute.workflow.json")
        text = "\n".join(workflow["steps"])
        self.assertIn("Read the prompt exactly once", text)
        self.assertIn("Materialize those exact prompt bytes", text)
        self.assertIn("PlanOnly mode with -PromptPath", text)
        self.assertIn("Recompute SHA-256 after preflight", text)
        self.assertIn("exact same -PromptPath", text)
        self.assertTrue(workflow["proofCeiling"])

    def test_runner_reads_clipboard_once_and_never_uses_it_as_gate_bridge(self) -> None:
        runner = read("tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1")
        self.assertEqual(len(re.findall(r"\bGet-Clipboard\b", runner)), 1)
        self.assertIn("Set-Content -LiteralPath $promptArtifact", runner)
        self.assertIn("'-PromptPath', $promptArtifact", runner)
        self.assertIn("if ($PlanOnly) { [void]$arguments.Add('-PlanOnly') }", runner)
        self.assertIn("Prompt artifact changed during preflight", runner)
        self.assertIn("Prompt artifact changed between preflight and execution", runner)
        self.assertIn("rawPromptRecordedInReceipt = $false", runner)
        self.assertNotRegex(runner.lower(), r"reset\s+--hard|git\s+clean|force-push|core\.hookspath")

    def test_existing_product_contract_supports_safe_handoff(self) -> None:
        product = read("tooling/gnhf/Start-AgentSwitchboardOpenCode.ps1")
        self.assertIn("[string]$PromptPath", product)
        self.assertIn("[switch]$PlanOnly", product)
        self.assertIn("-PromptPath", product)

    def test_skill_and_docs_explain_no_recopy_contract(self) -> None:
        skill = read(".ai/skills/opencode-prompt-handoff/SKILL.md")
        for token in (
            "id: opencode-prompt-handoff",
            "status: canonical",
            "## Trigger",
            "## Procedure",
            "## Deterministic validation",
            "Do not ask the operator to copy the same prompt again",
        ):
            self.assertIn(token, skill)
        guide = read("docs/harness/opencode-prompt-handoff.md")
        self.assertIn("Nothing later in that invocation reads the clipboard again", guide)
        self.assertIn("same `-PromptPath`", guide)
        self.assertIn("Proof ceiling", guide)

    def test_hooks_are_opt_in_and_non_destructive(self) -> None:
        pre_commit = read("tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPreCommit.ps1")
        pre_push = read("tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPrePush.ps1")
        for text in (pre_commit, pre_push):
            self.assertIn("Test-OpenCodePromptHandoffHarness.ps1", text)
            self.assertNotRegex(text.lower(), r"core\.hookspath|git\s+config|reset\s+--hard|git\s+clean|force-push")
        self.assertIn("diff --cached --check", pre_commit)
        self.assertIn("[Parameter(Mandatory)][string]$BaseRef", pre_push)
        self.assertIn("diff --check", pre_push)

    def test_operational_spine_registers_handoff_harness(self) -> None:
        manifest = load("tooling/harness/operational/manifest.json")
        self.assertEqual(
            manifest["entrypoints"]["promptHandoffHarness"],
            "tooling/harness/operational/opencode-prompt-handoff/manifest.json",
        )
        codebase = load("tooling/harness/operational/codebase-map.json")
        paths = {item["path"] for item in codebase["structure"]}
        self.assertIn("tooling/harness/operational/opencode-prompt-handoff/", paths)
        self.assertTrue(any("clipboard" in trap.lower() and "preflight" in trap.lower() for trap in codebase["knownTraps"]))
        workflows = load("tooling/harness/operational/workflow-registry.json")
        routes = {item.get("skill") for item in workflows["specializedRouting"]}
        self.assertIn(".ai/skills/opencode-prompt-handoff/SKILL.md", routes)
        validators = load("tooling/harness/operational/validator-registry.json")
        ids = {item["id"] for item in validators["validators"]}
        self.assertIn("opencode-prompt-handoff", ids)
        self.assertIn("opencode-prompt-handoff-portable", ids)


if __name__ == "__main__":
    unittest.main()
