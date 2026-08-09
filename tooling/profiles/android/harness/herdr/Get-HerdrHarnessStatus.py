#!/usr/bin/env python3
"""Render low-noise Herdr harness status from tracked contracts and sanitized readiness evidence."""
from __future__ import annotations
import argparse, json
from datetime import datetime, timezone
from pathlib import Path

STATE_ROOT = Path.home() / ".local/state/agentswitchboard/android-herdr-migration"
ALLOWED = {"profile","frontend","kernel","arch","android_release","herdr_path","herdr_version","herdr_help","tmux_path","tmux_version","migration_decision","next_gate","proof_level","fixture"}

def parse_env(path: Path) -> dict[str,str]:
    data = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw and not raw.startswith("#") and "=" in raw:
            key, value = raw.split("=", 1)
            if key in ALLOWED: data[key] = value
    return data

def newest() -> Path | None:
    if not STATE_ROOT.is_dir(): return None
    found = sorted(STATE_ROOT.glob("herdr-readiness-*.env"))
    return found[-1] if found else None

def classify(evidence: dict[str,str] | None) -> dict:
    status = {"canonicalMultiplexer":"tmux","herdrStatus":"experimental-unproved","working":["tracked Herdr harness contracts and tmux fallback"],"blocked":[],"missing":[],"proofReached":["repository harness classification only"],"risks":["Linux aarch64 is not Android/Termux proof","binary presence is not persistence proof","phone evidence remains local/untracked"]}
    if not evidence:
        status.update(status="runtime-evidence-not-supplied", migrationDecision="UNPROVED", blocked=["no sanitized phone readiness evidence selected"], missing=["phone binary-readiness classification","reviewed install method","all live promotion gates"], nextGate="phone-readiness-evidence", nextCommand="bash Test-AgentSwitchboard-Android-Herdr.sh evidence")
        return status
    decision = evidence.get("migration_decision", "UNPROVED")
    status["migrationDecision"] = decision
    status["proofReached"].append(evidence.get("proof_level", "unknown"))
    if evidence.get("tmux_path") not in (None, "", "missing"): status["working"].append("tmux fallback observed")
    if decision == "KEEP_TMUX_HERDR_NOT_INSTALLED":
        status.update(status="blocked-herdr-not-installed", blocked=["Herdr executable is absent"], missing=["source-bound reviewed installation method","Herdr binary identity","server/persistence/agent-state/background/sprint proof"], nextGate="reviewed-installation-method", nextCommand="python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write")
    elif decision == "KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY":
        status.update(status="blocked-herdr-binary-unhealthy", blocked=["Herdr version/help identity is unhealthy"], missing=["binary compatibility repair","server/persistence/agent-state/background/sprint proof"], nextGate="binary-compatibility-repair", nextCommand="python tests/test_android_herdr_harness_completeness.py")
    elif decision == "HERDR_BINARY_CANDIDATE_ONLY":
        status["working"].append("Herdr command/version/help readiness observed")
        status.update(status="binary-candidate-runtime-unproved", missing=["authorized server start","detach/reattach","agent-state","Android background survival","bounded sprint proof"], nextGate="separately-authorized-live-server-proof", nextCommand="python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py --write")
    else:
        status.update(status="unknown-readiness-classification", blocked=[f"unrecognized migration decision: {decision}"], missing=["recognized probe classification"], nextGate="repair-probe-or-evidence", nextCommand="python tests/test_android_herdr_harness_completeness.py")
    return status

def markdown(s: dict, source: str) -> str:
    bullets = lambda xs: "\n".join(f"- {x}" for x in xs) if xs else "- none"
    return f"""# Android Herdr harness status\n\n- Evidence source: {source}\n- Status: {s['status']}\n- Migration decision: {s['migrationDecision']}\n- Canonical multiplexer: {s['canonicalMultiplexer']}\n- Herdr status: {s['herdrStatus']}\n- Next gate: {s['nextGate']}\n\n## Working\n\n{bullets(s['working'])}\n\n## Broken or blocked\n\n{bullets(s['blocked'])}\n\n## Missing / unproved\n\n{bullets(s['missing'])}\n\n## Proof reached\n\n{bullets(s['proofReached'])}\n\n## Risks / known traps\n\n{bullets(s['risks'])}\n\n## Exact next command\n\n`{s['nextCommand']}`\n\n## Proof ceiling\n\nTracked harness state and sanitized readiness classification only; no installation approval, Android compatibility, persistent server, agent-state, background-survival, sprint-success, or tmux-retirement proof.\n"""

def main() -> int:
    p = argparse.ArgumentParser(); p.add_argument("--evidence", type=Path); p.add_argument("--format", choices=("markdown","json"), default="markdown"); p.add_argument("--write", action="store_true"); a = p.parse_args()
    ep = a.evidence.expanduser() if a.evidence else newest(); ev = parse_env(ep) if ep and ep.is_file() else None; source = str(ep) if ep and ep.is_file() else "none"; s = classify(ev); s["evidenceSource"] = source
    if a.write:
        STATE_ROOT.mkdir(parents=True, exist_ok=True); stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"); jp = STATE_ROOT / f"herdr-harness-status-{stamp}.json"; mp = STATE_ROOT / f"herdr-harness-status-{stamp}.md"; jp.write_text(json.dumps(s, indent=2)+"\n", encoding="utf-8"); mp.write_text(markdown(s, source), encoding="utf-8"); print(f"STATUS_JSON={jp}\nSTATUS_MARKDOWN={mp}\nSTATUS={s['status']}\nNEXT_GATE={s['nextGate']}\nNEXT_COMMAND={s['nextCommand']}"); return 0
    print(json.dumps(s, indent=2) if a.format == "json" else markdown(s, source), end="\n" if a.format == "json" else ""); return 0

if __name__ == "__main__": raise SystemExit(main())
