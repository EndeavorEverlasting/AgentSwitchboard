#!/usr/bin/env python3
"""Contracts for the Android Herdr bounded foreground server-start review."""
from __future__ import annotations
import json, os, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BASE=ROOT/"tooling/profiles/android/harness/herdr"; SOURCE=BASE/"upstream-server-start-source.json"; BUILDER=BASE/"Build-HerdrServerStartReview.py"; PROBE=BASE/"Probe-HerdrServerStart.py"; STATUS=BASE/"Get-HerdrHarnessStatus.py"; READINESS=BASE/"fixtures/herdr-not-installed.fixture.env"; PREBUILT=BASE/"fixtures/herdr-prebuilt-exec-pass.fixture.env"; INSTALL=BASE/"Build-HerdrInstallReview.py"
def run(args:list[str],env:dict[str,str]|None=None)->subprocess.CompletedProcess[str]: return subprocess.run(args,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=False)
def main()->None:
    src=json.loads(SOURCE.read_text(encoding="utf-8")); assert src["schema"]=="agentswitchboard.android-herdr-server-start-source.v1"; assert src["source"]["releaseCommit"]=="346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"; assert src["probe"]["decision"]=="BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL"; assert src["probe"]["launchCommand"]==["herdr","server"]; assert src["probe"]["statusCommand"]==["herdr","status","server","--json"]; assert src["probe"]["stopCommand"]==["herdr","server","stop"]; assert "run bare `herdr` auto-detect launch" in src["probe"]["forbiddenActions"]; assert src["migrationDecision"]=="KEEP_TMUX"
    with tempfile.TemporaryDirectory() as td:
        td=Path(td); review=td/"server-review.md"; r=run([sys.executable,str(BUILDER),"--output",str(review)]); assert r.returncode==0,r.stderr; text=review.read_text(encoding="utf-8")
        for token in ("Status: BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL","Launch command: `herdr server`","Status command: `herdr status server --json`","Stop command: `herdr server stop`","run bare `herdr` auto-detect launch","Next gate on PASS: bounded-client-attach-review"): assert token in text
        assert "DECISION=BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL" in r.stdout and "MIGRATION_DECISION=KEEP_TMUX" in r.stdout
        install=td/"install.md"; r=run([sys.executable,str(INSTALL),"--output",str(install)]); assert r.returncode==0,r.stderr; r=run([sys.executable,str(STATUS),"--state-root",str(td/"isolated"),"--evidence",str(READINESS),"--install-review",str(install),"--prebuilt-evidence",str(PREBUILT),"--format","json"]); assert r.returncode==0,r.stderr; s=json.loads(r.stdout); assert s["status"]=="prebuilt-execution-identity-proven-server-unproved"; assert s["nextGate"]=="bounded-server-start-review"; assert s["nextCommand"].endswith("Build-HerdrServerStartReview.py --write"); assert s["prebuiltEvidenceSource"]==str(PREBUILT)
    r=run([sys.executable,str(PROBE),"contract"]); assert r.returncode==0,r.stderr and "HERDR_SERVER_START_CONTRACT=PASS" in r.stdout and "DECISION=BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL" in r.stdout
    env=os.environ.copy(); env["PREFIX"]=""; r=run([sys.executable,str(PROBE),"evidence","--prebuilt-evidence",str(PREBUILT)],env=env); assert r.returncode!=0 and "no download or server start was attempted" in r.stderr
    source=PROBE.read_text(encoding="utf-8")
    for token in ('subprocess.Popen(','[str(candidate),"server"]','"status","server","--json"','"server","stop"','"HERDR_SOCKET_PATH"','start_new_session=True','force_cleanup','version_check = false','manifest_check = false','XDG_CONFIG_HOME','XDG_STATE_HOME'): assert token in source
    for forbidden in ("cargo install herdr","device_config put","max_phantom_processes","PREFIX/bin"): assert forbidden not in source
    print("PASS: Android Herdr bounded server-start review")
if __name__=="__main__": main()
