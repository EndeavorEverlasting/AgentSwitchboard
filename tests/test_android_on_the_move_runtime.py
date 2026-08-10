import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class AndroidOnTheMoveRuntimeTests(unittest.TestCase):
    def test_required_files_exist(self):
        for rel in [
            "Start-AgentSwitchboard-Android.sh",
            "tooling/profiles/android/AgentSwitchboard-Android.sh",
            "tooling/profiles/android/codex-runtime.json",
            "tooling/profiles/android/runtime-proof-sprint.prompt.md",
            "docs/workstation/android-on-the-move-runtime.md",
        ]:
            self.assertTrue((ROOT / rel).is_file(), rel)

    def test_codex_runtime_is_pinned_and_android_arm64_bound(self):
        manifest = json.loads(
            (ROOT / "tooling/profiles/android/codex-runtime.json").read_text()
        )
        self.assertEqual(manifest["agent"], "codex")
        self.assertEqual(manifest["package"], "@openai/codex")
        self.assertEqual(manifest["version"], "0.147.0")
        self.assertEqual(manifest["sourceTag"], "rust-v0.147.0")
        self.assertEqual(manifest["nodeDispatch"]["platform"], "android")
        self.assertEqual(manifest["nodeDispatch"]["arch"], "arm64")
        self.assertEqual(
            manifest["nodeDispatch"]["targetTriple"],
            "aarch64-unknown-linux-musl",
        )
        self.assertEqual(
            manifest["nodeDispatch"]["platformPackage"],
            "@openai/codex-linux-arm64",
        )

        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("CODEX_PACKAGE='@openai/codex'", text)
        self.assertIn("CODEX_VERSION='0.147.0'", text)
        self.assertIn('npm install -g --ignore-scripts "${CODEX_PACKAGE}@${CODEX_VERSION}"', text)
        self.assertIn("pkg install -y git openssh tmux gh jq nodejs", text)
        self.assertIn("unexpected PREFIX", text)
        self.assertIn("CODEX_NODE_PLATFORM='android'", text)
        self.assertIn("CODEX_NODE_ARCH='arm64'", text)
        self.assertNotIn("PI_PACKAGE=", text)
        self.assertNotIn("pi --mode", text)
        self.assertNotIn("StrictHostKeyChecking=no", text)
        self.assertNotIn("id_ed25519", text)

    def test_codex_auth_is_device_flow_and_secret_safe(self):
        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("codex login --device-auth", text)
        self.assertIn("codex login status", text)
        self.assertIn("never prints or records OAuth device codes", text)
        self.assertNotIn("OPENAI_API_KEY=", text)
        self.assertNotIn("CODEX_ACCESS_TOKEN=", text)

    def test_smoke_requires_same_run_command_and_behavior(self):
        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("codex exec --json --ephemeral -s read-only", text)
        self.assertIn('.type == "turn.completed"', text)
        self.assertIn('.item.type == "command_execution"', text)
        self.assertIn("AGENTS.md", text)
        self.assertIn("ANDROID_RUNTIME_SMOKE=PASS", text)
        self.assertIn("proof_level=live-agent-tool-behavior", text)

    def test_writing_sprint_isolated_sandboxed_and_proved(self):
        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("writing sprint refuses main", text)
        self.assertIn("codex exec --json --ephemeral --approve-for-me", text)
        self.assertIn('.item.type == "file_change"', text)
        self.assertIn("git -C \"$REPO_ROOT\" diff --check", text)
        self.assertIn("git -C \"$REPO_ROOT\" ls-remote origin", text)
        self.assertIn('gh pr view "$branch"', text)
        self.assertIn("ANDROID_RUNTIME_SPRINT=COMPLETE", text)
        self.assertIn("proof_level=live-agent-repository-mutation", text)
        self.assertIn("timeout 1800", text)
        self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", text)
        self.assertNotIn("--dangerously-bypass-hook-trust", text)

    def test_android_profile_registration_is_honest(self):
        registry = json.loads((ROOT / ".ai/harness/device-profile-registry.json").read_text())
        android = next(p for p in registry["profiles"] if p["profileId"] == "android")
        self.assertEqual(android["status"], "implemented-runtime-unproved")
        self.assertEqual(android["frontend"], "termux")
        self.assertEqual(android["canonicalSourcePath"], "Start-AgentSwitchboard-Android.sh")
        self.assertEqual(android["installedPath"], "$PREFIX/bin/agentswitchboard-android")
        self.assertEqual(android["codingAgent"], "codex")
        self.assertIn("Codex", registry["proofCeiling"])
        self.assertNotIn("Pi provider", registry["proofCeiling"])

    def test_proof_sprint_task_is_bounded(self):
        text = (ROOT / "tooling/profiles/android/runtime-proof-sprint.prompt.md").read_text()
        self.assertIn("documentation only", text)
        self.assertIn("docs/workstation/android-command-transport.md", text)
        self.assertIn("git diff --check", text)
        self.assertIn("docs(android): add cross-device command transport guide", text)
        self.assertIn("do not merge", text.lower())


if __name__ == "__main__":
    unittest.main()
