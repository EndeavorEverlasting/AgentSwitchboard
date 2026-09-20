#!/usr/bin/env python3
"""Remote-safe FirstMate prompt-dispatch scout using build_prompt_dispatch.

This scout demonstrates the routing-decision → prompt-dispatch translation seam
without claiming live crew delivery or dual-path vision complete.

Default mode is dry-run / contract scout:
  - Loads a prompt-kit.routing-decision/v1 fixture (or CLI path)
  - Calls build_prompt_dispatch(...) from RRB-03
  - Writes asb.prompt-dispatch/v1 artifact to local untracked evidence
  - Does NOT invoke fm-send, tmux, or FirstMate lifecycle

Optional live-delivery mode must fail-closed on Linux/cloud with structured
BLOCKED_HOST / BLOCKED_WINDOWS_WSL_REQUIRED unless explicitly on Admin Box.
This initial implementation leaves live-delivery as UNIMPLEMENTED.
"""

from __future__ import annotations

import argparse
import json
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCOUT_VERSION = "1.0.0"
COMPONENT = "firstmate-dispatch-scout"

# Import build_prompt_dispatch from sibling module
DISPATCH_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(DISPATCH_DIR))

try:
    from build_prompt_dispatch import build_prompt_dispatch, ContractError
except ImportError as exc:
    print(f"scout: Cannot import build_prompt_dispatch: {exc}", file=sys.stderr)
    raise SystemExit(2) from exc


class ScoutError(Exception):
    """Scout execution error."""


def get_evidence_root() -> Path:
    """Return the local untracked evidence root."""
    if platform.system() == "Windows":
        local_app_data = Path.home() / "AppData" / "Local"
    else:
        # Linux/macOS
        local_app_data = Path.home() / ".local" / "share"

    return local_app_data / "AgentSwitchboard" / "runtime-proof" / "fm-asb-prompt-dispatch-scout"


def write_dispatch_artifact(dispatch: dict[str, Any], evidence_root: Path) -> Path:
    """Write dispatch artifact to timestamped evidence directory."""
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = evidence_root / timestamp
    run_dir.mkdir(parents=True, exist_ok=True)

    artifact_path = run_dir / "prompt-dispatch.json"
    artifact_path.write_text(json.dumps(dispatch, indent=2, sort_keys=True), encoding="utf-8")

    # Write summary receipt
    receipt = {
        "scoutVersion": SCOUT_VERSION,
        "executedAt": timestamp,
        "mode": "dry-run",
        "dispatchEventId": dispatch["eventId"],
        "deliveryId": dispatch["delivery"]["deliveryId"],
        "targetTaskId": dispatch["target"]["firstMateTaskId"],
        "proofCeiling": "SCOUT_CONTRACT_STATIC",
        "notes": [
            "This is a contract-only scout demonstration.",
            "No live FirstMate delivery was attempted.",
            "No crew execution occurred.",
        ],
    }
    receipt_path = run_dir / "scout-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2), encoding="utf-8")

    return artifact_path


def scout_dry_run(
    decision_path: Path,
    *,
    firstmate_task_id: str,
    instruction_summary: str,
    proof_gate: str,
    resolved_variables: dict[str, Any] | None = None,
    allow_mutation: bool = True,
    allowed_scopes: list[str] | None = None,
    forbidden_scopes: list[str] | None = None,
    expected_generation: int | None = None,
    evidence_root: Path | None = None,
) -> dict[str, Any]:
    """Execute dry-run scout: load decision, build dispatch, write artifact.

    Returns:
        Scout result with artifact path and receipt.
    """
    # Load decision
    try:
        decision = json.loads(decision_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ScoutError(f"Cannot load decision from {decision_path}: {exc}") from exc

    if not isinstance(decision, dict):
        raise ScoutError(f"Decision root must be an object, got {type(decision).__name__}")

    # Build dispatch
    try:
        dispatch = build_prompt_dispatch(
            decision,
            firstmate_task_id=firstmate_task_id,
            resolved_variables=resolved_variables,
            instruction_summary=instruction_summary,
            proof_gate=proof_gate,
            allow_mutation=allow_mutation,
            allowed_scopes=allowed_scopes,
            forbidden_scopes=forbidden_scopes,
            expected_generation=expected_generation,
        )
    except ContractError as exc:
        raise ScoutError(f"Cannot build dispatch: {exc}") from exc

    # Write artifact
    if evidence_root is None:
        evidence_root = get_evidence_root()

    artifact_path = write_dispatch_artifact(dispatch, evidence_root)

    return {
        "status": "DRY_RUN_PASS",
        "mode": "dry-run",
        "artifactPath": str(artifact_path),
        "dispatchEventId": dispatch["eventId"],
        "deliveryId": dispatch["delivery"]["deliveryId"],
        "proofCeiling": "SCOUT_CONTRACT_STATIC",
    }


def scout_live_delivery(
    decision_path: Path,
    *,
    firstmate_task_id: str,
    instruction_summary: str,
    proof_gate: str,
    resolved_variables: dict[str, Any] | None = None,
    allow_mutation: bool = True,
    allowed_scopes: list[str] | None = None,
    forbidden_scopes: list[str] | None = None,
    expected_generation: int | None = None,
    evidence_root: Path | None = None,
) -> dict[str, Any]:
    """Execute live-delivery mode: BLOCKED on Linux/cloud, UNIMPLEMENTED otherwise.

    This scout implementation does not implement actual FirstMate delivery.
    Future work: Admin Box detection and fm-send invocation.

    Returns:
        Scout result with blocked/unimplemented status.
    """
    system = platform.system()

    # Fail-closed on Linux (cloud agent environment)
    if system == "Linux":
        return {
            "status": "BLOCKED_LINUX_WSL_REQUIRED",
            "mode": "live-delivery",
            "reason": "Live FirstMate delivery is only supported on Windows Admin Box with WSL",
            "blockerType": "HOST_CAPABILITY",
            "proofCeiling": "SCOUT_CONTRACT_STATIC",
            "notes": [
                "This scout cannot invoke FirstMate lifecycle on Linux.",
                "Admin Box with Windows + WSL required for live delivery.",
                "Use --mode dry-run for contract-only translation.",
            ],
        }

    # Even on Windows, this implementation leaves live delivery unimplemented
    return {
        "status": "UNIMPLEMENTED",
        "mode": "live-delivery",
        "reason": "Live delivery is not implemented in this scout version",
        "proofCeiling": "SCOUT_CONTRACT_STATIC",
        "notes": [
            "This scout demonstrates contract-only translation.",
            "Live fm-send invocation is future work.",
            "Use --mode dry-run to validate dispatch building.",
        ],
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "Remote-safe FirstMate prompt-dispatch scout. "
            "Default mode is dry-run (contract-only translation). "
            "Live-delivery mode is blocked on Linux and unimplemented elsewhere."
        )
    )

    parser.add_argument(
        "--decision",
        type=Path,
        required=True,
        help="Path to prompt-kit.routing-decision/v1 JSON",
    )
    parser.add_argument(
        "--mode",
        choices=["dry-run", "live-delivery"],
        default="dry-run",
        help="Scout mode: dry-run (default) or live-delivery (blocked/unimplemented)",
    )
    parser.add_argument(
        "--firstmate-task-id",
        required=True,
        help="FirstMate task identifier",
    )
    parser.add_argument(
        "--instruction-summary",
        required=True,
        help="Instruction packet summary (1..4000 chars)",
    )
    parser.add_argument(
        "--proof-gate",
        required=True,
        help="Proof gate text (1..4000 chars)",
    )
    parser.add_argument(
        "--allow-mutation",
        type=lambda x: x.lower() in ("true", "1", "yes"),
        default=True,
        help="Allow mutation (default True)",
    )
    parser.add_argument(
        "--allowed-scope",
        action="append",
        default=[],
        dest="allowed_scopes",
        help="Allowed scope pattern (repeatable)",
    )
    parser.add_argument(
        "--forbidden-scope",
        action="append",
        default=[],
        dest="forbidden_scopes",
        help="Forbidden scope pattern (repeatable)",
    )
    parser.add_argument(
        "--expected-generation",
        type=int,
        help="Expected task generation (optional)",
    )
    parser.add_argument(
        "--var",
        action="append",
        default=[],
        dest="variables",
        help="Resolved variable as key=value (repeatable)",
    )
    parser.add_argument(
        "--evidence-root",
        type=Path,
        help="Custom evidence root (default: platform-specific LocalAppData equivalent)",
    )

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Main scout entrypoint."""
    args = parse_args(argv)

    # Parse variables from key=value pairs
    resolved_variables = {}
    for var in args.variables:
        if "=" not in var:
            print(f"scout: Invalid variable format (expected key=value): {var}", file=sys.stderr)
            return 2
        key, value = var.split("=", 1)
        # Try to parse as JSON value
        try:
            resolved_variables[key] = json.loads(value)
        except json.JSONDecodeError:
            # Treat as string
            resolved_variables[key] = value

    # Execute scout
    try:
        if args.mode == "dry-run":
            result = scout_dry_run(
                args.decision,
                firstmate_task_id=args.firstmate_task_id,
                instruction_summary=args.instruction_summary,
                proof_gate=args.proof_gate,
                resolved_variables=resolved_variables if resolved_variables else None,
                allow_mutation=args.allow_mutation,
                allowed_scopes=args.allowed_scopes,
                forbidden_scopes=args.forbidden_scopes,
                expected_generation=args.expected_generation,
                evidence_root=args.evidence_root,
            )
        else:  # live-delivery
            result = scout_live_delivery(
                args.decision,
                firstmate_task_id=args.firstmate_task_id,
                instruction_summary=args.instruction_summary,
                proof_gate=args.proof_gate,
                resolved_variables=resolved_variables if resolved_variables else None,
                allow_mutation=args.allow_mutation,
                allowed_scopes=args.allowed_scopes,
                forbidden_scopes=args.forbidden_scopes,
                expected_generation=args.expected_generation,
                evidence_root=args.evidence_root,
            )
    except ScoutError as exc:
        print(f"scout: {exc}", file=sys.stderr)
        return 2

    # Output result
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")

    # Exit codes:
    # 0 = DRY_RUN_PASS or successful live delivery
    # 1 = BLOCKED or UNIMPLEMENTED
    # 2 = ScoutError or invalid input
    if result["status"] == "DRY_RUN_PASS":
        return 0
    elif result["status"] in ("BLOCKED_LINUX_WSL_REQUIRED", "UNIMPLEMENTED"):
        return 1
    else:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
