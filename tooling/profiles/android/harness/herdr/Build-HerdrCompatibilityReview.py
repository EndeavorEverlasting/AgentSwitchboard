#!/usr/bin/env python3
"""Create a local source-bound Herdr Android runtime compatibility review."""
from __future__ import annotations
import argparse, json, os
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parent
SOURCE = BASE / "upstream-runtime-compatibility.json"


def state_root() -> Path:
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".local/state"
    return base / "agentswitchboard/android-herdr-migration"


def load_source() -> dict:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert data["schema"] == "agentswitchboard.android-herdr-runtime-compatibility-source.v1"
    assert data["source"]["releaseCommit"] == "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
    assert data["compatibility"]["nativeAndroidSourceBuild"]["decision"] == "BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK"
    assert data["compatibility"]["linuxMuslPrebuiltOnTermux"]["decision"] == "EXECUTION_PROBE_APPROVED_NO_INSTALL"
    assert data["migrationDecision"] == "KEEP_TMUX"
    return data


def render(data: dict, stamp: str) -> str:
    src = data["source"]
    native = data["compatibility"]["nativeAndroidSourceBuild"]
    prebuilt = data["compatibility"]["linuxMuslPrebuiltOnTermux"]
    evidence = "\n".join(f"- `{item['path']}` — {item['fact']}" for item in data["sourceEvidence"])
    allowed = "\n".join(f"- {item}" for item in prebuilt["allowedActions"])
    forbidden = "\n".join(f"- {item}" for item in prebuilt["forbiddenActions"])
    return f"""# Herdr Android runtime compatibility review

Status: {data['reviewDecision']} — this review authorizes one ephemeral identity probe, not installation.

## Source binding

- Review timestamp (UTC): {stamp}
- Tracked compatibility snapshot: `tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json`
- Snapshot verified (UTC): {data['verifiedAtUtc']}
- Upstream repository: {src['repository']}
- Release/tag/commit: {src['releaseTag']} / {src['releaseCommit']}
- Candidate artifact: {src['artifact']}
- Candidate artifact URL: {src['artifactUrl']}
- Candidate size: {src['artifactSizeBytes']} bytes
- Candidate integrity: sha256:{src['artifactSha256']}
- Official Android/Termux support: {data['upstreamSupportSignal']['officialAndroidTermuxSupport']}
- Release build target: {prebuilt['buildTarget']}

## Pinned source evidence

{evidence}

## Native Android source-build path

- Rust target considered: {native['rustTarget']}
- Decision: {native['decision']}
- Reason: {native['reason']}

A native Android build is **not** approved as a migration route by this snapshot.

## Exact Linux-musl prebuilt probe

- Decision: {prebuilt['decision']}
- Reason: {prebuilt['reason']}
- Success gate: {prebuilt['successGate']}
- Failure gate: {prebuilt['failureGate']}

Allowed actions:

{allowed}

Forbidden actions:

{forbidden}

## Decision

- Migration decision: {data['migrationDecision']}
- Compatibility review decision: {data['reviewDecision']}
- Installation authorized: no
- Server startup authorized: no
- Exact next command: `python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence`
- Next gate: {data['nextGate']}

## Proof ceiling

{data['proofCeiling']}
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--write", action="store_true")
    p.add_argument("--output", type=Path)
    a = p.parse_args()
    data = load_source()
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    text = render(data, stamp)
    if not a.write and a.output is None:
        print(text, end="")
        return 0
    target = a.output.expanduser() if a.output else state_root() / f"herdr-compatibility-review-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    print(f"COMPATIBILITY_REVIEW={target}\nDECISION={data['reviewDecision']}\nMIGRATION_DECISION={data['migrationDecision']}\nNEXT_GATE={data['nextGate']}\nNEXT_COMMAND=python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
