#!/usr/bin/env python3
"""Dependency-free completeness contracts for the Android Herdr migration harness."""
import json, subprocess, sys, tempfile
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

def run(*args):
    return subprocess.run([sys.executable,*map(str,args)],cwd=ROOT,text=True,capture_output=True)

def main():
    m=load('tooling/profiles/android/harness/herdr/manifest.json')
    c=load('tooling/profiles/android/harness/herdr/codebase-map.json')
    a=load('tooling/profiles/android/harness/herdr/artifact-registry.json')
    w=load('tooling/profiles/android/harness/herdr/workflows/workflow-specs.json')
    u=load('tooling/profiles/android/harness/herdr/upstream-installation-source.json')
    rc=load('tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json')
    ss=load('tooling/profiles/android/harness/herdr/upstream-server-start-source.json')

    assert m['harnessId']=='agentswitchboard.android-herdr-migration-probe.v1'
    assert m['status']=='experimental-unproved'
    assert m['currentRuntime']['multiplexer']=='tmux'
    assert m['liveEvidencePolicy']=='local-untracked-sanitized'
    assert m['candidate']['installationReviewDecision']=='BLOCKED'
    assert m['candidate']['nativeAndroidSourceBuildDecision']=='BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK'
    assert m['candidate']['linuxMuslPrebuiltProbeDecision']=='EXECUTION_PROBE_APPROVED_NO_INSTALL'
    assert m['candidate']['boundedForegroundServerProbeDecision']=='BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL'
    for path in m['components'].values(): tracked(path)

    workflow_ids={x['workflowId'] for x in w['workflows']}
    assert workflow_ids=={'task-intake','reviewed-installation','runtime-compatibility-review','bounded-server-start-review','validate-before-commit','failure-recovery','handoff'}
    assert c['entrypoints']['buildInstallReview'].endswith('Build-HerdrInstallReview.py --write')
    assert c['entrypoints']['buildCompatibilityReview'].endswith('Build-HerdrCompatibilityReview.py --write')
    assert c['entrypoints']['buildServerStartReview'].endswith('Build-HerdrServerStartReview.py --write')
    assert c['entrypoints']['serverStartContract'].endswith('Probe-HerdrServerStart.py contract')
    assert c['entrypoints']['serverStartEvidence'].endswith('Probe-HerdrServerStart.py evidence')
    assert c['configuration']['upstreamServerStartSource']==m['components']['upstreamServerStartSource']

    ids={x['artifactId'] for x in a['artifacts']}
    required_ids={'herdr-readiness-evidence','herdr-harness-status-json','herdr-harness-status-markdown','herdr-install-review','herdr-compatibility-review','herdr-prebuilt-exec-evidence','herdr-server-start-review','herdr-server-start-evidence','herdr-validation-receipt','herdr-runtime-proof'}
    assert required_ids<=ids
    assert a['policy']=='generated-local-untracked' and '--state-root' in a['validatorIsolation']
    sources={x['sourceId']:x['path'] for x in a['trackedSources']}
    assert sources['herdr-upstream-installation-source']==m['components']['upstreamInstallationSource']
    assert sources['herdr-upstream-runtime-compatibility']==m['components']['upstreamRuntimeCompatibility']
    assert sources['herdr-upstream-server-start-source']==m['components']['upstreamServerStartSource']

    assert u['source']['releaseTag']=='v0.8.0' and u['candidate']['decision']=='BLOCKED' and u['candidate']['installCommand'] is None
    assert rc['source']['releaseCommit']=='346411fa21afd297f5ed3b3fa56f9e3fbf7654b7'
    assert rc['reviewDecision']=='EXECUTION_PROBE_APPROVED_NO_INSTALL' and rc['migrationDecision']=='KEEP_TMUX'
    assert ss['source']['releaseCommit']==rc['source']['releaseCommit']
    assert ss['source']['artifactSha256']=='f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87'
    assert ss['probe']['decision']=='BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL'
    assert ss['probe']['launchCommand']==['herdr','server']
    assert ss['probe']['statusCommand']==['herdr','status','server','--json']
    assert ss['probe']['stopCommand']==['herdr','server','stop']
    assert ss['migrationDecision']=='KEEP_TMUX'

    tracked('tooling/profiles/android/harness/herdr/fixtures/herdr-not-installed.fixture.env')
    tracked(m['components']['prebuiltPassFixture'])

    for component, marker in (
        ('statusStateIsolationTest','PASS: Android Herdr status state-root isolation'),
        ('serverStartReviewTest','PASS: Android Herdr bounded server-start review'),
    ):
        r=run(tracked(m['components'][component]))
        assert r.returncode==0,r.stderr
        assert marker in r.stdout

    with tempfile.TemporaryDirectory() as d:
        d=Path(d)
        compat=d/'compat.md'
        r=run(BASE/'Build-HerdrCompatibilityReview.py','--output',compat)
        assert r.returncode==0,r.stderr
        assert 'Status: EXECUTION_PROBE_APPROVED_NO_INSTALL' in compat.read_text(encoding='utf-8')

        server_review=d/'server.md'
        r=run(BASE/'Build-HerdrServerStartReview.py','--output',server_review)
        assert r.returncode==0,r.stderr
        text=server_review.read_text(encoding='utf-8')
        for token in ('Status: BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL','Launch command: `herdr server`','Status command: `herdr status server --json`','Stop command: `herdr server stop`','Next gate on PASS: bounded-client-attach-review'):
            assert token in text

    prebuilt_path=tracked(m['components']['prebuiltCompatibilityProbe'])
    prebuilt_source=prebuilt_path.read_text(encoding='utf-8')
    assert 'XDG_STATE_HOME' in prebuilt_source and 'def state_root()' in prebuilt_source
    server_probe=tracked(m['components']['serverStartProbe'])
    server_source=server_probe.read_text(encoding='utf-8')
    for token in ('[str(candidate),"server"]','"status","server","--json"','"server","stop"','"HERDR_SOCKET_PATH"','start_new_session=True','force_cleanup','version_check = false','manifest_check = false','XDG_CONFIG_HOME','XDG_STATE_HOME'):
        assert token in server_source
    for forbidden in ('cargo install herdr','device_config put','max_phantom_processes','PREFIX/bin'):
        assert forbidden not in server_source

    status_source=tracked(m['components']['statusReporter']).read_text(encoding='utf-8')
    for token in ('--state-root','--prebuilt-evidence','XDG_STATE_HOME','bounded-server-start-review','Build-HerdrServerStartReview.py --write'):
        assert token in status_source

    for probe, marker in ((prebuilt_path,'HERDR_PREBUILT_COMPATIBILITY_CONTRACT=PASS'),(server_probe,'HERDR_SERVER_START_CONTRACT=PASS')):
        r=run(probe,'contract')
        assert r.returncode==0,r.stderr
        assert marker in r.stdout

    skill=tracked('.ai/skills/android-herdr-migration/SKILL.md').read_text(encoding='utf-8')
    for token in ('id: android-herdr-migration','Build-HerdrServerStartReview.py --write','Probe-HerdrServerStart.py evidence','bare `herdr`','same-device','Forbidden scope'):
        assert token in skill

    report=tracked('tooling/profiles/android/harness/herdr/operator-report.template.md').read_text(encoding='utf-8')
    for token in ('## Working','## Broken or blocked','## Missing / unproved','Prebuilt execution evidence','Server-start evidence','## Exact next command','## Proof ceiling'):
        assert token in report

    precommit=tracked(m['components']['preCommitHook']).read_text(encoding='utf-8')
    for token in ('test_android_herdr_server_start_review.py','Probe-HerdrServerStart.py contract','test_android_herdr_harness_completeness.py','diff --check'):
        assert token in precommit
    prepush=tracked(m['components']['prePushHook']).read_text(encoding='utf-8')
    assert 'Invoke-HerdrHarnessPreCommit.sh' in prepush and 'diff --check' in prepush and 'merge-base --is-ancestor' in prepush

    ci=tracked('.github/workflows/android-herdr-migration.yml').read_text(encoding='utf-8')
    for token in ('test_android_herdr_server_start_review.py','Probe-HerdrServerStart.py contract','Build-HerdrServerStartReview.py','herdr-prebuilt-exec-pass.fixture.env','Invoke-HerdrHarnessPreCommit.sh'):
        assert token in ci
    assert 'Probe-HerdrServerStart.py evidence' not in ci

    print('PASS: Android Herdr operational harness completeness')

if __name__=='__main__': main()
