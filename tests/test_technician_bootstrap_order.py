from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "tooling" / "profiles" / "windows" / "harness" / "technician-ready" / "bootstrap-order.contract.json"
BOOTSTRAP = ROOT / "tooling" / "profiles" / "windows" / "Invoke-TechnicianBootstrapPrerequisites.ps1"
ENGINE = ROOT / "tooling" / "profiles" / "windows" / "Invoke-TechnicianAgentSwitchboardReady.ps1"
FRONT_DOOR = ROOT / "Technician-AgentSwitchboard-Ready.cmd"
DOC = ROOT / "docs" / "harness" / "technician-bootstrap-order.md"
CMD = ROOT / "Test-TechnicianBootstrapOrder.cmd"
PS_VALIDATOR = ROOT / "scripts" / "Test-TechnicianBootstrapOrder.ps1"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def assert_ordered_unique(test: unittest.TestCase, text: str, gates: list[dict[str, str]], label: str) -> None:
    ids: set[str] = set()
    tokens: set[str] = set()
    positions: list[tuple[str, int]] = []
    for gate in gates:
        gate_id = gate["id"]
        token = gate["token"]
        test.assertNotIn(gate_id, ids, f"duplicate {label} gate id: {gate_id}")
        test.assertNotIn(token, tokens, f"duplicate {label} token: {token}")
        ids.add(gate_id)
        tokens.add(token)
        test.assertEqual(text.count(token), 1, f"expected one {label} token for {gate_id}: {token}")
        positions.append((gate_id, text.index(token)))

    for (left_id, left_pos), (right_id, right_pos) in zip(positions, positions[1:]):
        test.assertLess(left_pos, right_pos, f"{label} order regressed: {left_id} must precede {right_id}")


class TestTechnicianBootstrapOrder(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads(read(CONTRACT))
        self.bootstrap = read(BOOTSTRAP)
        self.engine = read(ENGINE)
        self.front_door = read(FRONT_DOOR)

    def test_owned_files_exist(self) -> None:
        for path in (CONTRACT, BOOTSTRAP, ENGINE, FRONT_DOOR, DOC, CMD, PS_VALIDATOR):
            self.assertTrue(path.is_file(), f"missing owned file: {path}")

    def test_contract_identity_and_owners(self) -> None:
        self.assertEqual(self.contract["schemaVersion"], 2)
        self.assertEqual(self.contract["contractId"], "agentswitchboard.technician-bootstrap-order.v2")
        self.assertEqual(self.contract["frontDoor"], "Technician-AgentSwitchboard-Ready.cmd")
        self.assertEqual(
            self.contract["bootstrapOwner"],
            "tooling/profiles/windows/Invoke-TechnicianBootstrapPrerequisites.ps1",
        )
        self.assertEqual(
            self.contract["runtimeOwner"],
            "tooling/profiles/windows/Invoke-TechnicianAgentSwitchboardReady.ps1",
        )
        self.assertFalse(self.contract["generatedEvidence"]["tracked"])

    def test_bootstrap_gate_sequence_is_monotonic(self) -> None:
        assert_ordered_unique(self, self.bootstrap, self.contract["bootstrapGates"], "bootstrap")

    def test_front_door_blocks_runtime_until_bootstrap_passes(self) -> None:
        assert_ordered_unique(self, self.front_door, self.contract["frontDoorGates"], "front-door")
        self.assertIn('set "RESULT=%ERRORLEVEL%"', self.front_door)
        self.assertIn('if not "%RESULT%"=="0" goto :finish', self.front_door)

    def test_higher_runtime_setup_is_owned_by_engine_only(self) -> None:
        for token in self.contract["higherRuntimeTokens"]:
            self.assertIn(token, self.engine, f"runtime owner is missing: {token}")
            self.assertNotIn(token, self.bootstrap, f"prerequisite gate must not own higher runtime setup: {token}")

    def test_wezterm_precedes_tmux(self) -> None:
        self.assertLess(
            self.bootstrap.index("$wezTermVersion = Invoke-BoundedProcess"),
            self.bootstrap.index("if ! command -v tmux >/dev/null 2>&1; then"),
        )
        self.assertLess(
            self.bootstrap.index("if ! command -v tmux >/dev/null 2>&1; then"),
            self.bootstrap.index("tmux -V"),
        )

    def test_bootstrap_is_bounded_and_non_destructive(self) -> None:
        for forbidden in ("git reset", "git clean", "git stash", "push --force", "agy", "opencode", "$gnhfSetup", "-Operation Launch"):
            self.assertNotIn(forbidden, self.bootstrap)
        self.assertIn("ProcessTimeoutSeconds 300", self.bootstrap)
        self.assertIn("tmux prerequisite setup failed", self.bootstrap)

    def test_operator_contract_is_documented(self) -> None:
        text = read(DOC)
        for token in (
            "WezTerm → WSL/Ubuntu → tmux",
            "prerequisite gate",
            "AgentSwitchboard readiness engine",
            "does not prove",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
