from __future__ import annotations
import json
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
H = ROOT / 'tooling' / 'harness' / 'operational' / 'opencode-lsp-setup'
MANDATORY = {'manifest.json','codebase-map.json','workflows.json','artifact-registry.json','operator-report.template.md','Invoke-OpenCodeLspWorkstationSetup.ps1','hooks/Invoke-OpenCodeLspPreCommit.ps1','hooks/Invoke-OpenCodeLspPrePush.ps1'}

class OpenCodeLspHarnessTests(unittest.TestCase):
    def test_mandatory_files_exist(self):
        self.assertEqual([], [p for p in sorted(MANDATORY) if not (H / p).is_file()])
    def test_json_contracts_parse(self):
        for p in ('manifest.json','codebase-map.json','workflows.json','artifact-registry.json'):
            self.assertIsInstance(json.loads((H/p).read_text(encoding='utf-8')), dict)
    def test_workflow_order_is_small_and_deterministic(self):
        data=json.loads((H/'workflows.json').read_text(encoding='utf-8'))
        self.assertEqual(['intake','configure','failure-recovery','handoff'],data['order'])
        self.assertEqual(data['order'],[w['id'] for w in data['workflows']])
    def test_artifacts_are_immutable_local_and_untracked(self):
        data=json.loads((H/'artifact-registry.json').read_text(encoding='utf-8'))
        self.assertFalse(data['tracked']); self.assertTrue(data['configurationArtifactsImmutable']); self.assertIn('%LOCALAPPDATA%',data['defaultRunRoot'])
        ids={x['artifactId'] for x in data['artifacts']}; self.assertTrue({'lsp-overlay','launcher-script','launcher'} <= ids)
    def test_runner_preserves_config_and_verifies_exact_launchers(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8'); lower=text.lower()
        for token in ('opencode_config_content','opencode/nemotron-3-ultra-free','opencode_v2_lsp_unavailable','configurationdirectory','configuration_directory_already_owned','launcher_mismatch','localappdata','lsp=$true','free trial'):
            self.assertIn(token,lower)
        self.assertIn("if ([string]::IsNullOrWhiteSpace($env:OPENCODE_CONFIG))",text)
        self.assertIn("$effective[''lsp''] = $true",text)
        self.assertIn('Test-ExactLines',text)
        self.assertNotIn('Set-Content -LiteralPath $globalConfig',text)
    def test_runner_has_no_destructive_git_or_secret_persistence(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8').lower()
        for token in ('git reset','git clean','git stash','push --force','apikey','password='):
            self.assertNotIn(token,text)
        self.assertIn('inheritedinlineconfigcontentspersisted = $false',text)
    def test_failure_evidence_contract_exists(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        for token in ("status = 'failed'",'failureCode = $failureCode','Set-Content -LiteralPath $receiptPath','Set-Content -LiteralPath $reportPath'):
            self.assertIn(token,text)
        self.assertLess(text.index("$null = New-Item -ItemType Directory -Path $OutputDirectory"), text.index("if ($env:OS -ne 'Windows_NT')"))
    def test_python_fallback_and_hooks_are_fail_closed(self):
        cmd=(ROOT/'Test-OpenCodeLspHarness.cmd').read_text(encoding='utf-8')
        self.assertIn('python.exe',cmd); self.assertIn('py.exe -3',cmd)
        pre=(H/'hooks/Invoke-OpenCodeLspPreCommit.ps1').read_text(encoding='utf-8'); self.assertIn('--diff-filter=ACMRD',pre)
        push=(H/'hooks/Invoke-OpenCodeLspPrePush.ps1').read_text(encoding='utf-8')
        self.assertIn('[Parameter(Mandatory=$true)][string]$BaseRef',push); self.assertIn('rev-parse --verify',push); self.assertNotIn("BaseRef='origin/main'",push)
    def test_canonical_routes_reach_focused_skill(self):
        self.assertIn('opencode-lsp-workstation-setup',(ROOT/'SKILLS.md').read_text(encoding='utf-8'))
        triggers=(ROOT/'TRIGGERS.md').read_text(encoding='utf-8'); self.assertIn('opencode.lsp-workstation-setup',triggers); self.assertIn('opencode-lsp-workstation-setup',triggers)
        registry=(ROOT/'tooling/harness/operational/workflow-registry.json').read_text(encoding='utf-8'); self.assertIn('opencode-lsp-workstation-setup/SKILL.md',registry); self.assertIn('opencode-lsp-setup/',registry)
    def test_skill_is_bounded_for_weak_agents(self):
        text=(ROOT/'.ai/skills/opencode-lsp-workstation-setup/SKILL.md').read_text(encoding='utf-8')
        for token in ('## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate','## Proof ceiling'):
            self.assertIn(token,text)
    def test_ci_routes_focused_and_documentation_validation(self):
        ci=(ROOT/'.github/workflows/opencode-lsp-harness.yml').read_text(encoding='utf-8')
        for token in ('SKILLS.md','TRIGGERS.md','workflow-registry.json','tests.test_opencode_lsp_harness','Test-OpenCodeLspHarness.ps1','Test-AgentDocumentationContract.ps1','git diff --check'):
            self.assertIn(token,ci)

if __name__ == '__main__': unittest.main()
