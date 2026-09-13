"""Fail closed if ASQ-005 is routed to a noncanonical or private checkout path."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK_QUEUE = ROOT / ".ai" / "WORK_QUEUE.md"
RUNTIME_DOC = ROOT / "docs" / "harness" / "opencode-lsp-workstation-setup.md"


def _section(text: str, heading: str, next_heading_prefix: str = "## ASQ-") -> str:
    start = text.find(heading)
    if start < 0:
        raise AssertionError(f"missing heading: {heading}")
    rest = text[start + len(heading) :]
    end = rest.find(next_heading_prefix)
    return rest if end < 0 else rest[:end]


class Asq005CanonicalRuntimeFloorTests(unittest.TestCase):
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
        for forbidden in ("onedrive", "northwell", "desktop\\dev", "og laptop backup"):
            self.assertNotIn(forbidden, lowered, next_action)
        self.assertIn("AgentSwitchBoard-Live", next_action)
        self.assertIn("USERPROFILE", next_action)
        self.assertIn("Invoke-OpenCodeLspWorkstationSetup.ps1", next_action)
        self.assertIn("Configure", next_action)
        self.assertIn("OPENCODE_EXPERIMENTAL_LSP_TOOL", next_action)
        self.assertIn("Open-AgentSwitchboard-OpenCode-Lsp.cmd", next_action)
        self.assertIn("test_technician_live_cert_surface.py", next_action)
        self.assertIn("read_text", next_action)

    def test_adapter_lanes_are_frozen_by_firstmate_boundary(self) -> None:
        """ASQ-008/009 no longer wait on ASQ-005 adapter expansion; FirstMate ADR freezes them."""
        text = WORK_QUEUE.read_text(encoding="utf-8")
        asq8 = _section(text, "## ASQ-008")
        asq9 = _section(text, "## ASQ-009")
        self.assertIn("ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME", asq8)
        self.assertIn("ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME", asq9)
        self.assertRegex(asq8, r"- \*\*Dependencies:\*\* ASQ-014")
        self.assertRegex(asq9, r"- \*\*Dependencies:\*\* ASQ-014")
        self.assertIn("FREEZE", asq8)
        self.assertIn("FREEZE", asq9)
        self.assertIn("FirstMate", asq8)
        self.assertIn("FirstMate", asq9)

    def test_runtime_doc_names_canonical_live_floor(self) -> None:
        doc = RUNTIME_DOC.read_text(encoding="utf-8")
        self.assertIn("ASQ-005 fresh-TUI certification floor", doc)
        self.assertIn(r"%USERPROFILE%\dev\AgentSwitchBoard-Live", doc)
        self.assertIn("Invoke-OpenCodeLspWorkstationSetup.ps1", doc)
        self.assertNotRegex(doc, re.compile(r"OneDrive - Northwell", re.I))


if __name__ == "__main__":
    unittest.main()
