#!/usr/bin/env python3
"""Validate an AgentSwitchboard operator command against device/profile boundaries."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "tooling" / "harness" / "profile-boundary"
REGISTRY = HARNESS / "profile-boundary.registry.json"


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def validate_envelope(envelope: dict, registry: dict | None = None) -> dict:
    registry = registry or _load(REGISTRY)
    reasons: list[str] = []
    next_action = "Command handoff may proceed."

    required = ("schema", "hostContext", "targetProfile", "executionSurface", "command")
    missing = [key for key in required if not envelope.get(key)]
    if missing:
        reasons.append("missing-required-fields:" + ",".join(missing))

    if envelope.get("schema") != "agentswitchboard.command-envelope.v1":
        reasons.append("unsupported-envelope-schema")

    host = envelope.get("hostContext")
    surface = envelope.get("executionSurface")
    target = envelope.get("targetProfile")
    command = envelope.get("command", "")

    contexts = registry["hostContexts"]
    surfaces = registry["executionSurfaces"]
    if host not in contexts:
        reasons.append("unknown-host-context")
    if surface not in surfaces:
        reasons.append("unknown-execution-surface")
    if target not in {"windows", "linux", "android"}:
        reasons.append("unknown-target-profile")

    if host in contexts and surface:
        allowed = contexts[host]["allowedExecutionSurfaces"]
        if surface not in allowed:
            reasons.append("host-surface-mismatch")

    if surface in surfaces and target and surfaces[surface]["targetProfile"] != target:
        reasons.append("surface-profile-mismatch")

    lower = command.lower()
    android_markers = registry["commandMarkers"]["androidOnly"]
    if any(marker.lower() in lower for marker in android_markers):
        if not (host == "android-phone" and surface == "android-termux" and target == "android"):
            reasons.append("android-command-profile-mismatch")

    if host == "windows-laptop" and target == "android":
        reasons.append("android-target-on-windows-host")

    if host == "windows-laptop" and surface == "windows-powershell":
        if "bash -lc" in lower and "wsl.exe" not in lower:
            reasons.append("ambiguous-bash-on-windows")

    if host == "windows-laptop" and surface == "wsl-linux":
        proof = envelope.get("bridgeProof") or {}
        required_probe_tokens = contexts[host]["bridgeRequirements"]["wsl-linux"]["requiredProbeTokens"]
        if proof.get("status") != "passed":
            reasons.append("wsl-bridge-unproved")
        probe = proof.get("probe", "")
        for token in required_probe_tokens:
            if token.lower() not in probe.lower():
                reasons.append("wsl-bridge-probe-incomplete")
                break
        if not proof.get("evidence"):
            reasons.append("wsl-bridge-evidence-missing")

    status = "BLOCKED" if reasons else "PASS"
    if reasons:
        if any(code in reasons for code in ("android-command-profile-mismatch", "android-target-on-windows-host")):
            next_action = "Run the Android command from the Android phone/Termux context; do not repair laptop WSL as a substitute."
        elif any(code.startswith("wsl-bridge") or code == "ambiguous-bash-on-windows" for code in reasons):
            next_action = "Prove WSL with wsl.exe and /bin/bash first, then regenerate the envelope; otherwise use a Windows-native command."
        else:
            next_action = "Correct the declared host/profile/execution surface and regenerate the command envelope."

    return {
        "schema": "agentswitchboard.profile-boundary-report.v1",
        "status": status,
        "hostContext": host,
        "targetProfile": target,
        "executionSurface": surface,
        "reasonCodes": sorted(set(reasons)),
        "commandSha256": hashlib.sha256(command.encode("utf-8")).hexdigest(),
        "nextAction": next_action,
        "proofCeiling": "Deterministic routing classification only; no runtime execution is proven."
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--envelope", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    envelope = _load(args.envelope)
    result = validate_envelope(envelope)
    rendered = json.dumps(result, indent=2, sort_keys=True)
    print(rendered)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["status"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
