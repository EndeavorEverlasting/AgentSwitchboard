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
SURFACE_VALIDATOR_PATH = os.path.join(REPO_ROOT, "scripts", "Test-TechnicianLiveCertSurface.ps1")
HARNESS_VALIDATOR_PATH = os.path.join(REPO_ROOT, "scripts", "Test-TechnicianLiveCertHarness.ps1")
OPERATOR_VALIDATOR_PATH = os.path.join(REPO_ROOT, "scripts", "Test-OperatorCommandEnvelope.ps1")
CERTIFICATION_VALIDATOR_PATH = os.path.join(REPO_ROOT, "scripts", "Test-WindowsProfileLiveCertification.ps1")
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
CI_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "technician-live-cert-surface.yml")
SKILL_PATH = os.path.join(REPO_ROOT, ".ai", "skills", "windows-profile-live-certification", "SKILL.md")
OPERATOR_SKILL_PATH = os.path.join(REPO_ROOT, ".ai", "skills", "operator-command-envelope", "SKILL.md")
GUIDE_PATH = os.path.join(REPO_ROOT, "docs", "harness", "technician-live-cert-harness.md")
OPERATOR_CONTRACT_PATH = os.path.join(HARNESS_ROOT, "operator-command-contract.json")
OPERATOR_FIXTURE_PATH = os.path.join(
    HARNESS_ROOT, "fixtures", "operator-command-contamination.fixture.json"
)
OPERATOR_REPORT_TEMPLATE_PATH = os.path.join(HARNESS_ROOT, "operator-command-report.template.md")


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
        self.assertIn("prompt-free operator-command contracts", self.manifest["proofCeiling"])

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
            parsed = read_json(os.path.join(REPO_ROOT, entrypoints[key].replace("/", os.sep)))
            self.assertIsInstance(parsed, dict, key)

    def test_operator_command_contract_and_fixture_are_registered(self):
        contract = read_json(OPERATOR_CONTRACT_PATH)
        fixture = read_json(OPERATOR_FIXTURE_PATH)
        self.assertEqual("agentswitchboard.operator-command-envelope.v1", contract["contractId"])
        rule_ids = {rule["id"] for rule in contract["rules"]}
        for expected in [
            "duplicate-powershell-prompt",
            "powershell-prompt-prefix",
            "cmd-prompt-prefix",
            "posix-shell-prompt-prefix",
            "continuation-prompt",
            "powershell-error-location",
            "powershell-error-metadata",
            "powershell-error-header",
            "instruction-prose-in-command-block",
        ]:
            self.assertIn(expected, rule_ids)
        case_ids = {case["id"] for case in fixture["cases"]}
        for expected in [
            "bad-duplicated-powershell-prompt",
            "bad-duplicated-unix-powershell-prompt",
            "bad-wsl-shell-prompt",
            "bad-powershell-error-header",
        ]:
            self.assertIn(expected, case_ids)
        fixture_text = read_text(OPERATOR_FIXTURE_PATH)
        self.assertNotIn("pa_rperez26", fixture_text)
        self.assertNotIn("Northwell", fixture_text)

    def test_p00_forces_string_replace_and_forbids_ambiguous_overload(self):
        p00 = read_text(P00_PATH)
        self.assertNotIn(".Replace([char]0, '')", p00)
        self.assertIn(".Replace(([char]0).ToString(), [string]::Empty)", p00)
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
            self.assertNotRegex(
                text[:boundary],
                re.compile(r"=\s*\([^)]*\$PSScriptRoot", re.IGNORECASE),
                path,
            )
            self.assertIn("if ([string]::IsNullOrWhiteSpace($RootPath))", text, path)

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

    def test_harness_validator_binds_every_child_to_exact_root(self):
        validator = read_text(HARNESS_VALIDATOR_PATH)
        for token in [
            "[Parameter(Mandatory)][string]$WorkingDirectory",
            "Push-Location -LiteralPath $WorkingDirectory",
            "Pop-Location",
            "-WorkingDirectory $RootPath",
            "tests.test_operator_command_envelope",
            "tests.test_technician_live_cert_harness",
            "tests.test_technician_live_cert_surface",
            "git -C $RootPath --no-pager diff --check",
        ]:
            self.assertIn(token, validator)
        self.assertNotIn("Invoke-Checked $python.Source @('-m', 'unittest'", validator)

    def test_ci_proves_external_working_directory_independence(self):
        workflow = read_text(CI_PATH)
        for token in [
            "Validate harness in PowerShell 7 from external working directory",
            "Validate harness in Windows PowerShell 5.1 from external working directory",
            "Push-Location -LiteralPath $env:RUNNER_TEMP",
            "-RootPath $root",
            "Join-Path $root 'scripts/Test-TechnicianLiveCertHarness.ps1'",
            "Join-Path $root 'scripts\\Test-TechnicianLiveCertHarness.ps1'",
            "python -m unittest tests.test_operator_command_envelope",
            "git --no-pager diff --check",
        ]:
            self.assertIn(token, workflow)

    def test_independent_certification_requires_every_command_rule(self):
        validator = read_text(CERTIFICATION_VALIDATOR_PATH)
        for token in [
            "posix-shell-prompt-prefix",
            "instruction-prose-in-command-block",
        ]:
            self.assertIn(token, validator)

    def test_hook_validates_clean_staged_snapshot_not_mixed_worktree(self):
        hook = read_text(HOOK_PATH)
        for token in [
            "git -C $RootPath --no-pager diff --cached --check",
            "git -C $RootPath write-tree",
            "commit-tree $tree -p HEAD",
            "worktree add --detach $snapshotRoot $snapshotCommit",
            "-CandidatePath $candidatePaths",
            "-RootPath $snapshotRoot",
            "worktree remove $snapshotRoot",
            "Generated technician evidence must not be committed",
        ]:
            self.assertIn(token, hook)
        self.assertLess(hook.index("$staged = @("), hook.index("Test-OperatorCommandEnvelope.ps1"))

    def test_status_reporter_catches_operator_validator_failure(self):
        status = read_text(STATUS_REPORTER_PATH)
        for token in [
            "try {",
            "catch {",
            "errorType = $_.Exception.GetType().FullName",
            "Operator-command validator failed before producing structured output.",
            "status = 'FAIL'",
        ]:
            self.assertIn(token, status)

    def test_skills_and_guide_route_to_harness(self):
        skill = read_text(SKILL_PATH)
        operator_skill = read_text(OPERATOR_SKILL_PATH)
        guide = read_text(GUIDE_PATH)
        for token in [
            "scripts/Test-TechnicianLiveCertHarness.ps1",
            "scripts/Test-OperatorCommandEnvelope.ps1",
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
            "exact operator command",
            "operator-command envelope",
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
