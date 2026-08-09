#!/usr/bin/env python3
"""Build a source-bound Herdr installation review without installing anything."""
from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
SOURCE_PATH = ROOT / "tooling/profiles/android/harness/herdr/upstream-installation-source.json"


def state_root() -> Path:
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".local/state"
    return base / "agentswitchboard/android-herdr-migration"


def load_source() -> dict:
    data = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    assert data["schema"] == "agentswitchboard.android-herdr-upstream-installation-source.v1"
    assert data["source"]["kind"] == "official-upstream"
    assert data["candidate"]["decision"] in {"APPROVED", "REJECTED", "BLOCKED"}
    assert data["safety"]["linuxAarch64IsAndroidProof"] is False
    assert data["safety"]["curlPipeShellAcceptedAsProof"] is False
    assert data["safety"]["automaticAndroidPolicyMutationAllowed"] is False
    assert data["safety"]["tmuxRollbackRequired"] is True
    if data["candidate"]["decision"] == "APPROVED":
        assert data["androidTermuxSupport"] == "explicitly-supported"
        assert data["candidate"]["installCommand"]
        assert data["candidate"]["rollbackCommand"]
    else:
        assert data["candidate"]["installCommand"] is None
    return data


def render(data: dict) -> str:
    src = data["source"]
    candidate = data["candidate"]
    safety = data["safety"]
    reviewed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    methods = ", ".join(data["documentedInstallMethods"])
    platforms = ", ".join(data["documentedPlatforms"])
    architectures = ", ".join(data["documentedArchitectures"])
    install_command = candidate["installCommand"] or "none — no installation is authorized by this review"
    rollback_command = candidate["rollbackCommand"] or "none — no installation is authorized by this review"
    return f"""# Herdr installation review

Status: {candidate['decision']} — source-bound review generated from tracked official-upstream metadata.

## Source binding

- Review timestamp (UTC): {reviewed_at}
- Reviewer / actor: AgentSwitchboard tracked harness
- Tracked source snapshot: `tooling/profiles/android/harness/herdr/upstream-installation-source.json`
- Source snapshot verified (UTC): {data['verifiedAtUtc']}
- Upstream repository: {src['repository']}
- Official install documentation: {src['installDocs']}
- Exact release/tag/commit: {src['releaseTag']} / {src['releaseCommit']}
- Annotated tag object: {src['tagObject']}
- Release published (UTC): {src['releasePublishedAtUtc']}
- Documented install methods: {methods}
- Upstream-documented platforms: {platforms}
- Upstream-documented architectures/assets: {architectures}
- Explicit Android/Termux support claim: {data['androidTermuxSupport']}

## Candidate artifact identity

- Candidate method: {candidate['method']}
- Candidate artifact: {candidate['artifact']}
- Candidate artifact URL: {candidate['url']}
- Candidate size (bytes): {candidate['sizeBytes']}
- Integrity: {candidate['digestAlgorithm']}:{candidate['digest']}

## Safety review

- Linux aarch64 is not treated as Android compatibility proof: {'yes' if not safety['linuxAarch64IsAndroidProof'] else 'no'}
- `cargo install herdr` is documented by the pinned upstream source: {'yes' if data['cargoInstallDocumented'] else 'no'}
- curl-pipe-shell is excluded as migration proof: {'yes' if not safety['curlPipeShellAcceptedAsProof'] else 'no'}
- automatic Android `device_config` / battery mutation is excluded: {'yes' if not safety['automaticAndroidPolicyMutationAllowed'] else 'no'}
- tmux remains installed and available for rollback: {'yes' if safety['tmuxRollbackRequired'] else 'no'}
- expected install scope: unproved while decision is {candidate['decision']}
- network / subprocess / persistence implications: unresolved until Android/Termux compatibility is proven

## Decision

- Decision: {candidate['decision']}
- Reason: {candidate['reason']}
- Exact installation command, only when APPROVED: {install_command}
- Exact rollback command, only when APPROVED: {rollback_command}
- Evidence artifact expected after installation: `herdr-readiness-<UTC timestamp>.env`
- Next gate: {candidate['nextGate']}
- Completion gate: refresh the tracked upstream source snapshot and obtain explicit Android/Termux support or separately reviewed exact-device compatibility proof before defining any bounded install command.

## Proof ceiling

This review proves only that the candidate was bound to the tracked official-upstream snapshot and classified according to its support claim. It does not prove Android compatibility, server persistence, detach/reattach, agent-state detection, background survival, coding-agent behavior, or migration readiness.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    data = load_source()
    text = render(data)
    if not args.write and args.output is None:
        print(text, end="")
    else:
        target = args.output.expanduser() if args.output else state_root() / (
            "herdr-install-review-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".md"
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        print(f"INSTALL_REVIEW={target}")

    print(f"DECISION={data['candidate']['decision']}")
    print(f"NEXT_GATE={data['candidate']['nextGate']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
