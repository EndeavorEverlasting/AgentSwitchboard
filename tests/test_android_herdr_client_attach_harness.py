#!/usr/bin/env python3
"""Deterministic completeness/contract test for the bounded Herdr client-attach harness."""
from __future__ import annotations
import json, subprocess, sys, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"tooling/profiles/android/harness/herdr/client-attach"

def tracked(rel:str)->Path:
    p=ROOT/rel; assert p.is_file(), rel
    r=subprocess.run(["git","ls-files","--error-unmatch",rel],cwd=ROOT,text=True,capture_output=True)
    assert r.returncode==0, f"untracked: {rel}"
    return p

def main():
    manifest=json.loads(tracked("tooling/profiles/android/harness/herdr/client-attach/manifest.json").read_text())
    assert manifest["canonicalMultiplexer"]=="tmux"
    assert manifest["baseProof"]=="foreground-server-start-status-stop-only"
    assert manifest["currentGate"]=="source-bound-client-attach-review"
    for path in manifest["components"].values(): tracked(path)
    source=json.loads(tracked(manifest["components"]["upstreamSource"]).read_text())
    assert source["source"]["releaseTag"]=="v0.8.0"
    assert source["source"]["releaseCommit"]=="346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
    assert source["source"]["protocol"]==19
    assert source["reviewDecision"]=="BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL"
    assert source["fullAppTuiDecision"]=="BLOCKED_AUTODETECT_DAEMON_RACE"
    assert source["migrationDecision"]=="KEEP_TMUX"
    assert source["probe"]["readOnlyDiscoveryCommand"]==["herdr","pane","list"]
    assert source["probe"]["observerCommand"][:4]==["herdr","terminal","session","observe"]
    fixture=tracked(manifest["components"]["fixture"]).read_text()
    for token in ("schema=agentswitchboard.android-herdr-server-start.v1","server_lifecycle=PASS","status_running=yes","status_compatible=yes","forced_cleanup=no"): assert token in fixture
    probe=tracked(manifest["components"]["probe"])
    r=subprocess.run([sys.executable,str(probe),"contract"],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr
    assert "HERDR_CLIENT_ATTACH_CONTRACT=PASS" in r.stdout
    assert "FULL_APP_TUI_DECISION=BLOCKED_AUTODETECT_DAEMON_RACE" in r.stdout
    builder=tracked(manifest["components"]["reviewBuilder"])
    with tempfile.TemporaryDirectory() as td:
        out=Path(td)/"review.md"; r=subprocess.run([sys.executable,str(builder),"--output",str(out)],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr
        text=out.read_text()
        for token in ("BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL","BLOCKED_AUTODETECT_DAEMON_RACE","terminal session observe","KEEP_TMUX","Proof ceiling"): assert token in text,token
    skill=tracked(manifest["components"]["skill"]).read_text(); docs=tracked(manifest["components"]["documentation"]).read_text()
    for token in ("terminal session observe","BLOCKED_AUTODETECT_DAEMON_RACE","tmux","Proof ceiling"): assert token in docs,token
    assert "bare `herdr`" in skill
    for shell in (manifest["components"]["preCommit"],manifest["components"]["prePush"]):
        r=subprocess.run(["bash","-n",str(ROOT/shell)],cwd=ROOT,text=True,capture_output=True); assert r.returncode==0,r.stderr
    print("PASS: Android Herdr bounded client-attach harness completeness")
if __name__=="__main__": main()
