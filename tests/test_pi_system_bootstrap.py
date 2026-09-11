from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PI = ROOT / "tooling" / "pi"
HARNESS = PI / "harness"
BOOTSTRAP = PI / "Install-AgentSwitchboardPiSystem.ps1"
CHILD = PI / "Invoke-AgentSwitchboardPiChild.ps1"
ENTRY = ROOT / "Bootstrap-Pi-SystemWide.cmd"
SETUP = ROOT / "tooling" / "profiles" / "windows" / "Setup-TechnicianAgentSwitchboard.ps1"
DISPATCH = ROOT / "Pull-And-Run-AgentSwitchboard.cmd"


class PiSystemBootstrapTests(unittest.TestCase):
    def test_owned_surfaces_exist_and_json_contracts_parse(self):
        paths = [
            BOOTSTRAP,
            CHILD,
            ENTRY,
            HARNESS / "system-bootstrap.contract.json",
            HARNESS / "child-agent-invocation.contract.json",
            HARNESS / "upstream-verification.json",
            HARNESS / "pi-adapter.registry.json",
            ROOT / "docs" / "harness" / "pi-system-bootstrap-and-child-agents.md",
        ]
        for path in paths:
            self.assertTrue(path.is_file(), str(path.relative_to(ROOT)))
        for name in (
            "system-bootstrap.contract.json",
            "child-agent-invocation.contract.json",
            "upstream-verification.json",
            "pi-adapter.registry.json",
        ):
            self.assertIsInstance(json.loads((HARNESS / name).read_text(encoding="utf-8-sig")), dict)

    def test_upstream_pin_uses_official_standalone_windows_assets(self):
        data = json.loads((HARNESS / "upstream-verification.json").read_text(encoding="utf-8-sig"))
        self.assertEqual("0.85.1", data["version"])
        self.assertEqual("v0.85.1", data["versionTag"])
        native = data["nativeRelease"]
        self.assertEqual("standalone-release", native["preferredWindowsDistribution"])
        self.assertFalse(native["systemBootstrap"]["packageManagerRequired"])
        self.assertFalse(native["systemBootstrap"]["nodeRuntimeRequired"])
        self.assertEqual(
            "002fa95b90d521245b9985d8f168caebc237ad56e7e30b319807dee1b2e17e1c",
            native["windows"]["x64"]["sha256"],
        )
        self.assertEqual(
            "b25e96fe64c9f41f75a924c0d36f395abb98d6c6fec0b78aaa0b86926f938bb4",
            native["windows"]["arm64"]["sha256"],
        )
        self.assertTrue(native["windows"]["x64"]["downloadUrl"].endswith("/v0.85.1/pi-windows-x64.zip"))
        self.assertTrue(data["programmaticModes"]["json"])
        self.assertTrue(data["programmaticModes"]["rpc"])
        self.assertEqual("strict LF-delimited JSONL", data["programmaticModes"]["rpcFraming"])

    def test_bootstrap_is_machine_owned_digest_checked_and_package_manager_free(self):
        text = BOOTSTRAP.read_text(encoding="utf-8-sig")
        lower = text.lower()
        for token in (
            "$env:programfiles",
            "agentswitchboard\\agents\\pi",
            "agentswitchboard\\bin",
            "get-filehash",
            "sha256",
            "expand-archive",
            "pi_release_sha256_mismatch",
            "git_bash_required",
            "agentswitchboard-runtime.json",
            "pi_launcher_path_already_owned",
            "pi_install_directory_already_owned",
            "configurationmutation = 'none'",
            "authenticationmutation = 'none'",
            "projecttrustmutation = 'none'",
        ):
            self.assertIn(token, lower)
        for forbidden in (
            "npm install",
            "choco install",
            "scoop install",
            "winget install",
            "invoke-expression",
            "api_key",
            "api-key",
        ):
            self.assertNotIn(forbidden, lower)
        self.assertIn("@('package.json','README.md','docs','node_modules')", text)
        self.assertIn("Get-PiVersion -Path $launcherPath", text)
        self.assertIn("$extension -in @('.cmd','.bat')", text)

    def test_system_bootstrap_is_reachable_through_existing_dispatcher(self):
        setup = SETUP.read_text(encoding="utf-8-sig")
        dispatch = DISPATCH.read_text(encoding="utf-8-sig")
        entry = ENTRY.read_text(encoding="utf-8-sig")
        self.assertIn("'bootstrap-pi'", setup)
        self.assertIn("Install-AgentSwitchboardPiSystem.ps1", setup)
        self.assertIn("& $piBootstrapPath -Mode Apply -RootPath $RepoRoot", setup)
        self.assertIn('"bootstrap-pi"', dispatch)
        self.assertIn('bootstrap-pi "%ROOT%." "%GIT_REF%"', entry)
        self.assertIn("Do not paste implementation fragments into an interactive PowerShell REPL", entry)
        self.assertNotIn("pwsh.exe -Command", entry)

    def test_child_adapter_uses_only_managed_runtime_and_bounded_role_tools(self):
        text = CHILD.read_text(encoding="utf-8-sig")
        lower = text.lower()
        self.assertIn('agentswitchboard\\agents\\pi\\$version\\pi.exe', lower)
        self.assertNotIn("get-command pi", lower)
        self.assertNotIn("apikey", lower)
        self.assertNotIn("api-key", lower)
        self.assertIn("'read,grep,find,ls'", text)
        self.assertIn("'read,grep,find,ls,write,edit,bash'", text)
        for token in (
            "--mode','json",
            "--no-session",
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
            "--no-approve",
            "agent_end",
            "completed-unvalidated",
            "coordinatorValidationRequired = $true",
            "PI_CHILD_READ_ONLY_MUTATION",
        ):
            self.assertIn(token, text)

    def test_writer_child_fails_closed_without_isolated_clean_nondefault_worktree(self):
        text = CHILD.read_text(encoding="utf-8-sig")
        self.assertIn("if ($branchBefore -in @('main','master',$defaultBranch))", text)
        self.assertIn("Writer child requires a clean worktree before provider invocation.", text)
        self.assertIn("Writer child requires an isolated linked Git worktree", text)
        self.assertIn("--git-common-dir", text)
        self.assertIn("--git-dir", text)

    def test_child_contract_avoids_pairwise_configuration_and_marks_sensitive_raw_events(self):
        contract = json.loads((HARNESS / "child-agent-invocation.contract.json").read_text(encoding="utf-8-sig"))
        self.assertFalse(contract["architecture"]["pairwiseAgentConfigurationRequired"])
        self.assertEqual("json-subprocess", contract["piTransport"]["mode"])
        self.assertTrue(contract["piTransport"]["upstreamRpcAvailable"])
        self.assertTrue(contract["writeModes"]["writer"]["isolatedWorktreeRequired"])
        self.assertEqual(1, contract["writeModes"]["writer"]["writersPerMutationSurface"])
        self.assertFalse(contract["resultEnvelope"]["rawPromptIncludedInResultEnvelope"])
        self.assertTrue(contract["resultEnvelope"]["rawEventMayContainPrompt"])
        self.assertFalse(contract["resultEnvelope"]["rawEventsTracked"])


if __name__ == "__main__":
    unittest.main()
