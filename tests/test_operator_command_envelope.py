from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "technician-live-cert"
CONTRACT = HARNESS / "operator-command-contract.json"
FIXTURE = HARNESS / "fixtures" / "operator-command-contamination.fixture.json"
VALIDATOR = ROOT / "scripts" / "Test-OperatorCommandEnvelope.ps1"
MANIFEST = HARNESS / "manifest.json"
HOOK = ROOT / "tooling" / "profiles" / "windows" / "hooks" / "Invoke-TechnicianLiveCertPreCommit.ps1"
STATUS = ROOT / "tooling" / "profiles" / "windows" / "Get-TechnicianLiveCertHarnessStatus.ps1"
CI = ROOT / ".github" / "workflows" / "technician-live-cert-surface.yml"
SKILL = ROOT / ".ai" / "skills" / "operator-command-envelope" / "SKILL.md"
REPORT_TEMPLATE = HARNESS / "operator-command-report.template.md"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def read_json(path: Path):
    return json.loads(read_text(path))


def rule_matches(contract: dict, text: str) -> list[str]:
    return sorted(
        {
            rule["id"]
            for rule in contract["rules"]
            if re.search(rule["pattern"], text)
        }
    )


def command_lines(path: Path, allowed_languages: set[str]):
    lines = read_text(path).splitlines()
    inside = False
    marker = ""
    language = ""
    for number, line in enumerate(lines, start=1):
        if not inside:
            match = re.match(r"^\s*(?P<marker>`{3,}|~{3,})(?P<lang>[A-Za-z0-9_+-]*)\s*$", line)
            if match:
                inside = True
                marker = match.group("marker")
                language = match.group("lang").lower()
            continue

        close_pattern = rf"^\s*{re.escape(marker[0])}{{{len(marker)},}}\s*$"
        if re.match(close_pattern, line):
            inside = False
            marker = ""
            language = ""
            continue

        if language in allowed_languages:
            yield number, language, line

    if inside:
        raise AssertionError(f"unterminated command fence: {path}")


class TestOperatorCommandEnvelope(unittest.TestCase):
    def setUp(self):
        self.contract = read_json(CONTRACT)
        self.fixture = read_json(FIXTURE)

    def test_identity_and_safety_boundary(self):
        self.assertEqual(1, self.contract["schemaVersion"])
        self.assertEqual(
            "agentswitchboard.operator-command-envelope.v1",
            self.contract["contractId"],
        )
        self.assertEqual(
            "EndeavorEverlasting/AgentSwitchboard",
            self.contract["canonicalOwner"],
        )
        self.assertFalse(self.contract["generatedEvidence"]["tracked"])
        self.assertIn("does not prove the command succeeds", self.contract["proofCeiling"])

    def test_fixture_reproduces_cross_platform_prompt_and_transcript_failures(self):
        for case in self.fixture["cases"]:
            actual = rule_matches(self.contract, case["text"])
            expected = sorted(case["expectedRuleIds"])
            self.assertEqual(expected, actual, case["id"])

        case_ids = {case["id"] for case in self.fixture["cases"]}
        for required in [
            "bad-duplicated-powershell-prompt",
            "bad-duplicated-unix-powershell-prompt",
            "bad-unix-powershell-prompt",
            "bad-wsl-shell-prompt",
            "bad-bracketed-posix-prompt",
        ]:
            self.assertIn(required, case_ids)

        fixture_text = read_text(FIXTURE)
        ordinary_windows_user = re.compile(
            r"(?i)C:\\Users\\(?!<redacted>)[^\\\r\n]+"
        )
        self.assertRegex(r"C:\Users\alice\repo", ordinary_windows_user)
        self.assertNotRegex(fixture_text, ordinary_windows_user)
        self.assertNotIn("pa_rperez26", fixture_text)
        self.assertNotIn("Northwell", fixture_text)

    def test_markdown_parser_accepts_longer_closing_fence(self):
        allowed = {language.lower() for language in self.contract["fenceLanguages"]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "handoff.md"
            path.write_text(
                "```powershell\nGet-Date\n````\n\n~~~~bash\nprintf ok\n~~~~~~\n",
                encoding="utf-8",
            )
            records = list(command_lines(path, allowed))
        self.assertEqual(
            [(2, "powershell", "Get-Date"), (6, "bash", "printf ok")],
            records,
        )

    def test_redaction_contract_covers_paths_identities_hosts_and_secrets(self):
        patterns = [entry["pattern"] for entry in self.contract["sanitization"]["redactPatterns"]]
        samples = [
            r"C:\Users\alice\repo",
            "/home/alice/repo",
            r"\\fileserver\private\repo",
            "alice@example.internal",
            "$env:API_KEY='secret-value'",
            "tool --token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
            "sk-ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890",
        ]
        for sample in samples:
            self.assertTrue(
                any(re.search(pattern, sample) for pattern in patterns),
                sample,
            )

    def test_registered_operator_surfaces_exist_and_are_clean(self):
        allowed = {language.lower() for language in self.contract["fenceLanguages"]}
        for relative in self.contract["scanPaths"]:
            path = ROOT / Path(relative)
            self.assertTrue(path.is_file(), relative)
            for line_number, _language, line in command_lines(path, allowed):
                matches = rule_matches(self.contract, line)
                self.assertEqual([], matches, f"{relative}:{line_number}: {matches}")

    def test_validator_is_cross_shell_fixture_backed_and_candidate_private(self):
        text = read_text(VALIDATOR)
        boundary = text.index("Set-StrictMode")
        self.assertNotIn("$PSScriptRoot", text[:boundary])
        for token in [
            "operator-command-contract.json",
            "operator-command-contamination.fixture.json",
            "Get-MarkdownCommandLines",
            "Get-SanitizedExcerpt",
            "duplicate-powershell-prompt",
            "posix-shell-prompt-prefix",
            "missing-operator-surface",
            "CandidatePath",
            "<candidate-content-redacted>",
            "<candidate-$candidateIndex>",
            "$fenceMarker.Length + ',}'",
            "$privacyProbes",
            "$contract.generatedEvidence.json",
            "$contract.generatedEvidence.markdown",
            "GITHUB_ACTIONS",
        ]:
            self.assertIn(token, text)

    def test_manifest_hook_status_and_ci_enforce_contract(self):
        manifest = read_json(MANIFEST)
        entrypoints = manifest["entrypoints"]
        self.assertEqual(
            "scripts/Test-OperatorCommandEnvelope.ps1",
            entrypoints["operatorCommandValidator"],
        )
        self.assertEqual(
            "tests/test_operator_command_envelope.py",
            entrypoints["operatorCommandPythonValidator"],
        )
        component_ids = {component["id"] for component in manifest["components"]}
        for required in [
            "operator-command-contract",
            "operator-command-fixture",
            "operator-command-validator",
            "operator-command-python-validator",
            "operator-command-skill",
            "operator-command-report-template",
            "operator-command-contract-schema",
            "operator-command-fixture-schema",
        ]:
            self.assertIn(required, component_ids)

        hook = read_text(HOOK)
        self.assertIn("Test-OperatorCommandEnvelope.ps1", hook)
        self.assertIn("CandidatePath", hook)
        self.assertIn("commit-tree", hook)
        self.assertIn("worktree add --detach", hook)

        status = read_text(STATUS)
        self.assertIn("operator-command-envelope", status)
        self.assertIn("Test-OperatorCommandEnvelope.ps1", status)
        self.assertIn("catch", status)
        self.assertIn("errorType", status)

        ci = read_text(CI)
        for token in [
            "python -m unittest tests.test_operator_command_envelope",
            "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/Test-OperatorCommandEnvelope.ps1",
            "pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandEnvelope.ps1",
            "operator-command-envelope-report",
        ]:
            self.assertIn(token, ci)

    def test_skill_and_report_define_prompt_free_handoff(self):
        skill = read_text(SKILL)
        for token in [
            "Name the shell outside the code fence",
            "Begin at the first executable character",
            "Never include a PowerShell prompt",
            "Never mix stdout, stderr, stack traces",
            "Prefer a repository-owned CMD, PS1",
            "Test-OperatorCommandEnvelope.ps1 -CandidatePath",
            "owner, dependency, expected artifact, and completion gate",
        ]:
            self.assertIn(token, skill)

        report = read_text(REPORT_TEMPLATE)
        for token in [
            "{{sanitizedCommand}}",
            "{{owner}}",
            "{{dependency}}",
            "{{artifact}}",
            "{{completionGate}}",
            "{{nextCommand}}",
        ]:
            self.assertIn(token, report)


if __name__ == "__main__":
    unittest.main()
