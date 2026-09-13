from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "tooling" / "harness" / "multi-product-bootstrap" / "product-matrix.contract.json"
PLAN = ROOT / "plans" / "active" / "ASB-2026-09-multi-product-bootstrap-charter.plan.json"
PLAN_MD = ROOT / "plans" / "active" / "ASB-2026-09-multi-product-bootstrap-charter.md"
DOCS = ROOT / "docs" / "harness" / "multi-product-bootstrap-charter.md"
REGISTRY = ROOT / "plans" / "plan-registry.json"
ADAPTERS = ROOT / "tooling" / "harness" / "system-bootstrap-lifecycle" / "adapters.v1.json"
PI_INSTALLER = ROOT / "tooling" / "pi" / "Install-AgentSwitchboardPiSystem.ps1"
UNBOOTSTRAP_PI = ROOT / "Unbootstrap-Pi-SystemWide.cmd"


class MultiProductBootstrapCharterTests(unittest.TestCase):
    def test_matrix_parses_and_products_present(self):
        matrix = json.loads(MATRIX.read_text(encoding="utf-8-sig"))
        self.assertEqual("agentswitchboard.multi-product-bootstrap-matrix.v1", matrix["schema"])
        self.assertEqual("ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS", matrix["dependsOnPlan"])
        products = matrix["products"]
        for product_id in ("opencode", "pi", "firstmate", "herdr"):
            self.assertIn(product_id, products)
            row = products[product_id]
            for field in (
                "status",
                "platform",
                "bootstrapOwner",
                "runtime",
                "proofCeiling",
                "nextAction",
            ):
                self.assertIn(field, row)
                self.assertTrue(str(row[field]).strip(), f"{product_id}.{field} must be non-empty")

    def test_herdr_deferred_and_firstmate_wsl(self):
        matrix = json.loads(MATRIX.read_text(encoding="utf-8-sig"))
        herdr = matrix["products"]["herdr"]
        firstmate = matrix["products"]["firstmate"]
        self.assertEqual("deferred", herdr["status"])
        self.assertIn("android", herdr["platform"].lower())
        self.assertIn("WSL", firstmate["runtime"])
        self.assertIn("bridge", firstmate["platform"].lower())
        self.assertIn("herdr", matrix["decisionFloor"]["deferred"])
        self.assertEqual("convergence-contract-on-main", firstmate["status"])
        self.assertEqual(
            "tooling/firstmate/harness/convergence-contract.json",
            firstmate["bootstrapOwner"],
        )
        self.assertTrue(
            (ROOT / "tooling/firstmate/harness/convergence-contract.json").is_file()
        )

    def test_pi_and_opencode_windows_native(self):
        matrix = json.loads(MATRIX.read_text(encoding="utf-8-sig"))
        self.assertEqual("windows-native", matrix["products"]["opencode"]["platform"])
        self.assertEqual("windows-native", matrix["products"]["pi"]["platform"])
        self.assertIn("windows-native", matrix["products"]["opencode"]["platform"])
        self.assertNotIn("Remove", matrix["products"]["pi"]["status"])
        self.assertIn("remove-gap", matrix["products"]["pi"]["status"])

    def test_plan_registered_and_depends_on_september_program(self):
        registry = json.loads(REGISTRY.read_text(encoding="utf-8-sig"))
        plan = json.loads(PLAN.read_text(encoding="utf-8-sig"))
        self.assertTrue(PLAN_MD.is_file())
        self.assertTrue(DOCS.is_file())
        self.assertEqual("agentswitchboard.public-plan.v1", plan["schema"])
        self.assertEqual("ASB-2026-09-MULTI-PRODUCT-BOOTSTRAP-CHARTER", plan["planId"])
        self.assertIn("ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS", plan["dependencies"])
        entries = {item["planId"]: item for item in registry["plans"]}
        self.assertIn("ASB-2026-09-MULTI-PRODUCT-BOOTSTRAP-CHARTER", entries)
        entry = entries["ASB-2026-09-MULTI-PRODUCT-BOOTSTRAP-CHARTER"]
        self.assertEqual(
            "plans/active/ASB-2026-09-multi-product-bootstrap-charter.plan.json",
            entry["path"],
        )
        self.assertIn("ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS", entry["dependencies"])
        task_ids = {task["taskId"] for task in plan["tasks"]}
        self.assertEqual(
            {"CHARTER-01", "PI-02", "FM-03", "HERDR-04", "HOOKS-05"},
            task_ids,
        )

    def test_pi_adapter_registered_without_claiming_remove(self):
        adapters = json.loads(ADAPTERS.read_text(encoding="utf-8-sig"))
        by_id = {item["adapterId"]: item for item in adapters["adapters"]}
        self.assertIn("opencode", by_id)
        self.assertIn("pi", by_id)
        pi = by_id["pi"]
        self.assertEqual("tooling/pi/Install-AgentSwitchboardPiSystem.ps1", pi["owner"])
        self.assertEqual(
            "tooling/pi/harness/system-bootstrap.contract.json",
            pi["adapterContract"],
        )
        self.assertEqual("Bootstrap-Pi-SystemWide.cmd", pi["bootstrapEntrypoint"])
        self.assertIsNone(pi["unbootstrapEntrypoint"])
        self.assertEqual(["Inspect", "Apply"], pi["operations"])
        self.assertNotIn("Remove", pi["operations"])
        self.assertFalse(UNBOOTSTRAP_PI.exists(), "Do not invent Unbootstrap-Pi-SystemWide.cmd in this sprint")
        installer = PI_INSTALLER.read_text(encoding="utf-8-sig")
        self.assertIn("[ValidateSet('Inspect','Apply')]", installer)
        self.assertNotIn("[ValidateSet('Inspect','Apply','Remove')]", installer)
        self.assertIn("extensionPoints", json.loads(MATRIX.read_text(encoding="utf-8-sig")))


if __name__ == "__main__":
    unittest.main()
