# tests/test_technician_live_cert_surface.py
# Structural/runtime-contract tests for Technician Clickable Live-Cert Surface.

import hashlib
import json
import os
import re
import subprocess
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_DIR = os.path.join(REPO_ROOT, "tooling", "profiles", "windows", "technician-live-cert")
MANIFEST_PATH = os.path.join(BASE_DIR, "technician-live-cert.manifest.json")
SCHEMAS_DIR = os.path.join(BASE_DIR, "schemas")
STAGE_DISPATCHER_PATH = os.path.join(BASE_DIR, "Invoke-TechnicianLiveCertStage.ps1")
REPAIR_DISPATCHER_PATH = os.path.join(BASE_DIR, "Invoke-TechnicianRepair.ps1")
COMMON_MODULE_PATH = os.path.join(BASE_DIR, "TechnicianLiveCert.Common.psm1")
BOOTSTRAP_PATH = os.path.join(REPO_ROOT, "AgentSwitchboard-Technician-Bootstrap.cmd")
PARENT_BOOTSTRAP_PATH = os.path.join(REPO_ROOT, "Pull-Repo-And-Setup-AgentSwitchboard.cmd")
WSL_REPAIR_PATH = os.path.join(BASE_DIR, "stages", "Repair-Technician-WSL-Ubuntu.ps1")


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


class TestTechnicianLiveCertSurface(unittest.TestCase):

    def setUp(self):
        self.assertTrue(os.path.exists(MANIFEST_PATH), f"Manifest missing at {MANIFEST_PATH}")
        with open(MANIFEST_PATH, "r", encoding="utf-8") as handle:
            self.manifest = json.load(handle)

    def test_manifest_structure_and_sequence(self):
        self.assertEqual("agentswitchboard.technician-live-cert-manifest.v1", self.manifest["schema"])
        self.assertEqual(1, self.manifest["manifestVersion"])
        self.assertEqual(
            ["P00", "P01", "P02", "P03", "P04", "P05", "P06", "P07", "P08"],
            self.manifest["coreSequence"],
        )
        for field in ["stages", "coreSequence", "repairs", "fullRunCmd", "bootstrapCmd"]:
            self.assertIn(field, self.manifest, f"Missing required manifest field: {field}")

    def test_stages_and_cmd_wiring(self):
        stages = {stage["stageId"]: stage for stage in self.manifest["stages"]}
        self.assertEqual(set(self.manifest["coreSequence"] + ["P09"]), set(stages))
        for stage_id, stage in stages.items():
            self.assertTrue(os.path.isfile(os.path.join(REPO_ROOT, stage["cmd"])), stage_id)
            self.assertTrue(os.path.isfile(os.path.join(BASE_DIR, stage["implementation"])), stage_id)
            if stage["manualObservationRequired"]:
                self.assertTrue(stage.get("manualObservationPrompt"), f"{stage_id} lacks fixed observation prompt")

    def test_dependencies_reference_real_stages_and_are_acyclic(self):
        stages = {stage["stageId"]: stage for stage in self.manifest["stages"]}
        for stage in stages.values():
            for dependency in stage.get("dependencies", []):
                self.assertIn(dependency, stages)
                self.assertNotEqual(stage["stageId"], dependency)

        visiting: set[str] = set()
        visited: set[str] = set()

        def visit(stage_id: str) -> None:
            if stage_id in visiting:
                self.fail(f"Dependency cycle includes {stage_id}")
            if stage_id in visited:
                return
            visiting.add(stage_id)
            for dependency in stages[stage_id].get("dependencies", []):
                visit(dependency)
            visiting.remove(stage_id)
            visited.add(stage_id)

        for stage_id in stages:
            visit(stage_id)

    def test_repair_mapping(self):
        stage_ids = {stage["stageId"] for stage in self.manifest["stages"]}
        for repair in self.manifest["repairs"]:
            self.assertTrue(os.path.isfile(os.path.join(REPO_ROOT, repair["cmd"])))
            self.assertTrue(os.path.isfile(os.path.join(BASE_DIR, repair["implementation"])))
            self.assertTrue(repair["targetsStages"])
            for target in repair["targetsStages"]:
                self.assertIn(target, stage_ids)

    def test_hermes_is_optional_outside_core_and_can_bind_completed_run(self):
        stages = {stage["stageId"]: stage for stage in self.manifest["stages"]}
        self.assertTrue(stages["P09"]["optional"])
        self.assertEqual(["P08"], stages["P09"]["dependencies"])
        self.assertNotIn("P09", self.manifest["coreSequence"])

        dispatcher = read_text(STAGE_DISPATCHER_PATH)
        common = read_text(COMMON_MODULE_PATH)
        self.assertIn("$StageId -eq 'P09'", dispatcher)
        self.assertIn("Get-LatestCompletedTechnicianLiveCertRunId", dispatcher)
        self.assertIn("No completed P00-P08 live-cert run exists for optional P09", dispatcher)
        self.assertIn("function Get-LatestCompletedTechnicianLiveCertRunId", common)
        self.assertIn("$run.stages.P08.status -eq 'passed'", common)

    def test_schema_and_report_files_exist(self):
        for schema_name in [
            "technician-live-cert-manifest.schema.json",
            "technician-live-cert-run.schema.json",
            "technician-live-cert-stage-result.schema.json",
        ]:
            schema_path = os.path.join(SCHEMAS_DIR, schema_name)
            self.assertTrue(os.path.isfile(schema_path), schema_name)
            json.loads(read_text(schema_path))
        self.assertTrue(os.path.isfile(os.path.join(BASE_DIR, "templates", "technician-live-cert-report.template.md")))

    def test_direct_stage_click_uses_active_run_continuity(self):
        dispatcher = read_text(STAGE_DISPATCHER_PATH)
        self.assertIn("if ($StageId -eq 'P00')", dispatcher)
        self.assertIn("New-TechnicianLiveCertRunContext -RepoRoot $RepoRoot", dispatcher)
        self.assertIn("Get-TechnicianLiveCertActiveRunId", dispatcher)
        self.assertIn("No active live-cert run exists", dispatcher)

        common = read_text(COMMON_MODULE_PATH)
        for token in [
            "active-run.json",
            "Set-TechnicianLiveCertActiveRun",
            "Get-TechnicianLiveCertActiveRunId",
            "Clear-TechnicianLiveCertActiveRun",
        ]:
            self.assertIn(token, common)

    def test_same_user_elevation_and_reboot_boundary_are_enforced(self):
        dispatcher = read_text(STAGE_DISPATCHER_PATH)
        for token in ["$OriginSid", "-Verb RunAs", "Same-user elevation failed", "runContext.accountSid"]:
            self.assertIn(token, dispatcher)

        repair_dispatcher = read_text(REPAIR_DISPATCHER_PATH)
        for token in [
            "$OriginSid",
            "-Verb RunAs",
            "Same-user elevation failed",
            "$exitCode -eq 3010",
            "required Windows reboot boundary",
        ]:
            self.assertIn(token, repair_dispatcher)

    def test_no_unsupported_import_module_literal_path(self):
        offenders = []
        for root, _, files in os.walk(BASE_DIR):
            for filename in files:
                if not filename.lower().endswith((".ps1", ".psm1")):
                    continue
                path = os.path.join(root, filename)
                if "Import-Module -LiteralPath" in read_text(path):
                    offenders.append(os.path.relpath(path, REPO_ROOT))
        self.assertEqual([], offenders)

    def test_dispatcher_success_rendering_is_not_executable_if_expression(self):
        dispatcher = read_text(STAGE_DISPATCHER_PATH)
        self.assertNotIn("-ForegroundColor (if", dispatcher)
        self.assertIn("$statusColor = if ($stageStatus -eq 'passed')", dispatcher)
        self.assertIn("-ForegroundColor $statusColor", dispatcher)

    def test_p00_requires_real_workstation_prerequisites(self):
        p00 = read_text(os.path.join(BASE_DIR, "stages", "P00-Preflight.ps1"))
        for token in ["wsl.exe", "'Ubuntu'", "evidenceWritable", "accountSid", "TECHNICIAN_LIVE_CERT_CI_SURFACE"]:
            self.assertIn(token, p00)
        self.assertIn("Repair-Technician-WSL-Ubuntu.cmd", p00)

    def test_wsl_repair_is_first_machine_capable_and_does_not_loop(self):
        repair = read_text(WSL_REPAIR_PATH)
        for token in [
            "Microsoft-Windows-Subsystem-Linux",
            "VirtualMachinePlatform",
            "dism.exe",
            "/NoRestart",
            "RunOnce",
            "AgentSwitchBoardWslUbuntuRepair",
            "return 3010",
            "'--web-download'",
            "'--no-launch'",
            "'--set-default-version'",
            "'--set-version'",
            "one-time post-reboot continuation",
            "first-run initialization",
            "do not invent a password",
        ]:
            self.assertIn(token, repair)
        self.assertNotIn("Ubuntu is not yet available after 'wsl --install -d Ubuntu'", repair)
        self.assertIn("if ($continuingAfterReboot)", repair)
        self.assertIn("fail closed instead of creating a reboot loop", repair)

    def test_p03_executes_exact_four_version_probes_in_child_powershell(self):
        p03 = read_text(os.path.join(BASE_DIR, "stages", "P03-Verify-Commands.ps1"))
        for command_name in ["'wezterm'", "'tmux'", "'agy'", "'opencode'"]:
            self.assertIn(command_name, p03)
        self.assertIn("$CommandName -eq 'tmux'", p03)
        self.assertIn("'-V'", p03)
        self.assertIn("'--version'", p03)
        self.assertIn("pwsh.exe", p03)
        self.assertIn("throw \"P03 command verification failed", p03)
        self.assertNotIn("'wsl'; Args", p03)

    def test_launch_stages_cannot_warn_and_false_pass(self):
        for stage_name in ["P04-Launch-Shell.ps1", "P05-Launch-AGY.ps1", "P06-Launch-OpenCode.ps1"]:
            text = read_text(os.path.join(BASE_DIR, "stages", stage_name))
            self.assertIn("$proc.ExitCode -ne 0", text, stage_name)
            self.assertIn("throw", text, stage_name)
            self.assertNotIn("Write-Warning \"Launch", text, stage_name)

    def test_p07_proves_repeatability_instead_of_single_launch(self):
        p07 = read_text(os.path.join(BASE_DIR, "stages", "P07-Repeatability.ps1"))
        self.assertIn("@('setup', 'shell', 'shell', 'agy', 'opencode')", p07)
        for token in ["devSessionCount", "agyWindowCount", "openCodeWindowCount", "repositoryClean", "weztermConfigHashBefore", "tmuxConfigHashBefore"]:
            self.assertIn(token, p07)
        self.assertIn("throw", p07)

    def test_p08_refuses_to_finalize_incomplete_core(self):
        p08 = read_text(os.path.join(BASE_DIR, "stages", "P08-Finalize.ps1"))
        self.assertIn("$requiredPredecessors", p08)
        self.assertIn("P08 cannot finalize", p08)
        self.assertIn("technician-live-cert-stage-matrix.csv", p08)

    def test_command_shim_repair_reuses_canonical_setup(self):
        repair = read_text(os.path.join(BASE_DIR, "stages", "Repair-Technician-Command-Shims.ps1"))
        self.assertIn("Setup-TechnicianAgentSwitchboard.ps1", repair)
        for command_name in ["'wezterm'", "'tmux'", "'agy'", "'opencode'"]:
            self.assertIn(command_name, repair)
        self.assertNotIn("wsl.exe -d Ubuntu -- bash -lc", repair)

    def test_bootstrap_is_single_file_capable_and_parent_hash_is_pinned(self):
        bootstrap = read_text(BOOTSTRAP_PATH)
        parent = read_text(PARENT_BOOTSTRAP_PATH)
        self.assertIn('set "BRANCH=main"', bootstrap)
        self.assertIn('set "BRANCH=main"', parent)
        self.assertIn("curl.exe -fL \"%PARENT_URL%\"", bootstrap)
        self.assertIn("Get-FileHash -Algorithm SHA256", bootstrap)
        self.assertIn("Run-Technician-LiveCert.cmd", bootstrap)
        match = re.search(r'EXPECTED_PARENT_SHA256=([a-f0-9]{64})', bootstrap, flags=re.IGNORECASE)
        self.assertIsNotNone(match, "Bootstrap must pin a 64-character parent SHA-256")
        parent_blob = subprocess.check_output(
            ["git", "show", "HEAD:Pull-Repo-And-Setup-AgentSwitchboard.cmd"],
            cwd=REPO_ROOT,
        )
        self.assertEqual(hashlib.sha256(parent_blob).hexdigest(), match.group(1).lower())


if __name__ == "__main__":
    unittest.main()
