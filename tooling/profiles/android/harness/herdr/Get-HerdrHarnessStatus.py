#!/usr/bin/env python3
"""Render low-noise Herdr harness status from tracked contracts and sanitized local evidence."""
from __future__ import annotations
import argparse, json, os
from datetime import datetime, timezone
from pathlib import Path

RELEASE_COMMIT="346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
PREBUILT_SHA256="f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87"
READINESS_ALLOWED={"profile","frontend","kernel","arch","android_release","herdr_path","herdr_version","herdr_help","tmux_path","tmux_version","migration_decision","next_gate","proof_level","fixture"}

def default_state_root() -> Path:
    xdg=os.environ.get("XDG_STATE_HOME")
    base=Path(xdg).expanduser() if xdg else Path.home()/".local/state"
    return base/"agentswitchboard/android-herdr-migration"

DEFAULT_STATE_ROOT=default_state_root()

def parse_env(path: Path, allowed: set[str]|None=None) -> dict[str,str]:
    data={}
    for raw in path.read_text(encoding="utf-8",errors="replace").splitlines():
        if raw and not raw.startswith("#") and "=" in raw:
            key,value=raw.split("=",1)
            if allowed is None or key in allowed:
                data[key]=value
    return data

def newest(state_root: Path, pattern: str) -> Path|None:
    if not state_root.is_dir():
        return None
    found=sorted(state_root.glob(pattern))
    return found[-1] if found else None

def blocked_install_review(path: Path|None) -> bool:
    if not path or not path.is_file():
        return False
    text=path.read_text(encoding="utf-8",errors="replace")
    return "- Decision: BLOCKED" in text and RELEASE_COMMIT in text

def prebuilt_exec_pass(path: Path|None) -> bool:
    if not path or not path.is_file():
        return False
    ev=parse_env(path)
    return (
        ev.get("schema")=="agentswitchboard.android-herdr-prebuilt-exec.v1"
        and ev.get("release_commit")==RELEASE_COMMIT
        and ev.get("artifact")=="herdr-linux-aarch64"
        and ev.get("expected_sha256")==PREBUILT_SHA256
        and ev.get("size_verified")=="yes"
        and ev.get("digest_verified")=="yes"
        and ev.get("version_exit_code")=="0"
        and "herdr 0.8.0" in ev.get("version_output","").lower()
        and ev.get("exec_compatibility")=="PASS"
    )

def classify(evidence: dict[str,str]|None, install_review_complete: bool=False, prebuilt_complete: bool=False) -> dict:
    status={
        "canonicalMultiplexer":"tmux",
        "herdrStatus":"experimental-unproved",
        "working":["tracked Herdr harness contracts and tmux fallback"],
        "blocked":[],
        "missing":[],
        "proofReached":["repository harness classification only"],
        "risks":[
            "Linux aarch64 is not Android/Termux support proof",
            "prebuilt --version success is not server persistence or client attach proof",
            "bare herdr auto-launch is outside the bounded foreground server probe",
            "phone evidence remains local/untracked",
        ],
    }
    if not evidence:
        status.update(
            status="runtime-evidence-not-supplied",migrationDecision="UNPROVED",
            blocked=["no sanitized phone readiness evidence selected"],
            missing=["phone binary-readiness classification","source-bound install review","runtime compatibility review","prebuilt execution identity","all live promotion gates"],
            nextGate="phone-readiness-evidence",nextCommand="bash Test-AgentSwitchboard-Android-Herdr.sh evidence"
        )
        return status
    decision=evidence.get("migration_decision","UNPROVED")
    status["migrationDecision"]=decision
    status["proofReached"].append(evidence.get("proof_level","unknown"))
    if evidence.get("tmux_path") not in (None,"","missing"):
        status["working"].append("tmux fallback observed")
    if decision=="KEEP_TMUX_HERDR_NOT_INSTALLED":
        if install_review_complete and prebuilt_complete:
            status["working"].extend([
                "source-bound BLOCKED install review observed",
                "exact-device checksum-verified Herdr 0.8.0 prebuilt execution identity observed",
            ])
            status["proofReached"].extend(["source-bound-install-review-blocked","prebuilt-exec-identity-only"])
            status.update(
                status="prebuilt-execution-identity-proven-server-unproved",
                blocked=["persistent installation remains unauthorized; tmux remains canonical"],
                missing=["source-bound bounded server-start review","foreground server start/status/stop proof","client attach/detach/agent-state/background/sprint proof"],
                nextGate="bounded-server-start-review",
                nextCommand="python tooling/profiles/android/harness/herdr/Build-HerdrServerStartReview.py --write",
            )
        elif install_review_complete:
            status["working"].append("source-bound BLOCKED install review observed")
            status["proofReached"].append("source-bound-install-review-blocked")
            status.update(
                status="blocked-herdr-runtime-compatibility-unproved",
                blocked=["Herdr executable is absent; installation remains blocked"],
                missing=["source-bound runtime compatibility review","exact-device prebuilt execution identity","server/persistence/agent-state/background/sprint proof"],
                nextGate="source-bound-runtime-compatibility-review",
                nextCommand="python tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py --write",
            )
        else:
            status.update(
                status="blocked-herdr-not-installed",blocked=["Herdr executable is absent"],
                missing=["source-bound reviewed installation method","runtime compatibility review","Herdr binary identity","server/persistence/agent-state/background/sprint proof"],
                nextGate="reviewed-installation-method",
                nextCommand="python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write",
            )
    elif decision=="KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY":
        status.update(
            status="blocked-herdr-binary-unhealthy",blocked=["Herdr version/help identity is unhealthy"],
            missing=["binary compatibility repair","server/persistence/agent-state/background/sprint proof"],
            nextGate="binary-compatibility-repair",nextCommand="python tests/test_android_herdr_harness_completeness.py"
        )
    elif decision=="HERDR_BINARY_CANDIDATE_ONLY":
        status["working"].append("Herdr command/version/help readiness observed")
        status.update(
            status="binary-candidate-runtime-unproved",
            missing=["authorized server start","detach/reattach","agent-state","Android background survival","bounded sprint proof"],
            nextGate="separately-authorized-live-server-proof",
            nextCommand="python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py --write",
        )
    else:
        status.update(
            status="unknown-readiness-classification",blocked=[f"unrecognized migration decision: {decision}"],
            missing=["recognized probe classification"],nextGate="repair-probe-or-evidence",
            nextCommand="python tests/test_android_herdr_harness_completeness.py"
        )
    return status

def markdown(s: dict, source: str, review_source: str, prebuilt_source: str) -> str:
    bullets=lambda xs:"\n".join(f"- {x}" for x in xs) if xs else "- none"
    return f"""# Android Herdr harness status

- Evidence source: {source}
- Install review source: {review_source}
- Prebuilt execution source: {prebuilt_source}
- Status: {s['status']}
- Migration decision: {s['migrationDecision']}
- Canonical multiplexer: {s['canonicalMultiplexer']}
- Herdr status: {s['herdrStatus']}
- Next gate: {s['nextGate']}

## Working

{bullets(s['working'])}

## Broken or blocked

{bullets(s['blocked'])}

## Missing / unproved

{bullets(s['missing'])}

## Proof reached

{bullets(s['proofReached'])}

## Risks / known traps

{bullets(s['risks'])}

## Exact next command

`{s['nextCommand']}`

## Proof ceiling

Tracked harness state plus selected sanitized readiness/install-review/prebuilt-execution evidence only. Prebuilt identity can advance routing to a bounded foreground server-start review, but no persistent installation, daemon auto-launch, client attach, detach/reattach, agent-state, Android background-survival, sprint-success, or tmux-retirement proof is implied.
"""

def main() -> int:
    p=argparse.ArgumentParser()
    p.add_argument("--evidence",type=Path)
    p.add_argument("--install-review",type=Path)
    p.add_argument("--prebuilt-evidence",type=Path)
    p.add_argument("--state-root",type=Path,help="Override local state discovery/output root; deterministic validators should use an isolated temporary directory.")
    p.add_argument("--format",choices=("markdown","json"),default="markdown")
    p.add_argument("--write",action="store_true")
    a=p.parse_args()
    state_root=a.state_root.expanduser() if a.state_root else DEFAULT_STATE_ROOT
    ep=a.evidence.expanduser() if a.evidence else newest(state_root,"herdr-readiness-*.env")
    rp=a.install_review.expanduser() if a.install_review else newest(state_root,"herdr-install-review-*.md")
    pp=a.prebuilt_evidence.expanduser() if a.prebuilt_evidence else newest(state_root,"herdr-prebuilt-exec-*.env")
    ev=parse_env(ep,READINESS_ALLOWED) if ep and ep.is_file() else None
    source=str(ep) if ep and ep.is_file() else "none"
    review_source=str(rp) if rp and rp.is_file() else "none"
    prebuilt_source=str(pp) if pp and pp.is_file() else "none"
    s=classify(ev,blocked_install_review(rp),prebuilt_exec_pass(pp))
    s["evidenceSource"]=source
    s["installReviewSource"]=review_source
    s["prebuiltEvidenceSource"]=prebuilt_source
    s["stateRoot"]=str(state_root)
    if a.write:
        state_root.mkdir(parents=True,exist_ok=True)
        stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        jp=state_root/f"herdr-harness-status-{stamp}.json"
        mp=state_root/f"herdr-harness-status-{stamp}.md"
        jp.write_text(json.dumps(s,indent=2)+"\n",encoding="utf-8")
        mp.write_text(markdown(s,source,review_source,prebuilt_source),encoding="utf-8")
        print(f"STATUS_JSON={jp}\nSTATUS_MARKDOWN={mp}\nSTATUS={s['status']}\nNEXT_GATE={s['nextGate']}\nNEXT_COMMAND={s['nextCommand']}")
        return 0
    print(json.dumps(s,indent=2) if a.format=="json" else markdown(s,source,review_source,prebuilt_source),end="\n" if a.format=="json" else "")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
