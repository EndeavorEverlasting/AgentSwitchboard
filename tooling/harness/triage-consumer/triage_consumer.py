#!/usr/bin/env python3
"""
Triage→ASB durable consumer contract floor.

This module implements AgentSwitchboard's consumer for Triage prompt-parallel-dispatch
manifests and panel/lane-prompt transport artifacts. It closes the AUTONOMY_GAP by
providing machine ingestion, classification, and mapping to ASB execution descriptors.

Policy:
- human_scheduler_allowed: false
- panel_ingest_required: true
- autonomy_gap_classification_required: true
- manifest_and_panels_are_machine_inputs: true
- panel_deletion_forbidden: true
"""

import json
import os
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional


class AsbDescriptorKind(Enum):
    """ASB execution descriptor kinds."""
    PUBLIC_PLAN = "public-plan"
    CURSOR_CLOUD_AGENT = "cursor-cloud-agent"
    LOCAL_ARGV = "local-argv"
    UNMAPPED = "unmapped"


class MappingConfidence(Enum):
    """Lane mapping confidence levels."""
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    NONE = "none"


class AutonomyGapReason(Enum):
    """AUTONOMY_GAP classification reasons."""
    NO_GAP = "no_gap"
    NO_MANIFEST_OR_PANELS = "no_manifest_or_panels"
    NO_READY_LANES = "no_ready_lanes"
    ALL_LANES_MAPPED = "all_lanes_mapped"
    ADAPTERS_UNAVAILABLE = "adapters_unavailable"
    PANEL_INGEST_MISSING = "panel_ingest_missing"
    UNKNOWN = "unknown"


@dataclass
class TriageLane:
    """Triage parallel-dispatch lane."""
    lane_id: str
    mission: str
    dependencies: List[str]
    owned_mutation_surfaces: List[str]
    forbidden_surfaces: List[str]
    adapter: Dict[str, Any]
    launch: Dict[str, Any]
    expected_artifacts: List[str]
    validation: List[str]
    convergence_owner: str
    status: str


@dataclass
class TriageManifest:
    """Triage prompt-parallel-dispatch manifest."""
    schema_version: str
    run_id: str
    graph_width: int
    parallel_disposition: str
    autonomy_gap: Optional[str]
    lanes: List[TriageLane]

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TriageManifest":
        """Create manifest from dictionary."""
        lanes = [
            TriageLane(
                lane_id=lane["lane_id"],
                mission=lane["mission"],
                dependencies=lane.get("dependencies", []),
                owned_mutation_surfaces=lane.get("owned_mutation_surfaces", []),
                forbidden_surfaces=lane.get("forbidden_surfaces", []),
                adapter=lane.get("adapter", {}),
                launch=lane.get("launch", {}),
                expected_artifacts=lane.get("expected_artifacts", []),
                validation=lane.get("validation", []),
                convergence_owner=lane.get("convergence_owner", ""),
                status=lane.get("status", "PLANNED")
            )
            for lane in data.get("lanes", [])
        ]
        return cls(
            schema_version=data["schema_version"],
            run_id=data["run_id"],
            graph_width=data["graph_width"],
            parallel_disposition=data["parallel_disposition"],
            autonomy_gap=data.get("autonomy_gap"),
            lanes=lanes
        )


@dataclass
class TriagePanel:
    """Triage panel/lane-prompt transport artifact."""
    panel_id: str
    lane_id: str
    sprint_name: str
    repo: str
    branch: str
    mission: str
    owned_scope: List[str]
    forbidden_scope: List[str]
    expected_artifacts: List[str]
    validation_order: List[str]
    prompt_content: str
    dependencies: List[str]
    wave: int

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TriagePanel":
        """Create panel from dictionary."""
        return cls(
            panel_id=data["panel_id"],
            lane_id=data["lane_id"],
            sprint_name=data["sprint_name"],
            repo=data["repo"],
            branch=data.get("branch", ""),
            mission=data["mission"],
            owned_scope=data.get("owned_scope", []),
            forbidden_scope=data.get("forbidden_scope", []),
            expected_artifacts=data.get("expected_artifacts", []),
            validation_order=data.get("validation_order", []),
            prompt_content=data["prompt_content"],
            dependencies=data.get("dependencies", []),
            wave=data.get("wave", 1)
        )


@dataclass
class LaneMapping:
    """Mapping from Triage lane to ASB descriptor."""
    lane_id: str
    asb_descriptor_kind: AsbDescriptorKind
    mapping_confidence: MappingConfidence
    execution_ready: bool
    public_plan_id: Optional[str] = None
    cloud_agent_prompt: Optional[str] = None
    argv: Optional[List[str]] = None
    cwd: Optional[str] = None
    blocking_reason: Optional[str] = None


@dataclass
class AutonomyGap:
    """AUTONOMY_GAP classification."""
    gap_detected: bool
    manifest_present: bool
    panels_present: bool
    ready_lanes_count: int
    unmapped_lanes_count: int
    gap_reason: AutonomyGapReason
    unmapped_lane_ids: List[str]
    recommended_action: str


class TriageConsumer:
    """
    AgentSwitchboard consumer for Triage manifests and panels.

    Policy enforcement:
    - human_scheduler_allowed: false
    - panel_ingest_required: true
    - autonomy_gap_classification_required: true
    """

    def __init__(self, policy_path: Optional[Path] = None):
        """Initialize consumer with policy."""
        if policy_path is None:
            policy_path = Path(__file__).parent / "consumer.policy.json"

        with open(policy_path, 'r') as f:
            self.policy = json.load(f)

        # Enforce policy requirements
        assert not self.policy["policy"]["human_scheduler_allowed"], \
            "human_scheduler_allowed must be false"
        assert self.policy["policy"]["panel_ingest_required"], \
            "panel_ingest_required must be true"
        assert self.policy["policy"]["autonomy_gap_classification_required"], \
            "autonomy_gap_classification_required must be true"

    def ingest_manifest(self, manifest_path: Path) -> TriageManifest:
        """
        Ingest Triage prompt-parallel-dispatch manifest as first-class machine input.

        Args:
            manifest_path: Path to manifest JSON file

        Returns:
            Parsed TriageManifest
        """
        with open(manifest_path, 'r') as f:
            data = json.load(f)

        return TriageManifest.from_dict(data)

    def ingest_panel(self, panel_path: Path) -> TriagePanel:
        """
        Ingest Triage panel/lane-prompt transport artifact as first-class machine input.

        Args:
            panel_path: Path to panel JSON file

        Returns:
            Parsed TriagePanel
        """
        with open(panel_path, 'r') as f:
            data = json.load(f)

        return TriagePanel.from_dict(data)

    def classify_autonomy_gap(
        self,
        manifest: Optional[TriageManifest] = None,
        panels: Optional[List[TriagePanel]] = None,
        lane_mappings: Optional[List[LaneMapping]] = None
    ) -> AutonomyGap:
        """
        Classify AUTONOMY_GAP when panels/manifests exist but no adapter executes lanes.

        Args:
            manifest: Optional Triage manifest
            panels: Optional list of Triage panels
            lane_mappings: Optional list of lane mappings

        Returns:
            AutonomyGap classification
        """
        manifest_present = manifest is not None
        panels_present = panels is not None and len(panels) > 0

        if not manifest_present and not panels_present:
            return AutonomyGap(
                gap_detected=False,
                manifest_present=False,
                panels_present=False,
                ready_lanes_count=0,
                unmapped_lanes_count=0,
                gap_reason=AutonomyGapReason.NO_MANIFEST_OR_PANELS,
                unmapped_lane_ids=[],
                recommended_action="No manifest or panels to consume"
            )

        # Count ready lanes (PLANNED status, no blocking dependencies)
        ready_lanes = []
        if manifest:
            ready_lanes = [
                lane for lane in manifest.lanes
                if lane.status == "PLANNED" and not lane.dependencies
            ]

        if not ready_lanes:
            return AutonomyGap(
                gap_detected=False,
                manifest_present=manifest_present,
                panels_present=panels_present,
                ready_lanes_count=0,
                unmapped_lanes_count=0,
                gap_reason=AutonomyGapReason.NO_READY_LANES,
                unmapped_lane_ids=[],
                recommended_action="No dependency-ready PLANNED lanes to dispatch"
            )

        # Check if lanes are mapped
        if lane_mappings is None:
            lane_mappings = []

        unmapped_lanes = [
            lane.lane_id for lane in ready_lanes
            if not any(m.lane_id == lane.lane_id and m.execution_ready for m in lane_mappings)
        ]

        if not unmapped_lanes:
            return AutonomyGap(
                gap_detected=False,
                manifest_present=manifest_present,
                panels_present=panels_present,
                ready_lanes_count=len(ready_lanes),
                unmapped_lanes_count=0,
                gap_reason=AutonomyGapReason.ALL_LANES_MAPPED,
                unmapped_lane_ids=[],
                recommended_action="All ready lanes mapped to ASB descriptors"
            )

        # AUTONOMY_GAP detected
        return AutonomyGap(
            gap_detected=True,
            manifest_present=manifest_present,
            panels_present=panels_present,
            ready_lanes_count=len(ready_lanes),
            unmapped_lanes_count=len(unmapped_lanes),
            gap_reason=AutonomyGapReason.ADAPTERS_UNAVAILABLE,
            unmapped_lane_ids=unmapped_lanes,
            recommended_action="Implement ASB consumer floor to map lanes to ASB descriptors (public-plan, cursor-cloud-agent, local-argv)"
        )

    def map_lane_to_asb_descriptor(self, lane: TriageLane) -> LaneMapping:
        """
        Map Triage lane to ASB execution descriptor.

        This is a structural mapping that does not require live launches.

        Args:
            lane: Triage lane to map

        Returns:
            LaneMapping to ASB descriptor
        """
        # Check for runtime_tool launch mode -> cursor-cloud-agent
        if lane.launch.get("mode") == "runtime_tool":
            tool = lane.launch.get("tool", "")
            if "cursor" in tool.lower() or "cloud" in tool.lower() or "agent" in tool.lower():
                return LaneMapping(
                    lane_id=lane.lane_id,
                    asb_descriptor_kind=AsbDescriptorKind.CURSOR_CLOUD_AGENT,
                    mapping_confidence=MappingConfidence.HIGH,
                    execution_ready=True,
                    cloud_agent_prompt=lane.mission
                )

        # Check for argv launch mode with deterministic command
        if lane.launch.get("mode") == "argv":
            argv = lane.launch.get("argv", [])
            if argv:
                # Deterministic command (no LLM required) -> local-argv
                deterministic_commands = ["python", "python3", "pwsh", "bash", "node", "npm", "pytest"]
                if any(cmd in argv[0].lower() for cmd in deterministic_commands):
                    return LaneMapping(
                        lane_id=lane.lane_id,
                        asb_descriptor_kind=AsbDescriptorKind.LOCAL_ARGV,
                        mapping_confidence=MappingConfidence.HIGH,
                        execution_ready=True,
                        argv=argv,
                        cwd=lane.launch.get("cwd")
                    )
                else:
                    # Non-deterministic argv -> cursor-cloud-agent as fallback
                    return LaneMapping(
                        lane_id=lane.lane_id,
                        asb_descriptor_kind=AsbDescriptorKind.CURSOR_CLOUD_AGENT,
                        mapping_confidence=MappingConfidence.MEDIUM,
                        execution_ready=True,
                        cloud_agent_prompt=lane.mission
                    )

        # Default: unmapped
        return LaneMapping(
            lane_id=lane.lane_id,
            asb_descriptor_kind=AsbDescriptorKind.UNMAPPED,
            mapping_confidence=MappingConfidence.NONE,
            execution_ready=False,
            blocking_reason="No suitable ASB descriptor found for lane adapter"
        )

    def apply_merge_gate_classification(
        self,
        required_checks: List[Dict[str, str]],
        local_proof_exists: bool,
        degradation_reason: Optional[str] = None
    ) -> str:
        """
        Apply merge-gate classification from pr-merge-gate.v1.json.

        degraded provider limits + local_proof => CONTINUE
        true blockers => BLOCKED

        Args:
            required_checks: List of required checks with conclusion status
            local_proof_exists: Whether local proof exists for this exact head
            degradation_reason: Optional reason for degradation

        Returns:
            Classification: "CONTINUE" or "BLOCKED"
        """
        degraded_conclusions = ["skipped", "cancelled", "neutral"]
        allowed_degradation_reasons = [
            "actions_minute_exhaustion",
            "actions_billing_limit",
            "review_bot_usage_limit",
            "ci_provider_usage_limit"
        ]

        # Check if any required checks are degraded
        degraded_checks = [
            check for check in required_checks
            if check.get("conclusion") in degraded_conclusions
        ]

        if not degraded_checks:
            # No degraded checks, normal flow
            return "CONTINUE"

        # Degraded checks found
        if not local_proof_exists:
            return "BLOCKED"

        if degradation_reason not in allowed_degradation_reasons:
            return "BLOCKED"

        # Degraded provider limits + local_proof => CONTINUE
        return "CONTINUE"

    def extract_first_unproven_gate(self, checkpoint: Dict[str, Any]) -> Optional[str]:
        """
        Extract first_unproven_gate from Triage checkpoint.

        Args:
            checkpoint: Triage checkpoint.schema.v1 structure

        Returns:
            First unproven gate or None
        """
        threads = checkpoint.get("threads", [])
        if not threads:
            return None

        # Get first thread's first_unproven_gate
        first_thread = threads[0]
        return first_thread.get("first_unproven_gate")


def main():
    """CLI entrypoint for testing."""
    import argparse

    parser = argparse.ArgumentParser(description="Triage→ASB consumer")
    parser.add_argument("--manifest", type=Path, help="Path to Triage manifest")
    parser.add_argument("--panel", type=Path, help="Path to Triage panel")
    parser.add_argument("--checkpoint", type=Path, help="Path to Triage checkpoint")
    parser.add_argument("--classify-gap", action="store_true",
                       help="Classify AUTONOMY_GAP")

    args = parser.parse_args()

    consumer = TriageConsumer()

    if args.manifest:
        manifest = consumer.ingest_manifest(args.manifest)
        print(f"Ingested manifest: run_id={manifest.run_id}, "
              f"lanes={len(manifest.lanes)}")

        if args.classify_gap:
            gap = consumer.classify_autonomy_gap(manifest=manifest)
            print(f"AUTONOMY_GAP: detected={gap.gap_detected}, "
                  f"reason={gap.gap_reason.value}")

    if args.panel:
        panel = consumer.ingest_panel(args.panel)
        print(f"Ingested panel: panel_id={panel.panel_id}, "
              f"lane_id={panel.lane_id}")

    if args.checkpoint:
        with open(args.checkpoint, 'r') as f:
            checkpoint = json.load(f)
        first_unproven = consumer.extract_first_unproven_gate(checkpoint)
        print(f"First unproven gate: {first_unproven}")


if __name__ == "__main__":
    main()
