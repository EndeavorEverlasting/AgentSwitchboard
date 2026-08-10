from __future__ import annotations
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
H = ROOT / 'tooling' / 'harness' / 'operational' / 'opencode-lsp-setup'
MANDATORY = {
    'manifest.json',
    'codebase-map.json',
    'workflows.json',
    'artifact-registry.json',
    'operator-report.template.md',
    'Invoke-OpenCodeLspWorkstationSetup.ps1',
    'hooks/Invoke-OpenCodeLspPreCommit.ps1',
    'hooks/Invoke-OpenCodeLspPrePush.ps1',
}


class OpenCodeLspHarnessTests(unittest.TestCase):
    def test_mandatory_files_exist(self):
        self.assertEqual([], [p for p in sorted(MANDATORY) if not (H / p).is_file()])

    def test_json_contracts_parse(self):
        for p in ('manifest.json', 'codebase-map.json', 'workflows.json', 'artifact-registry.json'):
            self.assertIsInstance(json.loads((H / p).read_text(encoding='utf-8')), dict)

    def test_workflow_order_is_small_and_deterministic(self):
        data = json.loads((H / 'workflows.json').read_text(encoding='utf-8'))
        self.assertEqual(['intake', 'configure', 'failure-recovery', 'handoff'], data['order'])
        self.assertEqual(data['order'], [w['id'] for w in data['workflows']])

    def test_artifacts_are_local_and_untracked(self):
        data = json.loads((H / 'artifact-registry.json').read_text(encoding='utf-8'))
        self.assertFalse(data['tracked'])
        self.assertIn('%LOCALAPPDATA%', data['defaultRunRoot'])

    def test_runner_preserves_existing_config_and_free_model_is_launch_only(self):
        text = (H / 'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        lower = text.lower()
        for token in ('opencode_config', 'opencode/nemotron-3-ultra-free', 'opencode_v2_lsp_unavailable', 'localappdata', 'lsp=$true', 'free trial'):
            self.assertIn(token, lower)
        self.assertNotIn('Set-Content -LiteralPath $globalConfig', text)
        self.assertNotIn("model='opencode/nemotron-3-ultra-free'", text)

    def test_runner_has_no_destructive_git_or_secrets(self):
        text = (H / 'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8').lower()
        for token in ('git reset', 'git clean', 'git stash', 'push --force', 'apikey', 'password='):
            self.assertNotIn(token, text)

    def test_generic_harness_routes_focused_harness(self):
        text = (ROOT / 'tooling/harness/operational/manifest.json').read_text(encoding='utf-8')
        self.assertIn('opencode-lsp-setup/manifest.json', text)

    def test_skill_is_bounded_for_weak_agents(self):
        text = (ROOT / '.ai/skills/opencode-lsp-workstation-setup/SKILL.md').read_text(encoding='utf-8')
        for token in ('## Trigger', '## Inputs', '## Procedure', '## Outputs', '## Deterministic validation', '## Forbidden scope', '## Stop and escalate', '## Proof ceiling'):
            self.assertIn(token, text)

    def test_ci_and_hooks_route_validation(self):
        ci = (ROOT / '.github/workflows/opencode-lsp-harness.yml').read_text(encoding='utf-8')
        self.assertIn('tests.test_opencode_lsp_harness', ci)
        self.assertIn('Test-OpenCodeLspHarness.ps1', ci)
        self.assertIn('git diff --check', ci)
        for p in ('Invoke-OpenCodeLspPreCommit.ps1', 'Invoke-OpenCodeLspPrePush.ps1'):
            self.assertIn('Test-OpenCodeLspHarness.cmd', (H / 'hooks' / p).read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
