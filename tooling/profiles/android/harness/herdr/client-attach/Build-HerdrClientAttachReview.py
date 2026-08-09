#!/usr/bin/env python3
"""Build a source-bound Android Herdr client-attach review; never installs or runs Herdr."""
from __future__ import annotations
import argparse, datetime as dt, json, os
from pathlib import Path

BASE=Path(__file__).resolve().parent
SOURCE=BASE/"upstream-client-attach-source.json"

def state_root() -> Path:
    base=Path(os.environ.get("XDG_STATE_HOME", str(Path.home()/".local/state")))
    return base/"agentswitchboard"/"android-herdr-migration"

def load_source() -> dict:
    d=json.loads(SOURCE.read_text(encoding="utf-8"))
    assert d["schema"]=="agentswitchboard.android-herdr-client-attach-source.v1"
    assert d["source"]["releaseTag"]=="v0.8.0"
    assert d["source"]["releaseCommit"]=="346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
    assert d["source"]["artifactSha256"]=="f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
    assert d["source"]["protocol"]==19
    assert d["reviewDecision"]=="BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL"
    assert d["fullAppTuiDecision"]=="BLOCKED_AUTODETECT_DAEMON_RACE"
    assert d["migrationDecision"]=="KEEP_TMUX"
    return d

def render(d:dict, stamp:str)->str:
    s=d["source"]; p=d["probe"]; pre=d["precondition"]
    evidence="\n".join(f"- `{e['path']}` — {e['fact']}" for e in d["sourceEvidence"])
    allowed="\n".join(f"- {x}" for x in p["allowedActions"])
    forbidden="\n".join(f"- {x}" for x in p["forbiddenActions"])
    return f"""# Herdr Android bounded client-attach review

Status: {d['reviewDecision']} — one read-only client-protocol observer experiment is authorized after the exact same-device foreground server lifecycle prerequisite passes.

## Source binding

- Review timestamp (UTC): {stamp}
- Tracked source: `tooling/profiles/android/harness/herdr/client-attach/upstream-client-attach-source.json`
- Source verified (UTC): {d['verifiedAtUtc']}
- Upstream repository: {s['repository']}
- Release/tag/commit: {s['releaseTag']} / {s['releaseCommit']}
- Candidate artifact: {s['artifact']}
- Candidate size: {s['artifactSizeBytes']}
- Candidate SHA-256: {s['artifactSha256']}
- Protocol: {s['protocol']}

## Required same-device prerequisite

- Evidence schema: {pre['requiredEvidenceSchema']}
- Release commit: {pre['requiredReleaseCommit']}
- SHA-256: {pre['requiredSha256']}
- Server lifecycle: {pre['requiredLifecycle']}
- Running observation: {pre['requiredStatusRunning']}
- Version: {pre['requiredStatusVersion']}
- Protocol compatible: {pre['requiredStatusCompatible']}
- Graceful stop exit: {pre['requiredStopExitCode']}
- Post-stop running: {pre['requiredPostStopRunning']}
- Server exit: {pre['requiredServerExitCode']}
- Forced cleanup: {pre['requiredForcedCleanup']}

## Pinned upstream evidence

{evidence}

## Bounded client attach decision

- Approved path: `{p['observerCommand']}`
- Discovery: `{p['readOnlyDiscoveryCommand']}`
- Full-app bare `herdr` decision: **{d['fullAppTuiDecision']}**
- Reason: bare `herdr` may auto-spawn a detached daemon if the server disappears; the observer CLI connects directly and does not use that auto-detect path.
- Migration decision: {d['migrationDecision']}

Allowed actions:

{allowed}

Forbidden actions:

{forbidden}

## Completion gate

- Success: {p['successGate']}
- Failure: {p['failureGate']}
- Next gate on PASS: `{d['nextGateOnPass']}`
- Exact next command: `python tooling/profiles/android/harness/herdr/client-attach/Probe-HerdrClientAttach.py evidence`

## Proof ceiling

{d['proofCeiling']}
"""

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--write",action="store_true"); ap.add_argument("--output"); a=ap.parse_args()
    d=load_source(); now=dt.datetime.now(dt.timezone.utc); stamp=now.strftime("%Y-%m-%dT%H:%M:%SZ"); text=render(d,stamp)
    out=Path(a.output) if a.output else (state_root()/f"herdr-client-attach-review-{now.strftime('%Y%m%dT%H%M%SZ')}.md" if a.write else None)
    if out:
        out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding="utf-8"); print(f"CLIENT_ATTACH_REVIEW={out}")
    else: print(text,end="")
    print("DECISION=BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL")
    print("FULL_APP_TUI_DECISION=BLOCKED_AUTODETECT_DAEMON_RACE")
    print("MIGRATION_DECISION=KEEP_TMUX")
    print("NEXT_GATE=exact-device-client-protocol-observer-frame")
    print("NEXT_COMMAND=python tooling/profiles/android/harness/herdr/client-attach/Probe-HerdrClientAttach.py evidence")
if __name__=="__main__": main()
