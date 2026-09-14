#!/usr/bin/env python3
"""Focused FirstMate Linux/WSL integration-contract tests through FM-BRIDGE-10."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"
VERIFICATION_PATH = ROOT / "tooling" / "firstmate" / "harness" / "upstream-verification.json"
PIN_PATH = ROOT / "tooling" / "firstmate" / "harness" / "upstream-pin.json"
CONVERGENCE_PATH = ROOT / "tooling" / "firstmate" / "harness" / "convergence-contract.json"
PROBE_PATH = ROOT / "tooling" / "firstmate" / "Test-FirstMateInterop.sh"
DOC_PATH = ROOT / "docs" / "harness" / "firstmate-integration.md"
OPERATIONAL_DOC = ROOT / "docs" / "harness" / "firstmate-operational-harness.md"
EXPECTED_SHA = "b182d0f908b78d08c7ccb8dce3775bdca8c5d657"
STALE_PR96_SHA = "833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409"


class FirstMateIntegrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
        cls.verification = json.loads(VERIFICATION_PATH.read_text(encoding="utf-8"))
        cls.pin = json.loads(PIN_PATH.read_text(encoding="utf-8"))
        cls.convergence = json.loads(CONVERGENCE_PATH.read_text(encoding="utf-8"))
        cls.probe = PROBE_PATH.read_text(encoding="utf-8")
        cls.docs = DOC_PATH.read_text(encoding="utf-8")

    def test_upstream_pin_is_exact_and_shared_across_owners(self) -> None:
        sha = self.contract["upstream"]["verified_commit"]
        self.assertEqual(sha, EXPECTED_SHA)
        self.assertRegex(sha, re.compile(r"^[0-9a-f]{40}$"))
        self.assertEqual(self.verification["verified_commit"], sha)
        self.assertEqual(self.pin["commit"], sha)
        self.assertEqual(self.convergence["upstream"]["auditedCommit"], sha)
        self.assertEqual(
            self.contract["upstream"]["repository"],
            "https://github.com/kunchenguid/firstmate",
        )
        self.assertEqual(self.pin["repository"], "kunchenguid/firstmate")

    def test_stale_pr96_pin_is_recorded_but_rejected_as_current(self) -> None:
        self.assertEqual(self.contract["upstream"]["pr96_audited_commit"], STALE_PR96_SHA)
        self.assertEqual(self.pin["pr96AuditedCommit"], STALE_PR96_SHA)
        self.assertEqual(self.verification["pr96_audited_commit"], STALE_PR96_SHA)
        self.assertNotEqual(EXPECTED_SHA, STALE_PR96_SHA)
        self.assertIn("must not remain on the historical PR #96 audit SHA", self.probe)

    def test_first_sprint_is_local_only_non_mutating_and_yolo_off(self) -> None:
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

    def test_platform_claim_is_explicit_ubuntu_bridge_only(self) -> None:
        platform = self.contract["platform_contract"]
        self.assertIn("Linux", platform["upstream_declared_platforms"])
        self.assertEqual(platform["agentswitchboard_target"], "WSL/Ubuntu")
        self.assertEqual(platform["wsl_distribution"], "Ubuntu")
        self.assertEqual(platform["native_windows"], "unverified and out of scope")
        self.assertEqual(platform["windows_host_role"], "bridge_only")
        self.assertIn("inference", platform["wsl_support_claim"])
        self.assertTrue(self.pin["outOfScope"]["nativeWindows"])
        self.assertEqual(self.convergence["runtime"]["nativeWindows"], "out_of_scope")
        self.assertEqual(self.convergence["runtime"]["windowsHostRole"], "bridge_only")

    def test_role_boundaries_and_bridge_status_are_explicit(self) -> None:
        roles = self.contract["role_boundaries"]
        self.assertIn("not a second live crew orchestrator", roles["agentswitchboard"])
        self.assertIn("canonical live crew runtime", roles["firstmate"])
        runtime = self.contract["runtime_contract"]
        self.assertEqual(runtime["reference_backend"], "tmux")
        self.assertEqual(runtime["herdr"]["status"], "experimental-unproved")
        self.assertIs(runtime["herdr"]["automatic_selection"], False)
        bridge = self.contract["windows_bridge"]
        self.assertEqual("FM-BRIDGE-10", bridge["lane"])
        self.assertEqual("contract-integrated-runtime-unproved", bridge["status"])
        self.assertEqual("FirstMate", bridge["runtime_owner_after_bridge"])

    def test_routing_disposition_does_not_recreate_asb_crew_control(self) -> None:
        routing = self.contract["routing_disposition"]
        self.assertIsNone(routing["agentswitchboard_skill"])
        self.assertIsNone(routing["agentswitchboard_capability"])
        self.assertIsNone(routing["agentswitchboard_trigger"])
        self.assertIn("FirstMate owns live crew dispatch", routing["reason"])

    def test_probe_has_strict_shell_and_no_mutation_commands(self) -> None:
        self.assertIn("set -euo pipefail", self.probe)
        forbidden = (
            "git push",
            "git commit",
            "gh pr create",
            "gh repo create",
            "no-mistakes init",
            "apt install",
            "apt-get install",
            "brew install",
            "rm -rf",
        )
        for command in forbidden:
            self.assertNotIn(command, self.probe, command)
        # Bounded local FirstMate pin bootstrap is allowed environment setup
        # (clone to $HOME/firstmate at the audited pin only). Upstream mutation
        # remains forbidden.
        self.assertIn('bootstrap_dir="$HOME/firstmate"', self.probe)
        self.assertIn("git clone --quiet", self.probe)
        self.assertIn("BOOTSTRAPPED_FIRSTMATE=", self.probe)
        self.assertEqual(self.probe.count("git clone"), 1)

    def test_probe_accepts_git_worktree_identity_via_git(self) -> None:
        self.assertIn("rev-parse --is-inside-work-tree", self.probe)
        self.assertNotIn('[[ -d "$candidate/.git" ]]', self.probe)

    def test_origin_normalization_accepts_supported_git_transports(self) -> None:
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

    def test_probe_contract_parsing_is_fail_closed(self) -> None:
        self.assertIn("required_upstream_paths must be a non-empty list", self.probe)
        self.assertIn("PurePosixPath", self.probe)
        self.assertIn("must not contain control characters", self.probe)
        self.assertIn("first_safe_sprint.yolo_enabled must be explicitly false", self.probe)
        self.assertIn("must match upstream-pin.json commit", self.probe)
        self.assertNotIn("mapfile -t REQUIRED_PATHS < <(", self.probe)

    def test_probe_requires_clean_audited_clone_and_toolchain(self) -> None:
        self.assertIn("status --porcelain=v1", self.probe)
        # Structured pin/dirty fail-closed (exits 49/50) before long interop path.
        self.assertIn('if [[ "$ACTUAL_HEAD" != "$EXPECTED_HEAD" ]]; then', self.probe)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", self.probe)
        self.assertIn("STATUS=BLOCKED_FIRSTMATE_DIRTY", self.probe)
        self.assertIn("exit 50", self.probe)
        self.assertIn("exit 49", self.probe)
        for tool in self.contract["runtime_contract"]["required_tools"]:
            self.assertIn(tool, self.probe)
        for path in self.contract["required_upstream_paths"]:
            self.assertIn(path, self.verification["inspected_paths"])

    def test_auto_discovery_validates_required_paths_before_selection(self) -> None:
        self.assertIn("has_required_upstream_paths()", self.probe)
        self.assertIn('for path in "${REQUIRED_PATHS[@]}"; do', self.probe)
        start = self.probe.index("is_viable_discovered_firstmate()")
        end = self.probe.index('if [[ -z "$FIRSTMATE_DIR" ]]', start)
        viability = self.probe[start:end]
        self.assertIn('[[ "$head" == "$EXPECTED_HEAD" ]] || return 1', viability)
        self.assertIn('has_required_upstream_paths "$candidate"', viability)
        self.assertIn("missing required audited paths", self.probe)
        # $HOME/firstmate remains authoritative even when incomplete so the later
        # explicit checkout validation can report the owned-path defect instead of
        # silently replacing an operator checkout.
        home_preference = 'if is_firstmate_clone "$HOME/firstmate"; then'
        alternate_loop = 'if is_viable_discovered_firstmate "$candidate"; then'
        self.assertLess(self.probe.index(home_preference), self.probe.index(alternate_loop))

    def test_docs_bind_foundation_to_operational_bridge_and_proof_ceiling(self) -> None:
        self.assertTrue(OPERATIONAL_DOC.is_file())
        self.assertIn(EXPECTED_SHA, self.docs)
        self.assertIn(STALE_PR96_SHA, self.docs)
        self.assertIn("local-only", self.docs)
        self.assertIn("first_safe_sprint.yolo_enabled", self.docs)
        self.assertIn("Test-FirstMateInterop.sh", self.docs)
        self.assertIn("Proof ceiling", self.docs)
        self.assertIn("WSL/Ubuntu", self.docs)
        self.assertIn("bridge only", self.docs.lower())
        self.assertIn("firstmate-operational-harness.md", self.docs)
        self.assertIn("Herdr promotion is a separate gate", self.docs)

    def test_probe_rejects_stale_head_when_clone_is_wrong_commit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stub_bin = root / "stub-bin"
            stub_bin.mkdir()
            for name in ("gh", "tmux"):
                stub = stub_bin / name
                stub.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
                stub.chmod(0o755)

            repo = root / "firstmate"
            subprocess.run(["git", "init", str(repo)], check=True, capture_output=True)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "add", "origin", "https://github.com/kunchenguid/firstmate.git"],
                check=True,
                capture_output=True,
            )
            (repo / "AGENTS.md").write_text("stub\n", encoding="utf-8")
            (repo / "README.md").write_text("stub\n", encoding="utf-8")
            (repo / "docs").mkdir()
            (repo / "docs" / "configuration.md").write_text("stub\n", encoding="utf-8")
            (repo / ".agents" / "skills" / "project-management").mkdir(parents=True)
            (repo / ".agents" / "skills" / "project-management" / "SKILL.md").write_text("stub\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True, capture_output=True)
            subprocess.run(
                [
                    "git", "-C", str(repo), "-c", "user.name=ASB Test",
                    "-c", "user.email=asb-test@example.com", "commit", "-m", "stale fixture",
                ],
                check=True,
                capture_output=True,
            )
            env = dict(os.environ)
            env["PATH"] = f"{stub_bin}{os.pathsep}{env.get('PATH', '')}"
            completed = subprocess.run(
                ["bash", str(PROBE_PATH), "--firstmate", str(repo)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(completed.returncode, 50)
            combined = completed.stdout + completed.stderr
            self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", combined)
            self.assertIn(EXPECTED_SHA, combined)
            self.assertIn("git checkout", combined)
            self.assertNotIn("Required tool is unavailable", combined)


if __name__ == "__main__":
    unittest.main()
