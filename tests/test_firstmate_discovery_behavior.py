#!/usr/bin/env python3
"""Behavioral discovery regressions for the FirstMate Linux/WSL probe."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tooling" / "firstmate" / "Test-FirstMateInterop.sh"
CONTRACT = ROOT / "tooling" / "firstmate" / "harness" / "integration-contract.json"
PIN = ROOT / "tooling" / "firstmate" / "harness" / "upstream-pin.json"
MISSING_REQUIRED = ".agents/skills/project-management/SKILL.md"


def run(*args: str, cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )


class FirstMateDiscoveryBehaviorTests(unittest.TestCase):
    def test_ignored_worktree_substitute_cannot_satisfy_audited_path_contract(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            home.mkdir()
            # Existing non-clone path prevents network bootstrap after alternate
            # discovery correctly rejects the synthetic incomplete checkout.
            (home / "firstmate").mkdir()

            candidate = home / "dev" / "firstmate"
            candidate.mkdir(parents=True)
            run("git", "init", str(candidate), cwd=root)
            run(
                "git",
                "-C",
                str(candidate),
                "remote",
                "add",
                "origin",
                "https://github.com/kunchenguid/firstmate.git",
                cwd=root,
            )

            required = json.loads(CONTRACT.read_text(encoding="utf-8"))["required_upstream_paths"]
            for relative in required:
                if relative == MISSING_REQUIRED:
                    continue
                path = candidate / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture\n", encoding="utf-8")

            run("git", "-C", str(candidate), "add", ".", cwd=root)
            run(
                "git",
                "-C",
                str(candidate),
                "-c",
                "user.name=ASB Test",
                "-c",
                "user.email=asb-test@example.com",
                "commit",
                "-m",
                "synthetic audited floor",
                cwd=root,
            )
            expected_head = run("git", "-C", str(candidate), "rev-parse", "HEAD", cwd=root).stdout.strip()

            # Add the missing required path only as ignored worktree state. The tree
            # remains clean and -e succeeds, reproducing the old false-positive.
            fake = candidate / MISSING_REQUIRED
            fake.parent.mkdir(parents=True, exist_ok=True)
            fake.write_text("ignored substitute\n", encoding="utf-8")
            exclude = candidate / ".git" / "info" / "exclude"
            with exclude.open("a", encoding="utf-8") as handle:
                handle.write(f"/{MISSING_REQUIRED}\n")
            self.assertEqual("", run("git", "-C", str(candidate), "status", "--porcelain=v1", cwd=root).stdout)
            self.assertTrue(fake.exists())
            missing_tree = subprocess.run(
                ["git", "-C", str(candidate), "cat-file", "-e", f"{expected_head}:{MISSING_REQUIRED}"],
                cwd=root,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(0, missing_tree.returncode)

            probe_root = root / "probe" / "tooling" / "firstmate"
            harness_root = probe_root / "harness"
            harness_root.mkdir(parents=True)
            copied_probe = probe_root / PROBE.name
            shutil.copy2(PROBE, copied_probe)

            contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
            contract["upstream"]["verified_commit"] = expected_head
            contract["upstream"]["pr96_audited_commit"] = "0" * 40
            (harness_root / "integration-contract.json").write_text(
                json.dumps(contract, indent=2) + "\n",
                encoding="utf-8",
            )
            pin = json.loads(PIN.read_text(encoding="utf-8"))
            pin["commit"] = expected_head
            (harness_root / "upstream-pin.json").write_text(
                json.dumps(pin, indent=2) + "\n",
                encoding="utf-8",
            )

            stub_bin = root / "stub-bin"
            stub_bin.mkdir()
            for name in ("gh", "tmux", "opencode"):
                stub = stub_bin / name
                stub.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
                stub.chmod(0o755)

            env = dict(os.environ)
            env["HOME"] = str(home)
            env.pop("FIRSTMATE_DIR", None)
            env["PATH"] = f"{stub_bin}{os.pathsep}{env.get('PATH', '')}"
            completed = subprocess.run(
                ["bash", str(copied_probe)],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
            )

            combined = completed.stdout + completed.stderr
            self.assertEqual(50, completed.returncode, combined)
            self.assertIn("Skipping non-viable auto-discovery candidate", combined)
            self.assertIn("missing required audited paths", combined)
            self.assertIn("STATUS=BLOCKED_FIRSTMATE_PIN", combined)
            self.assertNotIn("[PASS] FIRSTMATE_INTEROP", combined)


if __name__ == "__main__":
    unittest.main()
