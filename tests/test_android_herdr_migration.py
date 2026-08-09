#!/usr/bin/env python3
"""Contracts for proof-first Android Herdr migration."""
import json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BASE=ROOT/'tooling/profiles/android/harness/herdr'
def tracked(path):
    target=ROOT/path; assert target.is_file(),f'missing: {path}'; r=subprocess.run(['git','-C',str(ROOT),'ls-files','--error-unmatch','--',path],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); assert r.returncode==0,f'not tracked: {path}'; return target
def main():
    m=json.loads(tracked('tooling/profiles/android/harness/herdr/manifest.json').read_text(encoding='utf-8')); assert m['status']=='experimental-unproved' and m['currentRuntime']['multiplexer']=='tmux'; assert m['candidate']['termuxAndroid']=='not-officially-claimed'; assert m['candidate']['cargoInstallClaim']=='not-used-until-upstream-documents-it'; assert m['candidate']['installationReviewDecision']=='BLOCKED'; assert m['candidate']['nativeAndroidSourceBuildDecision']=='BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK'; assert m['candidate']['linuxMuslPrebuiltProbeDecision']=='EXECUTION_PROBE_APPROVED_NO_INSTALL'; assert m['candidate']['boundedForegroundServerProbeDecision']=='BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL'; assert m['candidate']['serverStartProbeNextGate']=='exact-device-foreground-server-start-stop'; assert 'linux-aarch64' in m['candidate']['officialStablePlatforms']; required={'termux-environment-observed','herdr-installation-method-reviewed','source-bound-runtime-compatibility-reviewed','exact-device-prebuilt-execution-identity-observed','source-bound-foreground-server-start-reviewed','foreground-server-start-status-stop-observed','client-attach-observed','detach-reattach-observed','agent-state-observed','android-background-survival-observed','bounded-agent-sprint-observed'}; assert required<=set(m['gates']); assert 'Do not replace tmux' in m['promotionRule']
    for path in m['components'].values(): tracked(path)
    probe=tracked('tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh').read_text(encoding='utf-8')
    for token in ('KEEP_TMUX_HERDR_NOT_INSTALLED','KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY','HERDR_BINARY_CANDIDATE_ONLY','proof_level=binary-readiness-only','live-server-detach-reattach-and-agent-state-proof'): assert token in probe
    for forbidden in ('device_config put','max_phantom_processes','curl -fsSL https://herdr.dev/install.sh | sh','cargo install herdr'): assert forbidden not in probe
    wrapper=tracked('Test-AgentSwitchboard-Android-Herdr.sh'); r=subprocess.run(['bash',str(wrapper),'contract'],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr and 'HERDR_MIGRATION_CONTRACT=PASS' in r.stdout and 'CANONICAL_ANDROID_MULTIPLEXER=tmux' in r.stdout
    for rel,marker in ((BASE/'Probe-HerdrPrebuiltCompatibility.py','HERDR_PREBUILT_COMPATIBILITY_CONTRACT=PASS'),(BASE/'Probe-HerdrServerStart.py','HERDR_SERVER_START_CONTRACT=PASS')):
        r=subprocess.run(['python',str(rel),'contract'],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr and marker in r.stdout
    guide=tracked('docs/workstation/android-herdr-migration.md').read_text(encoding='utf-8')
    for token in ('experimental candidate','Linux `aarch64`','does **not** currently claim Android/Termux support','Do **not** uninstall tmux','bash Test-AgentSwitchboard-Android-Herdr.sh evidence','same-device','herdr server','bounded-client-attach-review','Proof ceiling'): assert token in guide,token
    print('PASS: Android Herdr migration contracts')
if __name__=='__main__': main()
