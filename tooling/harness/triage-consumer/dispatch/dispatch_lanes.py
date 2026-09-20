#!/usr/bin/env python3
"""
Triage lane dispatch runner.

Machine-executes ready lanes from ingested Triage manifests/panels and emits receipts.
Implements bounded adapter execution per dispatch.policy.json.
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).parent.parent))
from triage_consumer import (
    AsbDescriptorKind,
    AutonomyGapReason,
    TriageConsumer
)


class DispatchStatus:
    """Dispatch status constants."""
    DISPATCHED = "DISPATCHED"
    EXECUTED = "EXECUTED"
    BLOCKED_UNSUPPORTED = "BLOCKED_UNSUPPORTED"
    BLOCKED_MISSING_ADAPTER = "BLOCKED_MISSING_ADAPTER"
    BLOCKED_POLICY_VIOLATION = "BLOCKED_POLICY_VIOLATION"
    BLOCKED_HOST = "BLOCKED_HOST"
    BLOCKED_API = "BLOCKED_API"
    FAILED = "FAILED"


class DispatchReceipt:
    """Dispatch receipt for a lane execution attempt."""

    def __init__(
        self,
        lane_id: str,
        lane_mission: str,
        adapter_kind: str,
        dispatch_status: str,
        blocking_reason: Optional[str] = None,
        exit_code: Optional[int] = None,
        artifacts: Optional[List[str]] = None,
        autonomy_gap: Optional[Dict[str, Any]] = None,
        execution_details: Optional[Dict[str, Any]] = None,
        descriptor: Optional[Dict[str, Any]] = None
    ):
        self.receipt_version = "v1"
        self.lane_id = lane_id
        self.lane_mission = lane_mission
        self.adapter_kind = adapter_kind
        self.dispatch_status = dispatch_status
        self.timestamp = datetime.now(timezone.utc).isoformat()
        self.blocking_reason = blocking_reason
        self.exit_code = exit_code
        self.artifacts = artifacts or []
        self.autonomy_gap = autonomy_gap
        self.execution_details = execution_details
        self.descriptor = descriptor

    def to_dict(self) -> Dict[str, Any]:
        """Convert receipt to dictionary."""
        result = {
            "receipt_version": self.receipt_version,
            "lane_id": self.lane_id,
            "lane_mission": self.lane_mission,
            "adapter_kind": self.adapter_kind,
            "dispatch_status": self.dispatch_status,
            "timestamp": self.timestamp
        }
        if self.blocking_reason:
            result["blocking_reason"] = self.blocking_reason
        if self.exit_code is not None:
            result["exit_code"] = self.exit_code
        if self.artifacts:
            result["artifacts"] = self.artifacts
        if self.autonomy_gap:
            result["autonomy_gap"] = self.autonomy_gap
        if self.execution_details:
            result["execution_details"] = self.execution_details
        if self.descriptor:
            result["descriptor"] = self.descriptor
        return result

    def to_json(self) -> str:
        """Convert receipt to JSON string."""
        return json.dumps(self.to_dict(), indent=2)


class TriageDispatcher:
    """Dispatcher for Triage lanes to ASB adapters."""

    def __init__(self, consumer_policy_path: Path, dispatch_policy_path: Path):
        """Initialize dispatcher with policies."""
        self.consumer_policy = self._load_policy(consumer_policy_path)
        self.dispatch_policy = self._load_policy(dispatch_policy_path)
        self._validate_policies()

    def _load_policy(self, path: Path) -> Dict[str, Any]:
        """Load policy from JSON file."""
        if not path.exists():
            raise FileNotFoundError(f"Policy not found: {path}")
        with open(path) as f:
            return json.load(f)

    def _validate_policies(self):
        """Validate policy constraints."""
        consumer_policy_obj = self.consumer_policy.get("policy", {})
        dispatch_rules = self.dispatch_policy.get("dispatch_rules", {})

        if consumer_policy_obj.get("human_scheduler_allowed", True):
            raise ValueError("Policy violation: human_scheduler_allowed must be false")

        if not consumer_policy_obj.get("panel_ingest_required", False):
            raise ValueError("Policy violation: panel_ingest_required must be true")

        if not dispatch_rules.get("fail_closed_on_policy_violation", False):
            raise ValueError("Policy violation: fail_closed_on_policy_violation must be true")

    def dispatch_lane(
        self,
        lane_obj,
        mapping_obj,
        cwd: Optional[Path] = None
    ) -> DispatchReceipt:
        """
        Dispatch a single lane based on its mapping.

        Args:
            lane_obj: Triage lane object
            mapping_obj: ASB descriptor mapping object
            cwd: Working directory for execution

        Returns:
            DispatchReceipt with execution results
        """
        lane_id = lane_obj.lane_id
        lane_mission = lane_obj.mission
        adapter_kind = mapping_obj.asb_descriptor_kind.value

        if mapping_obj.asb_descriptor_kind == AsbDescriptorKind.LOCAL_ARGV:
            return self._execute_local_argv(lane_obj, mapping_obj, cwd)
        elif mapping_obj.asb_descriptor_kind == AsbDescriptorKind.CURSOR_CLOUD_AGENT:
            return self._handle_cloud_agent(lane_obj, mapping_obj)
        elif mapping_obj.asb_descriptor_kind == AsbDescriptorKind.PUBLIC_PLAN:
            return self._handle_public_plan(lane_obj, mapping_obj)
        else:
            return DispatchReceipt(
                lane_id=lane_id,
                lane_mission=lane_mission,
                adapter_kind=adapter_kind,
                dispatch_status=DispatchStatus.BLOCKED_MISSING_ADAPTER,
                blocking_reason=f"No adapter available for kind: {adapter_kind}"
            )

    def _execute_local_argv(
        self,
        lane_obj,
        mapping_obj,
        cwd: Optional[Path]
    ) -> DispatchReceipt:
        """Execute local argv command."""
        lane_id = lane_obj.lane_id
        lane_mission = lane_obj.mission
        argv = mapping_obj.argv

        if not argv:
            return DispatchReceipt(
                lane_id=lane_id,
                lane_mission=lane_mission,
                adapter_kind="local-argv",
                dispatch_status=DispatchStatus.BLOCKED_MISSING_ADAPTER,
                blocking_reason="argv not present in mapping"
            )

        execution_cwd = Path(mapping_obj.cwd) if mapping_obj.cwd else (cwd or Path.cwd())
        start_time = datetime.now(timezone.utc)

        try:
            result = subprocess.run(
                argv,
                cwd=execution_cwd,
                capture_output=True,
                text=True,
                timeout=300
            )

            duration_ms = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000

            execution_details = {
                "argv": argv,
                "cwd": str(execution_cwd),
                "stdout": result.stdout[:2000] if result.stdout else "",
                "stderr": result.stderr[:2000] if result.stderr else "",
                "duration_ms": duration_ms
            }

            status = DispatchStatus.EXECUTED if result.returncode == 0 else DispatchStatus.FAILED

            return DispatchReceipt(
                lane_id=lane_id,
                lane_mission=lane_mission,
                adapter_kind="local-argv",
                dispatch_status=status,
                exit_code=result.returncode,
                execution_details=execution_details
            )

        except subprocess.TimeoutExpired:
            return DispatchReceipt(
                lane_id=lane_id,
                lane_mission=lane_mission,
                adapter_kind="local-argv",
                dispatch_status=DispatchStatus.FAILED,
                blocking_reason="Execution timeout (300s)",
                execution_details={
                    "argv": argv,
                    "cwd": str(execution_cwd),
                    "timeout": 300
                }
            )
        except Exception as e:
            return DispatchReceipt(
                lane_id=lane_id,
                lane_mission=lane_mission,
                adapter_kind="local-argv",
                dispatch_status=DispatchStatus.FAILED,
                blocking_reason=f"Execution error: {str(e)}",
                execution_details={
                    "argv": argv,
                    "cwd": str(execution_cwd),
                    "error": str(e)
                }
            )

    def _handle_cloud_agent(
        self,
        lane_obj,
        mapping_obj
    ) -> DispatchReceipt:
        """Handle cursor-cloud-agent adapter with fail-closed observed probe."""
        cloud_agent_prompt = mapping_obj.cloud_agent_prompt
        
        if not cloud_agent_prompt:
            return DispatchReceipt(
                lane_id=lane_obj.lane_id,
                lane_mission=lane_obj.mission,
                adapter_kind="cursor-cloud-agent",
                dispatch_status=DispatchStatus.BLOCKED_MISSING_ADAPTER,
                blocking_reason="cloud_agent_prompt not present in mapping"
            )
        
        in_cloud_agent = os.environ.get("CURSOR_AGENT") == "1"
        agent_socket = os.environ.get("CURSOR_AGENT_SOCKET")
        
        if not in_cloud_agent:
            return DispatchReceipt(
                lane_id=lane_obj.lane_id,
                lane_mission=lane_obj.mission,
                adapter_kind="cursor-cloud-agent",
                dispatch_status="BLOCKED_HOST",
                blocking_reason=(
                    "CloudAgent dispatch requires execution within Cursor cloud agent context. "
                    "CURSOR_AGENT environment variable not set."
                ),
                descriptor={
                    "required_environment": "Cursor Cloud Agent",
                    "required_capability": "Task tool for subagent dispatch",
                    "recommended_action": "Run dispatcher from within a Cursor cloud agent execution context"
                }
            )
        
        if not agent_socket or not Path(agent_socket).exists():
            return DispatchReceipt(
                lane_id=lane_obj.lane_id,
                lane_mission=lane_obj.mission,
                adapter_kind="cursor-cloud-agent",
                dispatch_status="BLOCKED_API",
                blocking_reason=(
                    f"CloudAgent dispatch API socket unavailable. "
                    f"Expected socket: {agent_socket or 'not set'}"
                ),
                descriptor={
                    "required_api": "Cursor Agent API socket",
                    "socket_path": agent_socket,
                    "socket_exists": Path(agent_socket).exists() if agent_socket else False,
                    "recommended_action": (
                        "Implement Python binding for Cursor cloud agent Task tool, "
                        "or run dispatcher via cloud agent orchestration layer with Task access"
                    )
                }
            )
        
        return DispatchReceipt(
            lane_id=lane_obj.lane_id,
            lane_mission=lane_obj.mission,
            adapter_kind="cursor-cloud-agent",
            dispatch_status="BLOCKED_API",
            blocking_reason=(
                "Python API for Cursor cloud agent Task tool not yet implemented. "
                "Socket available but protocol integration required."
            ),
            descriptor={
                "cloud_agent_prompt": cloud_agent_prompt,
                "environment_detected": "Cursor Cloud Agent",
                "socket_available": True,
                "socket_path": agent_socket,
                "required_implementation": (
                    "Python client for /run/cursor/api.sock to invoke Task tool, "
                    "or orchestration-layer dispatcher that executes via cloud agent with Task access"
                ),
                "recommended_action": (
                    "SUCCESSOR IMPLEMENTATION: Create Python binding to invoke Task tool via agent socket, "
                    "enabling subagent launch with bounded wait and observed completion status"
                )
            }
        )

    def _handle_public_plan(
        self,
        lane_obj,
        mapping_obj
    ) -> DispatchReceipt:
        """Handle public-plan mapping (informational only)."""
        return DispatchReceipt(
            lane_id=lane_obj.lane_id,
            lane_mission=lane_obj.mission,
            adapter_kind="public-plan",
            dispatch_status=DispatchStatus.DISPATCHED,
            descriptor={
                "public_plan_id": mapping_obj.public_plan_id,
                "note": "Public plan mapping is informational; manual coordination required"
            }
        )

    def dispatch_manifest(
        self,
        manifest_path: Path,
        output_dir: Path,
        cwd: Optional[Path] = None
    ) -> List[DispatchReceipt]:
        """
        Dispatch all lanes from a manifest.

        Args:
            manifest_path: Path to Triage manifest JSON
            output_dir: Directory for receipt outputs
            cwd: Working directory for execution

        Returns:
            List of DispatchReceipts
        """
        consumer = TriageConsumer()
        manifest = consumer.ingest_manifest(manifest_path)

        receipts = []
        output_dir.mkdir(parents=True, exist_ok=True)

        for lane in manifest.lanes:
            mapping = consumer.map_lane_to_asb_descriptor(lane)
            receipt = self.dispatch_lane(lane, mapping, cwd)
            receipts.append(receipt)

            receipt_path = output_dir / f"receipt-{lane.lane_id}.json"
            with open(receipt_path, 'w') as f:
                f.write(receipt.to_json())

        summary_path = output_dir / "dispatch-summary.json"
        summary = {
            "manifest": str(manifest_path),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "total_lanes": len(receipts),
            "executed": sum(1 for r in receipts if r.dispatch_status == DispatchStatus.EXECUTED),
            "failed": sum(1 for r in receipts if r.dispatch_status == DispatchStatus.FAILED),
            "blocked_unsupported": sum(1 for r in receipts if r.dispatch_status == DispatchStatus.BLOCKED_UNSUPPORTED),
            "blocked_missing": sum(1 for r in receipts if r.dispatch_status == DispatchStatus.BLOCKED_MISSING_ADAPTER),
            "blocked_host": sum(1 for r in receipts if r.dispatch_status == "BLOCKED_HOST"),
            "blocked_api": sum(1 for r in receipts if r.dispatch_status == "BLOCKED_API"),
            "receipts": [r.to_dict() for r in receipts]
        }
        with open(summary_path, 'w') as f:
            json.dump(summary, f, indent=2)

        return receipts


def main():
    """CLI entry point."""
    if len(sys.argv) < 2:
        print("Usage: dispatch_lanes.py <manifest_path> [output_dir] [cwd]")
        sys.exit(1)

    manifest_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("./dispatch-receipts")
    cwd = Path(sys.argv[3]) if len(sys.argv) > 3 else None

    script_dir = Path(__file__).parent
    repo_root = script_dir.parent.parent.parent.parent
    consumer_policy = repo_root / "tooling/harness/triage-consumer/consumer.policy.json"
    dispatch_policy = repo_root / "tooling/harness/triage-consumer/dispatch/dispatch.policy.json"

    try:
        dispatcher = TriageDispatcher(consumer_policy, dispatch_policy)
        receipts = dispatcher.dispatch_manifest(manifest_path, output_dir, cwd)

        executed = sum(1 for r in receipts if r.dispatch_status == DispatchStatus.EXECUTED)
        failed = sum(1 for r in receipts if r.dispatch_status == DispatchStatus.FAILED)

        print(f"Dispatch complete: {executed} executed, {failed} failed, {len(receipts)} total")
        print(f"Receipts written to: {output_dir}")

        sys.exit(1 if failed > 0 else 0)

    except Exception as e:
        import traceback
        print(f"Dispatch failed: {e}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
