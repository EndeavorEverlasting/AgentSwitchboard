import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class AndroidOnTheMoveRuntimeTests(unittest.TestCase):
    def test_required_files_exist(self):
        for rel in [
            "Start-AgentSwitchboard-Android.sh",
            "tooling/profiles/android/AgentSwitchboard-Android.sh",
            "tooling/profiles/android/runtime-proof-sprint.prompt.md",
            "docs/workstation/android-on-the-move-runtime.md",
            ".pi/settings.json",
        ]:
            self.assertTrue((ROOT / rel).is_file(), rel)

    def test_runtime_is_pinned_and_termux_bounded(self):
        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("PI_PACKAGE='@earendil-works/pi-coding-agent'", text)
        self.assertIn("PI_VERSION='0.82.1'", text)
        self.assertIn("npm install -g --ignore-scripts", text)
        self.assertIn("pkg install -y git openssh tmux gh jq nodejs", text)
        self.assertIn("unexpected PREFIX", text)
        self.assertNotIn("StrictHostKeyChecking=no", text)
        self.assertNotIn("~/.config/gh/hosts.yml", text)
        self.assertNotIn("id_ed25519", text)
        self.assertNotIn("cat $HOME/.pi/agent", text)
        self.assertIn("never prints or records OAuth device codes", text)

    def test_smoke_requires_same_run_tool_and_behavior(self):
        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("--mode json --approve --no-session --tools read,grep,find,ls", text)
        self.assertIn('tool_execution_start', text)
        self.assertIn('tool_execution_end', text)
        self.assertIn('agent_end', text)
        self.assertIn('ANDROID_RUNTIME_SMOKE=PASS', text)
        self.assertIn("proof_level=live-agent-tool-behavior", text)

    def test_writing_sprint_isolated_and_proved(self):
        text = (ROOT / "tooling/profiles/android/AgentSwitchboard-Android.sh").read_text()
        self.assertIn("writing sprint refuses main", text)
        self.assertIn("git -C \"$REPO_ROOT\" diff --check", text)
        self.assertIn("git -C \"$REPO_ROOT\" ls-remote origin", text)
        self.assertIn('gh pr view "$branch"', text)
        self.assertIn("ANDROID_RUNTIME_SPRINT=COMPLETE", text)
        self.assertIn("proof_level=live-agent-repository-mutation", text)
        self.assertIn("timeout 1800", text)

    def test_project_settings_are_minimal(self):
        settings = json.loads((ROOT / ".pi/settings.json").read_text())
        self.assertFalse(settings["enableInstallTelemetry"])
        self.assertEqual(settings["skills"], ["../.ai/skills"])
        self.assertEqual(settings["packages"], [])
        self.assertEqual(settings["extensions"], [])

    def test_android_profile_registration_is_honest(self):
        registry = json.loads((ROOT / ".ai/harness/device-profile-registry.json").read_text())
        android = next(p for p in registry["profiles"] if p["profileId"] == "android")
        self.assertEqual(android["status"], "implemented-runtime-unproved")
        self.assertEqual(android["frontend"], "termux")
        self.assertEqual(android["canonicalSourcePath"], "Start-AgentSwitchboard-Android.sh")
        self.assertEqual(android["installedPath"], "$PREFIX/bin/agentswitchboard-android")
        self.assertIn("does not prove", registry["proofCeiling"])

    def test_proof_sprint_task_is_bounded(self):
        text = (ROOT / "tooling/profiles/android/runtime-proof-sprint.prompt.md").read_text()
        self.assertIn("documentation only", text)
        self.assertIn("docs/workstation/android-command-transport.md", text)
        self.assertIn("git diff --check", text)
        self.assertIn("docs(android): add cross-device command transport guide", text)
        self.assertIn("do not merge", text.lower())

if __name__ == "__main__":
    unittest.main()
