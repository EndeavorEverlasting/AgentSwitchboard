from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tooling" / "firstmate" / "Test-FirstMateInterop.sh"
ONE_SHOT = ROOT / "Invoke-FmWsl12AdminBoxLiveProof.ps1"
ASQ017 = ROOT / "Invoke-Asq017AdminBoxLiveFloor.ps1"


class FirstMateRecoveryRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.probe = PROBE.read_text(encoding="utf-8")
        cls.one_shot = ONE_SHOT.read_text(encoding="utf-8")
        cls.asq017 = ASQ017.read_text(encoding="utf-8")

    def test_probe_distinguishes_object_damage_from_contract_mismatch(self) -> None:
        self.assertIn('git -C "$FIRSTMATE_DIR" fsck --no-dangling "$EXPECTED_HEAD"', self.probe)
        self.assertIn("repair local FirstMate Git objects", self.probe)
        self.assertIn("tooling/firstmate/harness/integration-contract.json", self.probe)
        self.assertIn("tooling/firstmate/harness/upstream-pin.json", self.probe)
        self.assertIn("do not retry the same SHA checkout", self.probe)

    def test_one_shot_exit50_fallback_does_not_prescribe_same_sha_loop(self) -> None:
        marker = "elseif ($continue.ExitCode -eq 50)"
        start = self.one_shot.index(marker)
        end = self.one_shot.index("} else {", start)
        block = self.one_shot[start:end]
        self.assertIn("integration-contract.json", block)
        self.assertIn("upstream-pin.json", block)
        self.assertIn("do not retry the same SHA blindly", block)
        self.assertNotIn("git checkout b182d0f", block)

    def test_asq017_exit50_routes_to_child_or_contract_owner(self) -> None:
        marker = "if ($childExit -eq 50)"
        start = self.asq017.index(marker)
        end = self.asq017.index("if ($childExit -ne 0)", start)
        block = self.asq017[start:end]
        self.assertIn("follow the child NEXT= recovery above", block)
        self.assertIn("integration-contract.json", block)
        self.assertIn("upstream-pin.json", block)
        self.assertIn("do not retry the same SHA blindly", block)
        self.assertNotIn("git checkout b182d0f", block)


if __name__ == "__main__":
    unittest.main()
