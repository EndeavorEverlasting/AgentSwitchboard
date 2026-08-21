from __future__ import annotations
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
H = ROOT / 'tooling' / 'harness' / 'operational' / 'opencode-lsp-setup'
MANDATORY = {'manifest.json','codebase-map.json','workflows.json','artifact-registry.json','operator-report.template.md','Recover-AgentSwitchboardCheckout.ps1','Recover-OpenCodeRuntime.ps1','Resolve-AgentSwitchboardCheckout.ps1','Invoke-OpenCodeLspWorkstationSetup.ps1','hooks/Invoke-OpenCodeLspPreCommit.ps1','hooks/Invoke-OpenCodeLspPrePush.ps1'}

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
        self.assertEqual(2,data['schemaVersion'])
        for workflow in data['workflows']:
            spec=ROOT/workflow['specPath']; self.assertTrue(spec.is_file(),workflow['specPath'])
            parsed=json.loads(spec.read_text(encoding='utf-8')); self.assertEqual(workflow['id'],parsed['workflowId'])
            for key in ('trigger','inputs','outputs','dependencies','validator','failurePolicy','proofCeiling','handoff'):
                self.assertTrue(parsed.get(key),f"{workflow['id']} missing {key}")
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
    def test_runner_anchors_origin_and_derives_model_provider(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        self.assertIn("$canonicalOriginPattern = '^(?:https://github\\.com/|git@github\\.com:|ssh://git@github\\.com/|git://github\\.com/)EndeavorEverlasting/AgentSwitchboard",text)
        self.assertIn("$modelSeparator = $ModelId.IndexOf('/')",text)
        self.assertIn('$modelProvider = $ModelId.Substring(0, $modelSeparator)',text)
        self.assertIn('& $openCode models $modelProvider',text)
    def test_runner_materializes_git_identity_lines_before_scalar_conversion(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        self.assertIn("$originLines = @(Invoke-GitLines @('remote','get-url','origin'))",text)
        self.assertIn('$origin = ([string]$originLines[0]).Trim()',text)
        self.assertIn("$headLines = @(Invoke-GitLines @('rev-parse','HEAD'))",text)
        self.assertIn('$head = ([string]$headLines[0]).Trim()',text)
        self.assertIn("Stop-Setup 'GIT_IDENTITY_OUTPUT_EMPTY'",text)
        self.assertNotIn("([string](Invoke-GitLines @('remote','get-url','origin'))[0])",text)
        self.assertNotIn("([string](Invoke-GitLines @('rev-parse','HEAD'))[0])",text)
    def test_powershell_regex_literals_match_real_runtime_values(self):
        runner=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        resolver=(H/'Resolve-AgentSwitchboardCheckout.ps1').read_text(encoding='utf-8')
        canonical='https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
        for name,text in (('runner',runner),('resolver',resolver)):
            line=next(line for line in text.splitlines() if line.strip().startswith('$canonicalOriginPattern = '))
            pattern=line.split("'",2)[1]
            self.assertIsNotNone(re.fullmatch(pattern,canonical),f'{name} rejected canonical HTTPS origin: {pattern!r}')
            self.assertIsNone(re.fullmatch(pattern,'https://github.example/EndeavorEverlasting/AgentSwitchboard.git'))
            catch_line=next(line for line in text.splitlines() if "$raw -match '" in line)
            catch_pattern=catch_line.split("-match '",1)[1].split("'",1)[0]
            match=re.fullmatch(catch_pattern,'WRONG_REPOSITORY|canonical origin rejected')
            self.assertIsNotNone(match,f'{name} failed to parse structured failure envelope: {catch_pattern!r}')
            self.assertEqual('WRONG_REPOSITORY',match.group(1))
        version_line=next(line for line in runner.splitlines() if '$version -match ' in line)
        version_pattern=version_line.split("-match '",1)[1].split("'",1)[0]
        self.assertIsNotNone(re.search(version_pattern,'2.4.1'))
        self.assertIsNotNone(re.search(version_pattern,' v2.0.0'))
        self.assertIsNone(re.search(version_pattern,'1.9.9'))
    def test_runner_preserves_prior_configure_evidence(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        self.assertIn('$preOwnedConfigureDirectory',text)
        self.assertIn("Get-ChildItem -LiteralPath $requestedConfigurationDirectory -Force",text)
        self.assertIn("Stop-Setup 'CONFIGURATION_DIRECTORY_ALREADY_OWNED'",text)
        self.assertLess(text.index("if ($preOwnedConfigureDirectory) { Stop-Setup 'CONFIGURATION_DIRECTORY_ALREADY_OWNED'"), text.index("if ($env:OS -ne 'Windows_NT')"))
    def test_runner_has_no_destructive_git_or_secret_persistence(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8').lower()
        for token in ('git reset','git clean','git stash','push --force','apikey','password='):
            self.assertNotIn(token,text)
        self.assertIn('inheritedinlineconfigcontentspersisted = $false',text)
    def test_failure_evidence_contract_exists(self):
        text=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        for token in ("status = 'failed'",'failureCode = $failureCode','Set-Content -LiteralPath $receiptPath','Set-Content -LiteralPath $reportPath','Write-Host "FAILURE_CODE=$failureCode"','Write-Host "FAILURE_MESSAGE=$failureMessage"','Write-Host "NEXT_COMMAND=$nextCommand"'):
            self.assertIn(token,text)
        self.assertLess(text.index("$null = New-Item -ItemType Directory -Path $OutputDirectory"), text.index("if ($preOwnedConfigureDirectory) { Stop-Setup"))
    def test_wrong_repository_routes_to_fresh_checkout_recovery(self):
        runner=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        router=(H/'Recover-AgentSwitchboardCheckout.ps1').read_text(encoding='utf-8')
        manifest=json.loads((H/'manifest.json').read_text(encoding='utf-8'))
        self.assertIn("$checkoutRecoveryRouterPath = Join-Path $PSScriptRoot 'Recover-AgentSwitchboardCheckout.ps1'",runner)
        self.assertIn("if ($failureCode -eq 'WRONG_REPOSITORY')",runner)
        self.assertIn("-PreferredPath ' + (ConvertTo-PsLiteral $RepoPath)",runner)
        self.assertIn('git ls-remote --symref $canonicalUrl HEAD',router)
        self.assertIn('refs/heads/$defaultBranch',router)
        self.assertIn('& $resolverPath -PreferredPath $PreferredPath -ExpectedBranch $defaultBranch -ExpectedHead $expectedHead',router)
        self.assertNotIn('git rev-parse --show-toplevel',runner[runner.index("if ($failureCode -eq 'WRONG_REPOSITORY')"):runner.index("elseif ($failureCode -eq 'OPENCODE_NOT_FOUND'")])
        self.assertEqual('tooling/harness/operational/opencode-lsp-setup/Recover-AgentSwitchboardCheckout.ps1',manifest['entrypoints']['checkoutRecoveryRouter'])
        for forbidden in ('git reset','git clean','git stash','push --force','remove-item'):
            self.assertNotIn(forbidden,router.lower())
    def test_opencode_not_found_advances_through_runtime_recovery(self):
        runner=(H/'Invoke-OpenCodeLspWorkstationSetup.ps1').read_text(encoding='utf-8')
        router=(H/'Recover-OpenCodeRuntime.ps1').read_text(encoding='utf-8')
        manifest=json.loads((H/'manifest.json').read_text(encoding='utf-8'))
        workflow=json.loads((H/'workflows/failure-recovery.workflow.json').read_text(encoding='utf-8'))
        self.assertIn("$runtimeRecoveryRouterPath = Join-Path $PSScriptRoot 'Recover-OpenCodeRuntime.ps1'",runner)
        self.assertIn("Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\\bin\\opencode.cmd'",runner)
        self.assertIn("elseif ($failureCode -eq 'OPENCODE_NOT_FOUND' -and $repoResolved)",runner)
        block=runner[runner.index("elseif ($failureCode -eq 'OPENCODE_NOT_FOUND'"):runner.index('elseif ($repoResolved)')]
        self.assertIn('$runtimeRecoveryRouterPath',block)
        self.assertNotIn('-Mode Inspect',block)
        self.assertEqual('tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1',manifest['entrypoints']['runtimeRecoveryRouter'])
        self.assertFalse(manifest['runtimeRecovery']['sameStateRetryAllowed'])
        for token in ('Repair-Technician-Command-Shims.cmd','AGENT_SWITCHBOARD_NO_PAUSE','AgentSwitchboard\\bin\\opencode.cmd','-Mode Inspect','exit $LASTEXITCODE'):
            self.assertIn(token,router)
        for forbidden in ('git reset','git clean','git stash','push --force','remove-item'):
            self.assertNotIn(forbidden,router.lower())
        workflow_text=' '.join(workflow['steps']).lower() + ' ' + workflow['handoff'].lower()
        self.assertIn('never emit the same failing gate as its own next action',workflow_text)
        self.assertIn('same-state retry commands are insufficient',workflow_text)
    def test_python_fallback_and_hooks_are_fail_closed(self):
        cmd=(ROOT/'Test-OpenCodeLspHarness.cmd').read_text(encoding='utf-8')
        self.assertIn('where pwsh.exe >nul 2>nul',cmd)
        self.assertIn('python.exe',cmd); self.assertIn('py.exe -3',cmd)
        self.assertIn('if not errorlevel 1 set "PY_KIND=python"',cmd)
        self.assertIn('if not errorlevel 1 set "PY_KIND=py"',cmd)
        self.assertLess(cmd.index('python.exe -c'),cmd.index('if not defined PY_KIND ('))
        pre=(H/'hooks/Invoke-OpenCodeLspPreCommit.ps1').read_text(encoding='utf-8')
        self.assertIn('--diff-filter=ACMRD',pre); self.assertIn('git -C $RootPath diff --quiet -- $path',pre)
        push=(H/'hooks/Invoke-OpenCodeLspPrePush.ps1').read_text(encoding='utf-8')
        self.assertIn('[Parameter(Mandatory=$true)][string]$BaseRef',push); self.assertIn('rev-parse --verify',push); self.assertNotIn("BaseRef='origin/main'",push)
    def test_cmd_avoids_trailing_backslash_quote_boundary(self):
        cmd=(ROOT/'Test-OpenCodeLspHarness.cmd').read_text(encoding='utf-8')
        self.assertEqual(2,cmd.count('-RootPath "%ROOT%."'))
        self.assertNotIn('-RootPath "%ROOT%"',cmd)
    def test_cmd_propagates_validator_failures(self):
        cmd=(ROOT/'Test-OpenCodeLspHarness.cmd').read_text(encoding='utf-8')
        self.assertIn('set "RESULT="',cmd)
        self.assertGreaterEqual(cmd.count('if defined RESULT goto :fail'),4)
        self.assertIn(':fail\npopd\nendlocal & exit /b %RESULT%',cmd)
        self.assertNotIn('(set "R=%ERRORLEVEL%"& popd & endlocal & exit /b %R%)',cmd)
    def test_canonical_routes_reach_focused_skill(self):
        self.assertIn('opencode-lsp-workstation-setup',(ROOT/'SKILLS.md').read_text(encoding='utf-8'))
        triggers=(ROOT/'TRIGGERS.md').read_text(encoding='utf-8'); self.assertIn('opencode.lsp-workstation-setup',triggers); self.assertIn('opencode-lsp-workstation-setup',triggers)
        registry=(ROOT/'tooling/harness/operational/workflow-registry.json').read_text(encoding='utf-8'); self.assertIn('opencode-lsp-workstation-setup/SKILL.md',registry); self.assertIn('opencode-lsp-setup/',registry)
    def test_skill_is_bounded_for_weak_agents(self):
        text=(ROOT/'.ai/skills/opencode-lsp-workstation-setup/SKILL.md').read_text(encoding='utf-8')
        for token in ('## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate','## Proof ceiling'):
            self.assertIn(token,text)
        self.assertLessEqual(len(text.encode('utf-8')),3000)
    def test_checkout_resolver_recovers_without_rewriting_hint(self):
        text=(H/'Resolve-AgentSwitchboardCheckout.ps1').read_text(encoding='utf-8'); lower=text.lower()
        for token in ('preferredpath','expectedbranch','expectedhead','bounded-existing-checkout','created-isolated-clone','worktree add --detach','remote_head_mismatch'):
            self.assertIn(token,lower)
        for forbidden in ('git reset','git clean','git stash','push --force','remove-item'):
            self.assertNotIn(forbidden,lower)
        artifacts=json.loads((H/'artifact-registry.json').read_text(encoding='utf-8'))
        ids={x['artifactId'] for x in artifacts['artifacts']}; self.assertTrue({'checkout-resolution-json','checkout-resolution-report'} <= ids)
    def test_ci_routes_focused_and_documentation_validation(self):
        ci=(ROOT/'.github/workflows/opencode-lsp-harness.yml').read_text(encoding='utf-8')
        for token in ('SKILLS.md','TRIGGERS.md','workflow-registry.json','tests.test_opencode_lsp_harness','Test-OpenCodeLspHarness.ps1','Test-AgentDocumentationContract.ps1','git diff --check','Windows CMD entrypoint','shell: cmd','run: Test-OpenCodeLspHarness.cmd'):
            self.assertIn(token,ci)

if __name__ == '__main__': unittest.main()
