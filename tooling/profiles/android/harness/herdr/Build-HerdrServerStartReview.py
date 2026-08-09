#!/usr/bin/env python3
"""Create a source-bound bounded Herdr foreground-server-start review."""
from __future__ import annotations
import argparse, json, os
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parent
SOURCE = BASE / "upstream-server-start-source.json"

def state_root() -> Path:
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".local/state"
    return base / "agentswitchboard/android-herdr-migration"

def load_source() -> dict:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert data["schema"] == "agentswitchboard.android-herdr-server-start-source.v1"
    assert data["source"]["releaseCommit"] == "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
    assert data["source"]["artifactSha256"] == "f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
    assert data["probe"]["decision"] == "BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL"
    assert data["probe"]["launchCommand"] == ["herdr", "server"]
    assert data["probe"]["statusCommand"] == ["herdr", "status", "server", "--json"]
    assert data["probe"]["stopCommand"] == ["herdr", "server", "stop"]
    assert data["migrationDecision"] == "KEEP_TMUX"
    return data

def render(data: dict, stamp: str) -> str:
    src=data["source"]; probe=data["probe"]; pre=data["precondition"]
    evidence="\n".join(f"- `{item['path']}` — {item['fact']}" for item in data["sourceEvidence"])
    allowed="\n".join(f"- {item}" for item in probe["allowedActions"])
    forbidden="\n".join(f"- {item}" for item in probe["forbiddenActions"])
    return f"""# Herdr Android bounded server-start review

Status: {data['reviewDecision']} — one foreground lifecycle probe is authorized after the exact-device prebuilt identity prerequisite passes.

## Source binding

- Review timestamp (UTC): {stamp}
- Tracked source snapshot: `tooling/profiles/android/harness/herdr/upstream-server-start-source.json`
- Snapshot verified (UTC): {data['verifiedAtUtc']}
- Upstream repository: {src['repository']}
- Release/tag/commit: {src['releaseTag']} / {src['releaseCommit']}
- Candidate artifact: {src['artifact']}
- Candidate size: {src['artifactSizeBytes']} bytes
- Candidate integrity: sha256:{src['artifactSha256']}

## Required live prerequisite

- Evidence schema: {pre['requiredEvidenceSchema']}
- Release commit: {pre['requiredReleaseCommit']}
- Artifact: {pre['requiredArtifact']}
- SHA-256: {pre['requiredSha256']}
- Execution compatibility: {pre['requiredExecCompatibility']}
- Version identity contains: {pre['requiredVersionOutputContains']}

The live probe refuses to download or start a server unless this exact-device prerequisite is present and valid.

## Pinned upstream evidence

{evidence}

## Bounded probe contract

- Decision: {probe['decision']}
- Migration decision: {probe['migrationDecision']}
- Launch mode: {probe['launchMode']}
- Launch command: `{' '.join(probe['launchCommand'])}`
- Status command: `{' '.join(probe['statusCommand'])}`
- Stop command: `{' '.join(probe['stopCommand'])}`
- Start readiness bound: {probe['startTimeoutSeconds']} seconds
- Per-command bound: {probe['commandTimeoutSeconds']} seconds

Allowed actions:

{allowed}

Forbidden actions:

{forbidden}

## Completion gate

- Success: {probe['successGate']}
- Failure: {probe['failureGate']}
- Exact next command: `python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py evidence`
- Next gate on PASS: bounded-client-attach-review

## Proof ceiling

{data['proofCeiling']}
"""

def main() -> int:
    p=argparse.ArgumentParser()
    p.add_argument("--write", action="store_true")
    p.add_argument("--output", type=Path)
    a=p.parse_args()
    data=load_source()
    stamp=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    text=render(data, stamp)
    if not a.write and a.output is None:
        print(text, end="")
        return 0
    target=a.output.expanduser() if a.output else state_root()/f"herdr-server-start-review-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    print(f"SERVER_START_REVIEW={target}\nDECISION={data['reviewDecision']}\nMIGRATION_DECISION={data['migrationDecision']}\nNEXT_GATE={data['nextGate']}\nNEXT_COMMAND=python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py evidence")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
