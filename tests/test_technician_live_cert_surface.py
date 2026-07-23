# tests/test_technician_live_cert_surface.py
# Structural tests for Technician Live-Cert Surface

import json
import os
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_DIR = os.path.join(REPO_ROOT, "tooling", "profiles", "windows", "technician-live-cert")
MANIFEST_PATH = os.path.join(BASE_DIR, "technician-live-cert.manifest.json")
SCHEMAS_DIR = os.path.join(BASE_DIR, "schemas")
STAGE_DISPATCHER_PATH = os.path.join(BASE_DIR, "Invoke-TechnicianLiveCertStage.ps1")


class TestTechnicianLiveCertSurface(unittest.TestCase):

    def setUp(self):
        self.assertTrue(os.path.exists(MANIFEST_PATH), f"Manifest missing at {MANIFEST_PATH}")
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            self.manifest = json.load(f)

    def test_manifest_structure(self):
        """Verify manifest contains required fields."""
        for field in ["stages", "coreSequence", "repairs", "fullRunCmd", "bootstrapCmd"]:
            self.assertIn(field, self.manifest, f"Missing required manifest field: {field}")

    def test_stages_and_cmd_wiring(self):
        """Verify every stage has a corresponding CMD wrapper and implementation script."""
        stages = {s["stageId"]: s for s in self.manifest["stages"]}
        self.assertIn("P00", stages)
        self.assertIn("P08", stages)

        for stage_id, stage in stages.items():
            cmd_path = os.path.join(REPO_ROOT, stage["cmd"])
            self.assertTrue(os.path.exists(cmd_path), f"CMD wrapper missing for stage {stage_id}: {stage['cmd']}")

            impl_path = os.path.join(BASE_DIR, stage["implementation"])
            self.assertTrue(os.path.exists(impl_path), f"Implementation missing for stage {stage_id}: {stage['implementation']}")

    def test_dependencies_graph(self):
        """Verify stage dependencies exist and form a DAG."""
        stage_ids = {s["stageId"] for s in self.manifest["stages"]}
        for stage in self.manifest["stages"]:
            for dep in stage.get("dependencies", []):
                self.assertIn(dep, stage_ids, f"Stage {stage['stageId']} references unknown dependency {dep}")
                self.assertNotEqual(stage["stageId"], dep, f"Self-dependency found in stage {stage['stageId']}")

    def test_repair_mapping(self):
        """Verify repairs target valid stage IDs and have implementation scripts."""
        stage_ids = {s["stageId"] for s in self.manifest["stages"]}
        for repair in self.manifest["repairs"]:
            repair_id = repair["repairId"]
            cmd_path = os.path.join(REPO_ROOT, repair["cmd"])
            self.assertTrue(os.path.exists(cmd_path), f"CMD wrapper missing for repair {repair_id}: {repair['cmd']}")

            impl_path = os.path.join(BASE_DIR, repair["implementation"])
            self.assertTrue(os.path.exists(impl_path), f"Implementation missing for repair {repair_id}: {repair['implementation']}")

            targets = repair.get("targetsStages") or repair.get("stageDependencies") or []
            for target in targets:
                self.assertIn(target, stage_ids, f"Repair {repair_id} targets unknown stage {target}")

    def test_hermes_optional(self):
        """Verify stage P09 Hermes Optional is configured as optional."""
        stages = {s["stageId"]: s for s in self.manifest["stages"]}
        self.assertIn("P09", stages)
        p09 = stages["P09"]
        self.assertTrue(p09.get("optional", False), "P09 must be marked optional: true")
        self.assertIn("P08", p09.get("dependencies", []), "P09 must depend on P08")

    def test_schemas_exist(self):
        """Verify schema files exist."""
        required_schemas = [
            "technician-live-cert-manifest.schema.json",
            "technician-live-cert-run.schema.json",
            "technician-live-cert-stage-result.schema.json",
        ]
        for schema_name in required_schemas:
            schema_path = os.path.join(SCHEMAS_DIR, schema_name)
            self.assertTrue(os.path.exists(schema_path), f"Schema missing: {schema_name}")

    def test_report_template_exists(self):
        """Verify report template exists."""
        template_path = os.path.join(BASE_DIR, "templates", "technician-live-cert-report.template.md")
        self.assertTrue(os.path.exists(template_path), "Report template missing")

    def test_direct_stage_click_can_create_run(self):
        """A directly clicked P00 must create a new run instead of requiring prior evidence."""
        with open(STAGE_DISPATCHER_PATH, "r", encoding="utf-8") as f:
            dispatcher = f.read()

        self.assertIn("[string]::IsNullOrWhiteSpace($RunId)", dispatcher)
        self.assertIn("New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot", dispatcher)
        self.assertLess(
            dispatcher.index("New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot"),
            dispatcher.index("Get-TechnicianLiveCertRunContext -RunId $RunId"),
            "Standalone stage bootstrap must create a run before attempting run lookup.",
        )

    def test_no_unsupported_import_module_literal_path(self):
        """Import-Module does not expose -LiteralPath; owned runtime scripts must use -Name for path imports."""
        offenders = []
        for root, _, files in os.walk(BASE_DIR):
            for filename in files:
                if not filename.lower().endswith((".ps1", ".psm1")):
                    continue
                path = os.path.join(root, filename)
                with open(path, "r", encoding="utf-8") as f:
                    if "Import-Module -LiteralPath" in f.read():
                        offenders.append(os.path.relpath(path, REPO_ROOT))

        self.assertEqual([], offenders, f"Unsupported Import-Module -LiteralPath found in: {offenders}")


if __name__ == "__main__":
    unittest.main()
