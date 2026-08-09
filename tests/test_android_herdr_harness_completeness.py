#!/usr/bin/env python3
"""Dependency-free completeness contracts for the Android Herdr migration harness."""
import json, subprocess, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'tooling/profiles/android/harness/herdr'

def tracked(path):
    target=ROOT/path
    assert target.is_file(), f'missing: {path}'
    r=subprocess.run(['git','-C',str(ROOT),'ls-files','--error-unmatch','--',path],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    assert r.returncode==0, f'not tracked: {path}'
    return target

def load(path):
    return json.loads(tracked(path).read_text(encoding='utf-8'))

def main():
    m=load('tooling/profiles/android/harness/herdr/manifest.json')
    c=load('tooling/profiles/android/harness/herdr/codebase-map.json')
    a=load('tooling/profiles/android/harness/herdr/artifact-registry.json')
    w=load('tooling/profiles/android/harness/herdr/workflows/workflow-specs.json')
    u=load('tooling/profiles/android/harness/herdr/upstream-installation-source.json')

    assert m['harnessId']=='agentswitchboard.android-herdr-migration-probe.v1'
    assert m['status']=='experimental-unproved'
    assert m['currentRuntime']['multiplexer']=='tmux'
    assert m['liveEvidencePolicy']=='local-untracked-sanitized'
    assert m['candidate']['installationReviewDecision']=='BLOCKED'
    for path in m['components'].values():
        tracked(path)

    assert {x['workflowId'] for x in w['workflows']}=={'task-intake','reviewed-installation','validate-before-commit','failure-recovery','handoff'}
    assert c['entrypoints']['buildInstallReview'].endswith('Build-HerdrInstallReview.py --write')
    assert c['configuration']['upstreamInstallationSource']==m['components']['upstreamInstallationSource']

    ids={x['artifactId'] for x in a['artifacts']}
    assert {'herdr-readiness-evidence','herdr-harness-status-json','herdr-harness-status-markdown','herdr-install-review','herdr-validation-receipt','herdr-runtime-proof'}<=ids
    assert a['policy']=='generated-local-untracked'
    assert a['trackedSources'][0]['sourceId']=='herdr-upstream-installation-source'
    assert a['trackedSources'][0]['path']==m['components']['upstreamInstallationSource']

    assert u['source']['releaseTag']=='v0.8.0'
    assert u['androidTermuxSupport']=='not-stated'
    assert u['candidate']['decision']=='BLOCKED'
    assert u['candidate']['installCommand'] is None

    fixture=tracked('tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env')
    assert 'migration_decision=KEEP_TMUX_HERDR_NOT_INSTALLED' in fixture.read_text()
    r=subprocess.run(['python',str(BASE/'Get-HerdrHarnessStatus.py'),'--evidence',str(fixture),'--format','json'],cwd=ROOT,text=True,capture_output=True)
    assert r.returncode==0,r.stderr
    s=json.loads(r.stdout)
    assert s['status']=='blocked-herdr-not-installed'
    assert s['canonicalMultiplexer']=='tmux'
    assert s['nextGate']=='reviewed-installation-method'
    assert s['nextCommand'].endswith('Build-HerdrInstallReview.py --write')

    with tempfile.TemporaryDirectory() as d:
        out=Path(d)/'review.md'
        r=subprocess.run(['python',str(BASE/'Build-HerdrInstallReview.py'),'--output',str(out)],cwd=ROOT,text=True,capture_output=True)
        assert r.returncode==0,r.stderr
        text=out.read_text()
        for token in (
            'Status: BLOCKED',
            'Exact release/tag/commit: v0.8.0 / 346411fa21afd297f5ed3b3fa56f9e3fbf7654b7',
            'Explicit Android/Termux support claim: not-stated',
            'tmux remains installed and available for rollback: yes',
            'Decision: BLOCKED',
            'Exact installation command, only when APPROVED: none',
        ):
            assert token in text
        assert 'DECISION=BLOCKED' in r.stdout
        assert 'NEXT_GATE=prove-android-runtime-compatibility-or-obtain-explicit-upstream-support' in r.stdout

    skill=tracked('.ai/skills/android-herdr-migration/SKILL.md').read_text()
    for token in ('id: android-herdr-migration','KEEP_TMUX_HERDR_NOT_INSTALLED','Build-HerdrInstallReview.py --write','upstream-installation-source.json','same-device','Forbidden scope'):
        assert token in skill

    report=tracked('tooling/profiles/android/harness/herdr/operator-report.template.md').read_text()
    for token in ('## Working','## Broken or blocked','## Missing / unproved','## Exact next command','## Proof ceiling'):
        assert token in report

    precommit=tracked(m['components']['preCommitHook']).read_text()
    assert 'test_android_herdr_harness_completeness.py' in precommit
    assert 'test_android_herdr_install_review.py' in precommit
    assert 'diff --check' in precommit

    prepush=tracked(m['components']['prePushHook']).read_text()
    assert 'Invoke-HerdrHarnessPreCommit.sh' in prepush
    assert 'diff --check' in prepush
    assert 'merge-base --is-ancestor' in prepush

    ci=tracked('.github/workflows/android-herdr-migration.yml').read_text()
    for token in ('Test-AndroidHerdrHarnessCompleteness.ps1','test_android_herdr_harness_completeness.py','test_android_herdr_install_review.py','Build-HerdrInstallReview.py','Get-HerdrHarnessStatus.py','Invoke-HerdrHarnessPreCommit.sh'):
        assert token in ci

    print('PASS: Android Herdr operational harness completeness')

if __name__=='__main__':
    main()
