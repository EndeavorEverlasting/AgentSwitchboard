import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json"
SKILL = ROOT / ".ai/skills/launch-order-guard/SKILL.md"
FRONTIER = ROOT / "scripts/Get-RepositoryWorkLedgerFrontier.ps1"
WORK_QUEUE = ROOT / ".ai/WORK_QUEUE.md"

class P13RecurrenceGuardTests(unittest.TestCase):
    def test_skill_exists_and_names_critical_path(self):
        self.assertTrue(SKILL.is_file(), str(SKILL))
        text = SKILL.read_text(encoding="utf-8")
        self.assertIn("Get-RepositoryWorkLedgerFrontier", text)
        self.assertIn("PARALLEL EXECUTION", text)
        self.assertIn("R1", text)

    def test_plan_encodes_launch_order(self):
        self.assertTrue(PLAN.is_file(), str(PLAN))
        plan = json.loads(PLAN.read_text(encoding="utf-8"))
        tasks = {t["taskId"]: t for t in plan["tasks"]}
        self.assertIn("COORD-01", tasks)
        self.assertIn("PI-BOOT-03", tasks)
        self.assertIn("BUS-04", tasks)
        # WORK_QUEUE holds ASQ frontier, not plan
        self.assertTrue(WORK_QUEUE.is_file(), str(WORK_QUEUE))
        self.assertIn("ASQ-005", WORK_QUEUE.read_text(encoding="utf-8"))
        self.assertIn("ASQ-006", WORK_QUEUE.read_text(encoding="utf-8"))

    def test_frontier_script_exists(self):
        self.assertTrue(FRONTIER.is_file(), str(FRONTIER))

    def test_guard_requires_no_status_stall(self):
        text = SKILL.read_text(encoding="utf-8")
        self.assertIn("Execute one critical-path advancement before long report", text)
        self.assertIn("branch listing / PR status alone is not movement", text)

if __name__ == "__main__":
    unittest.main()