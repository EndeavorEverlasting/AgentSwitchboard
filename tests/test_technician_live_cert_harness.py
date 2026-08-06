# Dependency-free contracts for the scoped Technician Live-Cert harness.

import json
import os
import re
import unittest


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HARNESS_ROOT = os.path.join(
    REPO_ROOT, "tooling", "profiles", "windows", "harness", "technician-live-cert"
)
MANIFEST_PATH = os.path.join(HARNESS_ROOT, "manifest.json")
P00_PATH = os.path.join(
    REPO_ROOT,
    "tooling",
    "profiles",
    "windows",
    "technician-live-cert",
    "stages",
    "P00-Preflight.ps1",
)
SURFACE_VALIDATOR_PATH = os.path.join(
    REPO_ROOT, "scripts", "Test-TechnicianLiveCertSurface.ps1"
)
HARNESS_VALIDATOR_PATH = os.path.join(
    REPO_ROOT, "scripts", "Test-TechnicianLiveCertHarness.ps1"
)
OPERATOR_VALIDATOR_PATH = os.path.join(
    REPO_ROOT, "scripts", "Test-OperatorCommandEnvelope.ps1"
)
STATUS_REPORTER_PATH = os.path.join(
    REPO_ROOT,
    "tooling",
    "profiles",
    "windows",
    "Get-TechnicianLiveCertHarnessStatus.ps1",
)
HOOK_PATH = os.path.join(
    REPO_ROOT,
    "tooling",
    "profiles",
    "windows",
    "hooks",
    "Invoke-TechnicianLiveCertPreCommit.ps1",
)
CI_PATH = os.path.join(
    REPO_ROOT, ".github", "workflows", "technician-live-cert-surface.yml"
)
SKILL_PATH = os.path.join(
    REPO_ROOT, ".ai", "skills", "windows-profile-live-certification", "SKILL.md"
)
OPERATOR_SKILL_PATH = os.path.join(
    REPO_ROOT, ".ai", "skills", "operator-command-envelope", "SKILL.md"
)
GUIDE_PATH = os.path.join(
    REPO_ROOT, "docs", "harness", "technician-live-cert-harness.md"
)
OPERATOR_CONTRACT_PATH = os.path.join(
    HARNESS_ROOT, "operator-command-contract.json"
)
OPERATOR_FIXTURE_PATH = os.path.join(
    HARNESS_ROOT, "fixtures", "operator-command-contamination.fixture.json"
)
OPERATOR_REPORT_TEMPLATE_PATH = os.path.join(
    HARNESS_ROOT, "operator-command-report.template.md"
)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def read_json(path: str):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


class TestTechnicianLiveCertHarness(unittest.TestCase):

    def setUp(self):
        self.assertTrue(os.path.isfile(MANIFEST_PATH), MANIFEST_PATH)
        self.manifest = read_json(MANIFEST_PATH)

    def test_manifest_identity_and_safety_floor(self):
        self.assertEqual(1, self.manifest["schemaVersion"])
        self.assertEqual(
            "agentswitchboard.technician-live-cert-harness.v1",
            self.manifest["harnessId"],
        )
        self.assertEqual(
            "EndeavorEverlasting/AgentSwitchboard",
            self.manifest["canonicalOwner"],
        )
        self.assertFalse(self.manifest["generatedEvidence"]["tracked"])
        self.assertFalse(self.manifest["implicitHookInstallationAllowed"])
        self.assertFalse(self.manifest["networkAllowedByValidators"])
        self.assertFalse(self.manifest["targetMutationAllowedByValidators"])
        self.assertIn(
            "require the workstation live-cert sequence",
            self.manifest["proofCeiling"],
        )
        self.assertIn(
            "prompt-free operator-command contracts",
            self.manifest["proofCeiling"],
        )

    def test_all_registered_components_exist(self):
        components = self.manifest["components"]
        self.assertGreaterEqual(len(components), 32)
        ids = [component["id"] for component in components]
        self.assertEqual(len(ids), len(set(ids)))
        for component in components:
            path = os.path.join(REPO_ROOT, component["path"].replace("/", os.sep))
            self.assertTrue(os.path.isfile(path), component["path"])

    def test_scoped_json_contracts_parse(self):
        entrypoints = self.manifest["entrypoints"]
        for key in [
            "codebaseMap",
            "artifactRegistry",
            "maintenanceWorkflow",
            "fieldFailureRepairWorkflow",
            "schema",
            "operatorCommandContract",
            "operatorCommandFixture",
            "operatorCommandContractSchema",
            "operatorCommandFixtureSchema",
        ]:
            path = os.path.join(REPO_ROOT, entrypoints[key].replace("/", os.sep))
            parsed = read_json(path)
            self.assertIsInstance(parsed, dict, key)

    def test_codebase_map_covers_required_operator_surfaces(self):
        mapping = read_json(os.path.join(HARNESS_ROOT, "codebase-map.json"))
        for field in [
            "overview",
            "directories",
            "entrypoints",
            "configurationFiles",
            "commands",
            "knownTraps",
            "proofCeiling",
        ]:
            self.assertIn(field, mapping)
        commands = json.dumps(mapping["commands"])
        for token in [
            "tests.test_operator_command_envelope",
            "Test-OperatorCommandEnvelope.ps1",
            "tests.test_technician_live_cert_harness",
            "Test-TechnicianLiveCertSurface.ps1",
            "Test-TechnicianLiveCertHarness.ps1",
            "git --no-pager diff --check",
            "-CandidatePath",
        ]:
            self.assertIn(token, commands)
        traps = "\n".join(mapping["knownTraps"])
        self.assertIn("Get-Process alias", traps)
        self.assertIn("duplicated prompt", traps)
        self.assertIn("CategoryInfo", traps)
        self.assertIn("PSScriptRoot", traps)
        self.assertIn("string,string overload", traps)
        self.assertIn("interactive pager", traps)

    def test_workflows_cover_pickup_failure_validation_and_handoff(self):
        maintenance = read_json(
            os.path.join(HARNESS_ROOT, "workflows", "maintenance.workflow.json")
        )
        phase_ids = [phase["id"] for phase in maintenance["phases"]]
        self.assertEqual(
            ["intake", "factor", "implement", "validate", "handoff"], phase_ids
        )
        maintenance_text = json.dumps(maintenance)
        for token in [
            "Windows PowerShell 5.1",
            "PowerShell 7",
            "git --no-pager",
            "exact next command",
            "operator-command envelope",
            "candidate handoff artifact",
            "shell prompt",
        ]:
            self.assertIn(token, maintenance_text)

        repair = read_json(
            os.path.join(
                HARNESS_ROOT, "workflows", "field-failure-repair.workflow.json"
            )
        )
        step_ids = [step["id"] for step in repair["steps"]]
        self.assertEqual(
            [
                "preserve",
                "separate-command-from-transcript",
                "reproduce-contract",
                "repair",
                "cross-shell-validate",
                "exact-command-rerun",
                "converge",
            ],
            step_ids,
        )
        self.assertIn("prompt-free operator command", repair["proofCeiling"])

    def test_artifact_registry_keeps_generated_evidence_untracked(self):
        registry = read_json(os.path.join(HARNESS_ROOT, "artifact-registry.json"))
        self.assertGreaterEqual(len(registry["artifacts"]), 15)
        artifact_ids = {artifact["artifactId"] for artifact in registry["artifacts"]}
        self.assertIn("operator-command-envelope-json", artifact_ids)
        self.assertIn("operator-command-envelope-report", artifact_ids)
        for artifact in registry["artifacts"]:
            self.assertFalse(artifact["tracked"], artifact["artifactId"])
            self.assertEqual("local-operational", artifact["sensitivity"])
            self.assertTrue(artifact["generator"])
            self.assertTrue(artifact["proofCeiling"])

    def test_operator_command_contract_and_fixture_are_registered(self):
        contract = read_json(OPERATOR_CONTRACT_PATH)
        fixture = read_json(OPERATOR_FIXTURE_PATH)
        self.assertEqual(
            "agentswitchboard.operator-command-envelope.v1",
            contract["contractId"],
        )
        rule_ids = {rule["id"] for rule in contract["rules"]}
        for expected in [
            "duplicate-powershell-prompt",
            "powershell-prompt-prefix",
            "cmd-prompt-prefix",
            "continuation-prompt",
            "powershell-error-location",
            "powershell-error-metadata",
            "powershell-error-header",
            "instruction-prose-in-command-block",
        ]:
            self.assertIn(expected, rule_ids)
        case_ids = {case["id"] for case in fixture["cases"]}
        self.assertIn("bad-duplicated-powershell-prompt", case_ids)
        self.assertIn("bad-powershell-error-header", case_ids)
        fixture_text = read_text(OPERATOR_FIXTURE_PATH)
        self.assertNotIn("pa_rperez26", fixture_text)
        self.assertNotIn("Northwell", fixture_text)

    def test_p00_forces_string_replace_and_forbids_ambiguous_overload(self):
        p00 = read_text(P00_PATH)
        self.assertNotIn(".Replace([char]0, '')", p00)
        self.assertIn(
            ".Replace(([char]0).ToString(), [string]::Empty)",
            p00,
        )
        self.assertIn("char/char cannot represent an empty replacement", p00)

    def test_entrypoints_resolve_psscriptroot_in_body_not_parameter_defaults(self):
        for path in [
            OPERATOR_VALIDATOR_PATH,
            SURFACE_VALIDATOR_PATH,
            HARNESS_VALIDATOR_PATH,
            STATUS_REPORTER_PATH,
            HOOK_PATH,
        ]:
            text = read_text(path)
            boundary = text.find("Set-StrictMode")
            self.assertGreater(boundary, 0, path)
            parameter_surface = text[:boundary]
            self.assertNotRegex(
                parameter_surface,
                re.compile(r"=\s*\([^)]*\$PSScriptRoot", re.IGNORECASE),
                path,
            )
            self.assertIn(
                "if ([string]::IsNullOrWhiteSpace($RootPath))",
                text,
                path,
            )

    def test_surface_validator_executes_behavior_guard(self):
        validator = read_text(SURFACE_VALIDATOR_PATH)
        for token in [
            "p00/no-ambiguous-char-replace",
            "p00/string-replace",
            "p00/null-normalization-behavior",
            "$nullPadded",
            "$normalized -eq 'Ubuntu'",
        ]:
            self.assertIn(token, validator)
        self.assertNotRegex(
            validator,
            re.compile(
                r"(?mi)^\s*Write-Host\b.*-ForegroundColor\s+\(if\b"
            ),
        )

    def test_harness_validator_checks_tracking_children_and_noninteractive_git(self):
        validator = read_text(HARNESS_VALIDATOR_PATH)
        for token in [
            "git -C $RootPath ls-files --error-unmatch",
            "Test-OperatorCommandEnvelope.ps1",
            "tests.test_operator_command_envelope",
            "Test-TechnicianLiveCertSurface.ps1",
            "tests.test_technician_live_cert_harness",
            "tests.test_technician_live_cert_surface",
            "git -C $RootPath --no-pager diff --check",
            "Get-Process : A positional parameter",
        ]:
            self.assertIn(token, validator)

    def test_hook_is_opt_in_and_blocks_generated_evidence(self):
        hook = read_text(HOOK_PATH)
        for token in [
            "Test-OperatorCommandEnvelope.ps1",
            "Test-TechnicianLiveCertHarness.ps1",
            "git -C $RootPath --no-pager diff --cached --check",
            "Generated technician evidence must not be committed",
            "operator-command-envelope-report",
            "preflight-summary",
            "stage-result",
        ]:
            self.assertIn(token, hook)
        self.assertNotIn("core.hooksPath", hook)

    def test_ci_runs_cross_shell_matrix_and_fixture_safe_cmd(self):
        workflow = read_text(CI_PATH)
        for token in [
            "python -m unittest tests.test_operator_command_envelope",
            "python -m unittest tests.test_technician_live_cert_harness",
            "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-OperatorCommandEnvelope.ps1",
            "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TechnicianLiveCertSurface.ps1",
            "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-TechnicianLiveCertHarness.ps1",
            "pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1",
            "pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertSurface.ps1",
            "pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertHarness.ps1",
            "TECHNICIAN_LIVE_CERT_CI_SURFACE",
            "operator-command-envelope-report",
            "git --no-pager diff --check",
        ]:
            self.assertIn(token, workflow)

    def test_skills_and_operator_guide_route_to_scoped_harness(self):
        skill = read_text(SKILL_PATH)
        operator_skill = read_text(OPERATOR_SKILL_PATH)
        guide = read_text(GUIDE_PATH)
        for token in [
            "tooling/profiles/windows/harness/technician-live-cert/manifest.json",
            "scripts/Test-TechnicianLiveCertHarness.ps1",
            "scripts/Test-OperatorCommandEnvelope.ps1",
            ".ai/skills/operator-command-envelope/SKILL.md",
            "Windows PowerShell 5.1",
            "PowerShell 7",
        ]:
            self.assertIn(token, skill)
        for token in [
            "Name the shell outside the code fence",
            "Never include a PowerShell prompt",
            "Test-OperatorCommandEnvelope.ps1 -CandidatePath",
        ]:
            self.assertIn(token, operator_skill)
        for token in [
            "What is working",
            "What is broken",
            "What is missing",
            "git --no-pager",
            "exact operator command",
            "operator-command envelope",
            "CandidatePath",
            "proof ceiling",
        ]:
            self.assertIn(token, guide)

    def test_operator_command_report_template_is_actionable(self):
        template = read_text(OPERATOR_REPORT_TEMPLATE_PATH)
        for token in [
            "{{sanitizedCommand}}",
            "{{owner}}",
            "{{dependency}}",
            "{{artifact}}",
            "{{completionGate}}",
            "{{nextCommand}}",
        ]:
            self.assertIn(token, template)


if __name__ == "__main__":
    unittest.main()
