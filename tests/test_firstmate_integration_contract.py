import json
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"
VERIFICATION_PATH = ROOT / "tooling" / "firstmate" / "harness" / "upstream-verification.json"
PROBE_PATH = ROOT / "tooling" / "firstmate" / "Test-FirstMateInterop.sh"
DOC_PATH = ROOT / "docs" / "harness" / "firstmate-integration.md"
EXPECTED_SHA = "833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409"


class FirstMateIntegrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
        cls.verification = json.loads(VERIFICATION_PATH.read_text(encoding="utf-8"))
        cls.probe = PROBE_PATH.read_text(encoding="utf-8")
        cls.docs = DOC_PATH.read_text(encoding="utf-8")

    def test_upstream_pin_is_exact_and_shared(self):
        sha = self.contract["upstream"]["verified_commit"]
        self.assertEqual(sha, EXPECTED_SHA)
        self.assertRegex(sha, re.compile(r"^[0-9a-f]{40}$"))
        self.assertEqual(self.verification["verified_commit"], sha)
        self.assertEqual(self.contract["upstream"]["repository"], "https://github.com/kunchenguid/firstmate")

    def test_first_sprint_is_local_only_non_mutating_and_yolo_off(self):
        sprint = self.contract["first_safe_sprint"]
        self.assertEqual(sprint["project_delivery_mode"], "local-only")
        self.assertIs(sprint["yolo_enabled"], False)
        for key in (
            "remote_writes",
            "credential_mutation",
            "dependency_installation",
            "firstmate_repository_mutation",
            "agentswitchboard_shared_registry_mutation",
        ):
            self.assertIs(sprint[key], False, key)

    def test_platform_claim_does_not_overstate_windows_support(self):
        platform = self.contract["platform_contract"]
        self.assertIn("Linux", platform["upstream_declared_platforms"])
        self.assertEqual(platform["agentswitchboard_target"], "WSL/Linux")
        self.assertEqual(platform["wsl_distribution"], "Ubuntu")
        self.assertEqual(platform["native_windows"], "unverified and out of scope")
        self.assertIn("inference", platform["wsl_support_claim"])

    def test_role_boundaries_and_runtime_floor_are_explicit(self):
        roles = self.contract["role_boundaries"]
        self.assertIn("control plane", roles["agentswitchboard"])
        self.assertIn("crew chief", roles["firstmate"])
        runtime = self.contract["runtime_contract"]
        self.assertEqual(runtime["reference_backend"], "tmux")
        self.assertEqual(runtime["herdr"]["status"], "experimental-unproved")
        self.assertIs(runtime["herdr"]["automatic_selection"], False)

    def test_probe_has_strict_shell_and_no_mutation_commands(self):
        self.assertIn("set -euo pipefail", self.probe)
        forbidden = (
            "git push",
            "git commit",
            "gh pr create",
            "gh repo create",
            "git clone",
            "no-mistakes init",
            "apt install",
            "apt-get install",
            "brew install",
            "rm -rf",
        )
        for command in forbidden:
            self.assertNotIn(command, self.probe, command)

    def test_probe_accepts_git_worktree_identity_via_git(self):
        self.assertIn("rev-parse --is-inside-work-tree", self.probe)
        self.assertNotIn('[[ -d "$candidate/.git" ]]', self.probe)

    def test_origin_normalization_accepts_supported_git_transports(self):
        variants = (
            "https://github.com/kunchenguid/firstmate.git",
            "https://example-user@github.com/kunchenguid/firstmate.git/",
            "git://github.com/kunchenguid/firstmate.git",
            "git@github.com:kunchenguid/firstmate.git",
            "ssh://git@github.com/kunchenguid/firstmate.git",
        )
        for url in variants:
            completed = subprocess.run(
                ["bash", str(PROBE_PATH), "--normalize-origin", url],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.stdout.strip(), "kunchenguid/firstmate", url)

    def test_probe_contract_parsing_is_fail_closed(self):
        self.assertIn("required_upstream_paths must be a non-empty list", self.probe)
        self.assertIn("PurePosixPath", self.probe)
        self.assertIn("first_safe_sprint.yolo_enabled must be explicitly false", self.probe)
        self.assertNotIn("mapfile -t REQUIRED_PATHS < <(", self.probe)

    def test_probe_requires_clean_audited_clone_and_toolchain(self):
        self.assertIn("status --porcelain=v1", self.probe)
        self.assertIn('[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]]', self.probe)
        for tool in self.contract["runtime_contract"]["required_tools"]:
            self.assertIn(tool, self.probe)
        for path in self.contract["required_upstream_paths"]:
            self.assertIn(path, self.verification["inspected_paths"])

    def test_docs_bind_to_contract_and_proof_ceiling(self):
        self.assertIn(EXPECTED_SHA, self.docs)
        self.assertIn("local-only", self.docs)
        self.assertIn("first_safe_sprint.yolo_enabled", self.docs)
        self.assertIn("Test-FirstMateInterop.sh", self.docs)
        self.assertIn("Proof ceiling", self.docs)
        self.assertIn("WSL", self.docs)
        self.assertIn("Herdr promotion is a separate gate", self.docs)


if __name__ == "__main__":
    unittest.main()
