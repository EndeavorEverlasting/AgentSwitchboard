import json, subprocess, sys, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
H=ROOT/'tooling/code-search/harness'

def load(p): return json.loads(p.read_text(encoding='utf-8'))

class CodeSearchHarness(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.manifest=load(H/'manifest.json'); cls.providers=load(H/'provider-registry.json'); cls.workflows=load(H/'workflow-registry.json'); cls.artifacts=load(H/'artifact-registry.json')
 def test_components_exist(self):
  for p in self.manifest['components'].values(): self.assertTrue((ROOT/p).exists(),p)
 def test_provider_registry_has_three_explicit_routes(self):
  ids={p['id'] for p in self.providers['providers']}; self.assertEqual(ids,{'github-api-code-search','zoekt-local','sourcegraph'})
 def test_github_cli_limitation_is_honest(self):
  p=next(x for x in self.providers['providers'] if x['id']=='github-api-code-search'); self.assertIn('legacy', ' '.join(p['limitations']).lower()); self.assertFalse(p['localIndexing'])
 def test_sourcegraph_not_claimed_free(self):
  p=next(x for x in self.providers['providers'] if x['id']=='sourcegraph'); self.assertIn('plan-or-trial',p['costClass']); self.assertEqual(p['status'],'explicit-opt-in-only')
 def test_zoekt_cost_is_not_handwaved(self):
  p=next(x for x in self.providers['providers'] if x['id']=='zoekt-local'); self.assertTrue(p['localIndexing']); self.assertIn('compute', ' '.join(p['limitations']).lower())
 def test_selector_prefers_github_when_probe_passes(self):
  cp=subprocess.run([sys.executable,str(ROOT/'tooling/code-search/Select-CodeSearchProvider.py'),'--capabilities',str(H/'fixtures/github-ready.json')],capture_output=True,text=True); self.assertEqual(cp.returncode,0); self.assertEqual(json.loads(cp.stdout)['provider'],'github-api-code-search')
 def test_selector_falls_back_to_existing_zoekt(self):
  cp=subprocess.run([sys.executable,str(ROOT/'tooling/code-search/Select-CodeSearchProvider.py'),'--capabilities',str(H/'fixtures/zoekt-fallback.json')],capture_output=True,text=True); self.assertEqual(cp.returncode,0); self.assertEqual(json.loads(cp.stdout)['provider'],'zoekt-local')
 def test_sourcegraph_requires_explicit_gates(self):
  cp=subprocess.run([sys.executable,str(ROOT/'tooling/code-search/Select-CodeSearchProvider.py'),'--capabilities',str(H/'fixtures/sourcegraph-explicit.json')],capture_output=True,text=True); self.assertEqual(cp.returncode,0); self.assertEqual(json.loads(cp.stdout)['provider'],'sourcegraph')
 def test_query_builder_uses_argv_not_shell(self):
  cp=subprocess.run([sys.executable,str(ROOT/'tooling/code-search/Search-Codebase.py'),'--provider','github-api-code-search','--repo','EndeavorEverlasting/AgentSwitchboard','--query','manifest','--dry-run'],capture_output=True,text=True,check=True); data=json.loads(cp.stdout); self.assertEqual(data['argv'][:3],['gh','search','code']); self.assertNotIn('shell',data)
 def test_workflows_complete(self):
  expected={'code-search-task-intake','code-search-provider-selection','code-search-query-execution','code-search-failure-recovery','code-search-handoff'}; actual=set()
  for w in self.workflows['workflows']:
   d=load(ROOT/w['spec']); actual.add(d['id']);
   for k in ('trigger','inputs','steps','outputs','failureHandling','proofCeiling'): self.assertTrue(d[k])
  self.assertEqual(actual,expected)
 def test_artifacts_untracked_and_secret_safe(self):
  self.assertFalse(self.artifacts['generatedEvidenceTracked']); self.assertIn('access tokens',self.artifacts['forbiddenTrackedEvidence'])
 def test_status_is_read_only_and_honest(self):
  cp=subprocess.run([sys.executable,str(ROOT/'tooling/code-search/Get-CodeSearchHarnessStatus.py'),'--no-write','--json'],capture_output=True,text=True,check=True); d=json.loads(cp.stdout); self.assertIn('providerCount',d); self.assertIn('unproved',d['proofCeiling'].lower())
 def test_no_dangerous_hook_install_or_secret_print(self):
  for p in (ROOT/'tooling/code-search/hooks').glob('*.ps1'):
   t=p.read_text(encoding='utf-8').lower(); self.assertNotIn('core.hookspath',t); self.assertNotIn('push --force',t); self.assertNotIn('src auth token',t)

if __name__=='__main__': unittest.main()
