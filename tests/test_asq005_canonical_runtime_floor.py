"""Fail closed if ASQ-005 drifts off the Live floor or weakens G0-G8."""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK_QUEUE = ROOT / ".ai" / "WORK_QUEUE.md"
RUNTIME_DOC = ROOT / "docs" / "harness" / "opencode-lsp-workstation-setup.md"
GATES_DOC = ROOT / "docs" / "harness" / "asq005-fresh-tui-lsp-runtime-gates.md"
GATES_CONTRACT = (
    ROOT
    / "tooling"
    / "harness"
    / "operational"
    / "opencode-lsp-setup"
    / "asq005-runtime-gates.contract.json"
)
SEPTEMBER_PLAN = ROOT / "plans" / "active" / "ASB-2026-09-agent-bootstrap-child-bus.plan.json"
MANIFEST = ROOT / "tooling" / "harness" / "operational" / "opencode-lsp-setup" / "manifest.json"
FIXTURE = ROOT / "tests" / "test_technician_live_cert_surface.py"

_PRIVATE_PATH_MARKERS = ("onedrive", "northwell", "desktop\\dev", "og laptop backup", "pa_rperez")
_GATE_IDS = tuple(f"G{i}" for i in range(9))


def _section(text: str, heading: str, next_heading_prefix: str = "## ASQ-") -> str:
    start = text.find(heading)
    if start < 0:
        raise AssertionError(f"missing heading: {heading}")
    rest = text[start + len(heading) :]
    end = rest.find(next_heading_prefix)
    return rest if end < 0 else rest[:end]


class Asq005CanonicalRuntimeFloorTests(unittest.TestCase):
    def test_fixture_symbol_exists(self) -> None:
        self.assertTrue(FIXTURE.is_file(), FIXTURE)
        self.assertIn("def read_text(", FIXTURE.read_text(encoding="utf-8"))

    def test_asq005_next_action_uses_canonical_live_configure_flow(self) -> None:
        text = WORK_QUEUE.read_text(encoding="utf-8")
        block = _section(text, "## ASQ-005")
        next_action = None
        for line in block.splitlines():
            if line.startswith("- **Next action:**"):
                next_action = line
                break
        self.assertIsNotNone(next_action)
        assert next_action is not None
        lowered = next_action.lower()
        for forbidden in _PRIVATE_PATH_MARKERS:
            self.assertNotIn(forbidden, lowered, next_action)
        self.assertTrue(lowered.startswith("- **next action:** run "))
        self.assertIn("AgentSwitchBoard-Live", next_action)
        self.assertIn("USERPROFILE", next_action)
        self.assertIn("Invoke-Asq005FreshTuiCertificationPrep.ps1", next_action)
        self.assertIn("Open-AgentSwitchboard-OpenCode-Lsp.cmd", next_action)
        self.assertIn("test_technician_live_cert_surface.py", next_action)
        self.assertIn("read_text", next_action)
        self.assertIn("24cce9e321a4913dda32f21a2d51a599dd0e4bb4", next_action)
        self.assertIn("20260912T194619Z-e3f423df", next_action)
        self.assertIn("G0", block)
        self.assertIn("G8", block)
        self.assertIn("LIVE_RUNTIME_PROOF:UNPROVEN", block)
        self.assertIn("WINDOWS_REQUIRED", block)
        self.assertIn("LIVE_ATTEMPT", block)
        self.assertIn("asq005-fresh-tui-lsp-runtime-gates.md", block)
        self.assertIn("Configure-only proof is insufficient", block)
        self.assertIn("1e5c599", block)
        self.assertIn("pr:#170", block.lower())
        self.assertIn("3c31d2c", block)
        self.assertIn("pr:#173", block.lower())

    def test_adapter_lanes_are_frozen_by_firstmate_boundary(self) -> None:
        text = WORK_QUEUE.read_text(encoding="utf-8")
        asq5 = _section(text, "## ASQ-005")
        asq8 = _section(text, "## ASQ-008")
        asq9 = _section(text, "## ASQ-009")
        self.assertIn("FirstMate FREEZE/HAND-OFF", asq5)
        self.assertIn("ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME", asq8)
        self.assertIn("ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME", asq9)
        self.assertRegex(asq8, r"- \*\*Dependencies:\*\* ASQ-014")
        self.assertRegex(asq9, r"- \*\*Dependencies:\*\* ASQ-014")
        self.assertIn("FREEZE", asq8)
        self.assertIn("FREEZE", asq9)

    def test_runtime_doc_names_canonical_live_floor(self) -> None:
        doc = RUNTIME_DOC.read_text(encoding="utf-8")
        self.assertIn("ASQ-005 fresh-TUI certification floor", doc)
        self.assertIn(r"%USERPROFILE%\dev\AgentSwitchBoard-Live", doc)
        self.assertIn("Invoke-Asq005FreshTuiCertificationPrep.ps1", doc)
        self.assertIn("asq005-fresh-tui-lsp-runtime-gates.md", doc)
        self.assertIn("G1 only", doc)
        self.assertIn("20260912T194619Z-e3f423df", doc)
        self.assertIn("test_technician_live_cert_surface.py", doc)
        self.assertIn("read_text", doc)
        self.assertNotRegex(doc, re.compile(r"OneDrive\s*-\s*Northwell", re.I))

    def test_g0_g8_gate_contract_and_doc(self) -> None:
        self.assertTrue(GATES_DOC.is_file(), GATES_DOC)
        self.assertTrue(GATES_CONTRACT.is_file(), GATES_CONTRACT)
        prep = (
            ROOT
            / "tooling"
            / "harness"
            / "operational"
            / "opencode-lsp-setup"
            / "Invoke-Asq005FreshTuiCertificationPrep.ps1"
        )
        self.assertTrue(prep.is_file(), prep)
        doc = GATES_DOC.read_text(encoding="utf-8")
        for gate_id in _GATE_IDS:
            self.assertIn(gate_id, doc)
        self.assertIn("Configure", doc)
        self.assertIn("LSP_RUNTIME_SMOKE_TEST: PASS", doc)
        self.assertIn("FREEZE", doc)
        self.assertIn("never counts as ASQ-005 DONE", doc)
        self.assertIn("Invoke-Asq005FreshTuiCertificationPrep.ps1", doc)
        self.assertIn("LIVE_RUNTIME_PROOF", doc)
        self.assertIn("UNPROVEN", doc)
        contract = json.loads(GATES_CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(contract["schema"], "agentswitchboard.asq005-runtime-gates.v1")
        self.assertEqual(contract["liveProofStatus"], "UNPROVEN")
        self.assertTrue(contract["configureNeverPromotesToDone"])
        self.assertEqual(contract["runtimeOwner"], "Admin Box 1")
        self.assertEqual(contract["headlessBaselineId"], "20260912T194619Z-e3f423df")
        self.assertEqual(contract["fixture"]["path"], "tests/test_technician_live_cert_surface.py")
        self.assertEqual(contract["fixture"]["symbol"], "read_text")
        self.assertEqual([g["id"] for g in contract["gates"]], list(_GATE_IDS))
        self.assertEqual(contract["doneRequiresGateIds"], list(_GATE_IDS))
        self.assertEqual(
            contract["prepEntrypoint"],
            "tooling/harness/operational/opencode-lsp-setup/Invoke-Asq005FreshTuiCertificationPrep.ps1",
        )
        g1 = next(g for g in contract["gates"] if g["id"] == "G1")
        self.assertTrue(g1.get("notSufficientForDone"))
        g8 = next(g for g in contract["gates"] if g["id"] == "G8")
        self.assertTrue(g8.get("doneRequiresLivePassVerdict"))
        prep_text = prep.read_text(encoding="utf-8")
        self.assertIn("Get-NormalizedOrigin", prep_text)
        self.assertIn("Get-NormalizedLocalPath", prep_text)
        self.assertIn("ToLowerInvariant", prep_text)
        self.assertIn("-replace '/', '\\'", prep_text)
        self.assertIn("NOT_ON_MAIN", prep_text)
        self.assertIn("ASQ005_LIVE_PROOF_STATUS", prep_text)
        self.assertIn("WINDOWS_REQUIRED", prep_text)
        self.assertIn("never ASQ-005 DONE", prep_text)
        self.assertIn(
            "(Get-NormalizedLocalPath -PathValue $root) -ne (Get-NormalizedLocalPath -PathValue $RepoPath)",
            prep_text,
        )
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(
            manifest["entrypoints"]["asq005RuntimeGatesContract"],
            "tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json",
        )
        self.assertEqual(
            manifest["entrypoints"]["asq005RuntimeGatesDoc"],
            "docs/harness/asq005-fresh-tui-lsp-runtime-gates.md",
        )
        self.assertEqual(
            manifest["entrypoints"]["asq005FreshTuiCertificationPrep"],
            "tooling/harness/operational/opencode-lsp-setup/Invoke-Asq005FreshTuiCertificationPrep.ps1",
        )

    def test_september_plan_handoff_uses_canonical_live_only(self) -> None:
        plan = json.loads(SEPTEMBER_PLAN.read_text(encoding="utf-8"))
        handoff = plan["handoff"]
        next_command = handoff["nextCommand"]
        lowered = next_command.lower()
        for forbidden in _PRIVATE_PATH_MARKERS:
            self.assertNotIn(forbidden, lowered, next_command)
        self.assertIn("AgentSwitchBoard-Live", next_command)
        self.assertIn("USERPROFILE", next_command)
        self.assertIn("Invoke-Asq005FreshTuiCertificationPrep.ps1", next_command)
        self.assertIn("24cce9e321a4913dda32f21a2d51a599dd0e4bb4", next_command)
        self.assertIn("Admin Box 1", handoff["nextOwner"])
        self.assertTrue(any("FREEZE" in n for n in handoff.get("notes") or []))
        lsp02 = next(t for t in plan["tasks"] if t["taskId"] == "LSP-02")
        evidence = " ".join(lsp02.get("evidence") or [])
        criteria = " ".join(lsp02.get("acceptanceCriteria") or [])
        self.assertIn("UNPROVEN", evidence)
        self.assertIn("24cce9e", evidence)
        self.assertIn("1e5c599", evidence)
        self.assertIn("G0", criteria)
        self.assertIn("G8", criteria)
        self.assertIn("test_technician_live_cert_surface.py", criteria)
        self.assertIn("read_text", criteria)
        self.assertIn("never promote", criteria.lower())
        self.assertIn("Invoke-Asq005FreshTuiCertificationPrep.ps1", " ".join(lsp02.get("inputs") or []))


if __name__ == "__main__":
    unittest.main()
