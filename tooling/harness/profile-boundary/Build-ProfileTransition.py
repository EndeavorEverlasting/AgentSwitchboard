#!/usr/bin/env python3
"""Build a corrected command envelope for a validated cross-profile transition."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "tooling" / "harness" / "profile-boundary"
VALIDATOR_PATH = HARNESS / "Validate-CommandEnvelope.py"
REGISTRY_PATH = HARNESS / "profile-boundary.registry.json"

ANDROID_TRANSITION_REASONS = {
    "android-command-profile-mismatch",
    "android-target-on-windows-host",
    "host-surface-mismatch",
}


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _load_validator():
    spec = importlib.util.spec_from_file_location("profile_boundary_validator", VALIDATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("validator-loader-unavailable")
    spec.loader.exec_module(module)
    return module


def build_transition(envelope: dict, report: dict, registry: dict | None = None) -> tuple[dict, dict]:
    registry = registry or _load(REGISTRY_PATH)
    validator = _load_validator()

    command = envelope.get("command", "")
    digest = hashlib.sha256(command.encode("utf-8")).hexdigest()
    errors: list[str] = []

    if report.get("schema") != "agentswitchboard.profile-boundary-report.v1":
        errors.append("unsupported-source-report-schema")
    if report.get("status") != "BLOCKED":
        errors.append("source-report-not-blocked")
    if report.get("commandSha256") != digest:
        errors.append("source-command-digest-mismatch")

    for key in ("hostContext", "targetProfile", "executionSurface"):
        if report.get(key) != envelope.get(key):
            errors.append(f"source-{key}-mismatch")

    reasons = set(report.get("reasonCodes") or [])
    if not reasons.intersection(ANDROID_TRANSITION_REASONS):
        errors.append("source-not-android-transition")
    if envelope.get("targetProfile") != "android":
        errors.append("source-target-not-android")

    if errors:
        raise ValueError(",".join(sorted(set(errors))))

    transitioned = {
        "schema": "agentswitchboard.command-envelope.v1",
        "hostContext": "android-phone",
        "targetProfile": "android",
        "executionSurface": "android-termux",
        "command": command,
    }

    validation = validator.validate_envelope(transitioned, registry)
    if validation["status"] != "PASS":
        raise ValueError(
            "transition-validation-failed:" + ",".join(validation["reasonCodes"])
        )

    transition_report = {
        "schema": "agentswitchboard.profile-transition-report.v1",
        "status": "PASS",
        "sourceCommandSha256": digest,
        "sourceHostContext": envelope.get("hostContext"),
        "destinationHostContext": transitioned["hostContext"],
        "targetProfile": transitioned["targetProfile"],
        "executionSurface": transitioned["executionSurface"],
        "sourceReasonCodes": sorted(reasons),
        "handoffValidationStatus": validation["status"],
        "nextAction": (
            "Transfer the generated command envelope to the Android phone/Termux context "
            "and validate it there before execution."
        ),
        "proofCeiling": (
            "The transition artifact is cryptographically bound to the blocked source command "
            "and passes deterministic profile-boundary validation. No Android runtime execution "
            "is proven."
        ),
    }
    return transitioned, transition_report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--envelope", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--transition-report", type=Path)
    args = parser.parse_args()

    try:
        envelope = _load(args.envelope)
        report = _load(args.report)
        transitioned, transition_report = build_transition(envelope, report)
    except (OSError, json.JSONDecodeError, ValueError, RuntimeError) as exc:
        print(
            json.dumps(
                {
                    "schema": "agentswitchboard.profile-transition-report.v1",
                    "status": "BLOCKED",
                    "reason": str(exc),
                    "proofCeiling": "No transition artifact was emitted.",
                },
                indent=2,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(transitioned, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    rendered = json.dumps(transition_report, indent=2, sort_keys=True)
    print(rendered)
    print(f"HANDOFF={args.output}")
    if args.transition_report:
        args.transition_report.parent.mkdir(parents=True, exist_ok=True)
        args.transition_report.write_text(rendered + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
