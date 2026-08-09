#!/usr/bin/env python3
"""Dependency-free completeness contracts for the Android Herdr migration harness."""
import json, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BASE=ROOT/'tooling/profiles/android/harness/herdr'
def tracked(path):
    target=ROOT/path; assert target.is_file(), f'missing: {path}'; r=subprocess.run(['git','-C',str(ROOT),'ls-files','--error-unmatch','--',path],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); assert r.returncode==0, f'not tracked: {path}'; return target
def load(path): return json.loads(tracked(path).read_text(encoding='utf-8'))
def main():
    m=load('tooling/profiles/android/harness/herdr/manifest.json'); c=load('tooling/profiles/android/harness/herdr/codebase-map.json'); a=load('tooling/profiles/android/harness/herdr/artifact-registry.json'); w=load('tooling/profiles/android/harness/herdr/workflows/workflow-specs.json')
    assert m['harnessId']=='agentswitchboard.android-herdr-migration-probe.v1' and m['status']=='experimental-unproved' and m['currentRuntime']['multiplexer']=='tmux' and m['liveEvidencePolicy']=='local-untracked-sanitized'
    for path in m['components'].values(): tracked(path)
    assert {x['workflowId'] for x in w['workflows']}=={'task-intake','reviewed-installation','validate-before-commit','failure-recovery','handoff'}
    assert c['entrypoints']['buildInstallReview'].endswith('Build-HerdrInstallReview.py --write')
    ids={x['artifactId'] for x in a['artifacts']}; assert {'herdr-readiness-evidence','herdr-harness-status-json','herdr-harness-status-markdown','herdr-install-review','herdr-validation-receipt','herdr-runtime-proof'}<=ids; assert a['policy']=='generated-local-untracked'
    fixture=tracked('tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env'); assert 'migration_decision=KEEP_TMUX_HERDR_NOT_INSTALLED' in fixture.read_text()
    r=subprocess.run(['python',str(BASE/'Get-HerdrHarnessStatus.py'),'--evidence',str(fixture),'--format','json'],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr; s=json.loads(r.stdout); assert s['status']=='blocked-herdr-not-installed' and s['canonicalMultiplexer']=='tmux' and s['nextGate']=='reviewed-installation-method' and s['nextCommand'].endswith('Build-HerdrInstallReview.py --write')
    with tempfile.TemporaryDirectory() as d:
        out=Path(d)/'review.md'; r=subprocess.run(['python',str(BASE/'Build-HerdrInstallReview.py'),'--output',str(out)],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr; text=out.read_text();
        for token in ('Status: PENDING','Exact release/tag/commit:','Explicit Android/Termux support claim','tmux remains installed','Decision: APPROVED / REJECTED / BLOCKED / PENDING','Exact installation command, only when APPROVED:'): assert token in text
    skill=tracked('.ai/skills/android-herdr-migration/SKILL.md').read_text();
    for token in ('id: android-herdr-migration','KEEP_TMUX_HERDR_NOT_INSTALLED','Build-HerdrInstallReview.py --write','same-device evidence','Forbidden scope'): assert token in skill
    report=tracked('tooling/profiles/android/harness/herdr/operator-report.template.md').read_text();
    for token in ('## Working','## Broken or blocked','## Missing / unproved','## Exact next command','## Proof ceiling'): assert token in report
    for hook in (m['components']['preCommitHook'],m['components']['prePushHook']):
        text=tracked(hook).read_text(); assert 'test_android_herdr_harness_completeness.py' in text and 'diff --check' in text
    ci=tracked('.github/workflows/android-herdr-migration.yml').read_text();
    for token in ('Test-AndroidHerdrHarnessCompleteness.ps1','test_android_herdr_harness_completeness.py','Build-HerdrInstallReview.py','Get-HerdrHarnessStatus.py','Invoke-HerdrHarnessPreCommit.sh'): assert token in ci
    print('PASS: Android Herdr operational harness completeness')
if __name__=='__main__': main()
