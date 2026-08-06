from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "tooling" / "profiles" / "windows" / "harness" / "technician-ready" / "bootstrap-order.contract.json"
ENGINE = ROOT / "tooling" / "profiles" / "windows" / "Invoke-TechnicianAgentSwitchboardReady.ps1"
DOC = ROOT / "docs" / "harness" / "technician-bootstrap-order.md"
CMD = ROOT / "Test-TechnicianBootstrapOrder.cmd"
PS_VALIDATOR = ROOT / "scripts" / "Test-TechnicianBootstrapOrder.ps1"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class TestTechnicianBootstrapOrder(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads(read(CONTRACT))
        self.engine = read(ENGINE)

    def test_owned_files_exist(self) -> None:
        for path in (CONTRACT, ENGINE, DOC, CMD, PS_VALIDATOR):
            self.assertTrue(path.is_file(), f"missing owned file: {path}")

    def test_contract_identity_and_proof_ceiling(self) -> None:
        self.assertEqual(self.contract["schemaVersion"], 1)
        self.assertEqual(
            self.contract["contractId"],
            "agentswitchboard.technician-bootstrap-order.v1",
        )
        self.assertEqual(
            self.contract["owner"],
            "tooling/profiles/windows/Invoke-TechnicianAgentSwitchboardReady.ps1",
        )
        self.assertFalse(self.contract["generatedEvidence"]["tracked"])
        self.assertIn("Static repository ordering", self.contract["proofCeiling"])
        self.assertIn("No package installation", self.contract["proofCeiling"])

    def test_all_order_tokens_are_unique_and_present(self) -> None:
        ids: set[str] = set()
        tokens: set[str] = set()
        for gate in self.contract["orderedGates"]:
            gate_id = gate["id"]
            token = gate["token"]
            self.assertNotIn(gate_id, ids, f"duplicate gate id: {gate_id}")
            self.assertNotIn(token, tokens, f"duplicate gate token: {token}")
            ids.add(gate_id)
            tokens.add(token)
            self.assertEqual(
                self.engine.count(token),
                1,
                f"expected exactly one bootstrap token for {gate_id}: {token}",
            )

    def test_canonical_gate_sequence_is_monotonic(self) -> None:
        positions = []
        for gate in self.contract["orderedGates"]:
            positions.append((gate["id"], self.engine.index(gate["token"])))

        for (left_id, left_pos), (right_id, right_pos) in zip(positions, positions[1:]):
            self.assertLess(
                left_pos,
                right_pos,
                f"bootstrap order regressed: {left_id} must precede {right_id}",
            )

    def test_required_relations_are_enforced(self) -> None:
        positions = {
            gate["id"]: self.engine.index(gate["token"])
            for gate in self.contract["orderedGates"]
        }
        for relation in self.contract["requiredRelations"]:
            before = relation["before"]
            after = relation["after"]
            self.assertIn(before, positions)
            self.assertIn(after, positions)
            self.assertLess(
                positions[before],
                positions[after],
                f"required relation violated: {before} -> {after}",
            )

    def test_tmux_is_proven_before_higher_runtime_setup(self) -> None:
        tmux_probe = self.engine.index("tmux -V")
        for higher_runtime_token in (
            "if ! command -v agy >/dev/null 2>&1; then",
            "if ! command -v opencode >/dev/null 2>&1; then",
            "'-File', $gnhfSetup",
            "-Operation Launch",
        ):
            self.assertLess(tmux_probe, self.engine.index(higher_runtime_token))

    def test_wezterm_is_proven_before_wsl_tmux_setup(self) -> None:
        self.assertLess(
            self.engine.index("Add-Step -Name 'wezterm' -Status 'passed'"),
            self.engine.index("$linuxSetup = @'"),
        )

    def test_operator_contract_is_documented(self) -> None:
        text = read(DOC)
        for token in (
            "WezTerm → WSL/Ubuntu → tmux",
            "agent CLIs",
            "GNHF fleet",
            "Windows Profile launcher",
            "does not prove",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
