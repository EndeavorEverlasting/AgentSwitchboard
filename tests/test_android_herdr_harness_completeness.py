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
    rc=load('tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json')

    assert m['harnessId']=='agentswitchboard.android-herdr-migration-probe.v1'
    assert m['status']=='experimental-unproved'
    assert m['currentRuntime']['multiplexer']=='tmux'
    assert m['liveEvidencePolicy']=='local-untracked-sanitized'
    assert m['candidate']['installationReviewDecision']=='BLOCKED'
    assert m['candidate']['nativeAndroidSourceBuildDecision']=='BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK'
    assert m['candidate']['linuxMuslPrebuiltProbeDecision']=='EXECUTION_PROBE_APPROVED_NO_INSTALL'
    for path in m['components'].values(): tracked(path)

    assert {x['workflowId'] for x in w['workflows']}=={'task-intake','reviewed-installation','runtime-compatibility-review','validate-before-commit','failure-recovery','handoff'}
    assert c['entrypoints']['buildInstallReview'].endswith('Build-HerdrInstallReview.py --write')
    assert c['entrypoints']['buildCompatibilityReview'].endswith('Build-HerdrCompatibilityReview.py --write')
    assert c['entrypoints']['prebuiltCompatibilityEvidence'].endswith('Probe-HerdrPrebuiltCompatibility.py evidence')
    assert c['configuration']['upstreamInstallationSource']==m['components']['upstreamInstallationSource']
    assert c['configuration']['upstreamRuntimeCompatibility']==m['components']['upstreamRuntimeCompatibility']

    ids={x['artifactId'] for x in a['artifacts']}
    assert {'herdr-readiness-evidence','herdr-harness-status-json','herdr-harness-status-markdown','herdr-install-review','herdr-compatibility-review','herdr-prebuilt-exec-evidence','herdr-validation-receipt','herdr-runtime-proof'}<=ids
    assert a['policy']=='generated-local-untracked'
    sources={x['sourceId']:x['path'] for x in a['trackedSources']}
    assert sources['herdr-upstream-installation-source']==m['components']['upstreamInstallationSource']
    assert sources['herdr-upstream-runtime-compatibility']==m['components']['upstreamRuntimeCompatibility']

    assert u['source']['releaseTag']=='v0.8.0' and u['androidTermuxSupport']=='not-stated'
    assert u['candidate']['decision']=='BLOCKED' and u['candidate']['installCommand'] is None
    assert rc['source']['releaseCommit']=='346411fa21afd297f5ed3b3fa56f9e3fbf7654b7'
    assert rc['compatibility']['nativeAndroidSourceBuild']['decision']=='BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK'
    assert rc['compatibility']['linuxMuslPrebuiltOnTermux']['buildTarget']=='aarch64-unknown-linux-musl'
    assert rc['reviewDecision']=='EXECUTION_PROBE_APPROVED_NO_INSTALL' and rc['migrationDecision']=='KEEP_TMUX'

    fixture=tracked('tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env')
    r=subprocess.run(['python',str(BASE/'Get-HerdrHarnessStatus.py'),'--evidence',str(fixture),'--format','json'],cwd=ROOT,text=True,capture_output=True)
    assert r.returncode==0,r.stderr
    s=json.loads(r.stdout)
    assert s['status']=='blocked-herdr-not-installed' and s['nextGate']=='reviewed-installation-method'

    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        install=d/'install.md'
        r=subprocess.run(['python',str(BASE/'Build-HerdrInstallReview.py'),'--output',str(install)],cwd=ROOT,text=True,capture_output=True)
        assert r.returncode==0,r.stderr
        r=subprocess.run(['python',str(BASE/'Get-HerdrHarnessStatus.py'),'--evidence',str(fixture),'--install-review',str(install),'--format','json'],cwd=ROOT,text=True,capture_output=True)
        assert r.returncode==0,r.stderr
        s=json.loads(r.stdout)
        assert s['status']=='blocked-herdr-runtime-compatibility-unproved'
        assert s['nextGate']=='source-bound-runtime-compatibility-review'
        assert s['nextCommand'].endswith('Build-HerdrCompatibilityReview.py --write')

        compat=d/'compat.md'
        r=subprocess.run(['python',str(BASE/'Build-HerdrCompatibilityReview.py'),'--output',str(compat)],cwd=ROOT,text=True,capture_output=True)
        assert r.returncode==0,r.stderr
        text=compat.read_text(encoding='utf-8')
        for token in ('Status: EXECUTION_PROBE_APPROVED_NO_INSTALL','Release build target: aarch64-unknown-linux-musl','Decision: BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK','Installation authorized: no','Server startup authorized: no'):
            assert token in text

    r=subprocess.run(['python',str(BASE/'Probe-HerdrPrebuiltCompatibility.py'),'contract'],cwd=ROOT,text=True,capture_output=True)
    assert r.returncode==0,r.stderr and 'HERDR_PREBUILT_COMPATIBILITY_CONTRACT=PASS' in r.stdout

    skill=tracked('.ai/skills/android-herdr-migration/SKILL.md').read_text()
    for token in ('id: android-herdr-migration','KEEP_TMUX_HERDR_NOT_INSTALLED','Build-HerdrInstallReview.py --write','upstream-installation-source.json','same-device','Forbidden scope'):
        assert token in skill

    report=tracked('tooling/profiles/android/harness/herdr/operator-report.template.md').read_text()
    for token in ('## Working','## Broken or blocked','## Missing / unproved','## Exact next command','## Proof ceiling'): assert token in report

    precommit=tracked(m['components']['preCommitHook']).read_text()
    for token in ('test_android_herdr_harness_completeness.py','test_android_herdr_install_review.py','test_android_herdr_compatibility_review.py','Probe-HerdrPrebuiltCompatibility.py contract','diff --check'):
        assert token in precommit
    prepush=tracked(m['components']['prePushHook']).read_text()
    assert 'Invoke-HerdrHarnessPreCommit.sh' in prepush and 'diff --check' in prepush and 'merge-base --is-ancestor' in prepush

    ci=tracked('.github/workflows/android-herdr-migration.yml').read_text()
    for token in ('Test-AndroidHerdrHarnessCompleteness.ps1','test_android_herdr_compatibility_review.py','Build-HerdrCompatibilityReview.py','Probe-HerdrPrebuiltCompatibility.py contract','Get-HerdrHarnessStatus.py','Invoke-HerdrHarnessPreCommit.sh'):
        assert token in ci

    print('PASS: Android Herdr operational harness completeness')

if __name__=='__main__': main()
