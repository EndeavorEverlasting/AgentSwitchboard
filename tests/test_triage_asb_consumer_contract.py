#!/usr/bin/env python3
"""
Pytest tests for Triage→ASB consumer contract floor.

Tests:
- Policy enforcement (human_scheduler_allowed:false, panel_ingest_required:true)
- Schema validation against fixtures
- Manifest ingestion
- Panel ingestion
- Checkpoint processing
- AUTONOMY_GAP classification
- Lane mapping to ASB descriptors
- Merge-gate classification with degraded provider + local_proof => CONTINUE
"""

import json
import pytest
from pathlib import Path
import sys

# Add triage-consumer to path
REPO_ROOT = Path(__file__).parent.parent
CONSUMER_ROOT = REPO_ROOT / "tooling/harness/triage-consumer"
sys.path.insert(0, str(CONSUMER_ROOT))

from triage_consumer import (
    TriageConsumer,
    TriageManifest,
    TriagePanel,
    TriageLane,
    LaneMapping,
    AutonomyGap,
    AsbDescriptorKind,
    MappingConfidence,
    AutonomyGapReason
)


@pytest.fixture
def consumer():
    """Create TriageConsumer instance."""
    return TriageConsumer()


@pytest.fixture
def example_manifest_path():
    """Path to example manifest fixture."""
    return CONSUMER_ROOT / "fixtures/example-manifest.json"


@pytest.fixture
def example_panel_path():
    """Path to example panel fixture."""
    return CONSUMER_ROOT / "fixtures/example-panel.json"


@pytest.fixture
def example_checkpoint_path():
    """Path to example checkpoint fixture."""
    return CONSUMER_ROOT / "fixtures/example-checkpoint.json"


@pytest.fixture
def policy_path():
    """Path to consumer policy."""
    return CONSUMER_ROOT / "consumer.policy.json"


class TestPolicy:
    """Test consumer policy enforcement."""
    
    def test_policy_exists(self, policy_path):
        """Test policy file exists and is valid JSON."""
        assert policy_path.exists()
        with open(policy_path, 'r') as f:
            policy = json.load(f)
        assert policy is not None
    
    def test_human_scheduler_not_allowed(self, consumer):
        """Test human_scheduler_allowed is false."""
        assert consumer.policy["policy"]["human_scheduler_allowed"] is False
    
    def test_panel_ingest_required(self, consumer):
        """Test panel_ingest_required is true."""
        assert consumer.policy["policy"]["panel_ingest_required"] is True
    
    def test_autonomy_gap_classification_required(self, consumer):
        """Test autonomy_gap_classification_required is true."""
        assert consumer.policy["policy"]["autonomy_gap_classification_required"] is True
    
    def test_manifest_and_panels_are_machine_inputs(self, consumer):
        """Test manifest_and_panels_are_machine_inputs is true."""
        assert consumer.policy["policy"]["manifest_and_panels_are_machine_inputs"] is True
    
    def test_panel_deletion_forbidden(self, consumer):
        """Test panel_deletion_forbidden is true."""
        assert consumer.policy["policy"]["panel_deletion_forbidden"] is True


class TestSchemas:
    """Test schema files are valid."""
    
    def test_manifest_schema_valid(self):
        """Test manifest schema is valid JSON."""
        schema_path = CONSUMER_ROOT / "schemas/triage-manifest.schema.json"
        assert schema_path.exists()
        with open(schema_path, 'r') as f:
            schema = json.load(f)
        assert "$schema" in schema
        assert "$id" in schema
    
    def test_panel_schema_valid(self):
        """Test panel schema is valid JSON."""
        schema_path = CONSUMER_ROOT / "schemas/triage-panel.schema.json"
        assert schema_path.exists()
        with open(schema_path, 'r') as f:
            schema = json.load(f)
        assert "$schema" in schema
        assert "$id" in schema
    
    def test_checkpoint_schema_valid(self):
        """Test checkpoint schema is valid JSON."""
        schema_path = CONSUMER_ROOT / "schemas/triage-checkpoint.schema.json"
        assert schema_path.exists()
        with open(schema_path, 'r') as f:
            schema = json.load(f)
        assert "$schema" in schema
        assert "$id" in schema
    
    def test_lane_mapping_schema_valid(self):
        """Test lane-mapping schema is valid JSON."""
        schema_path = CONSUMER_ROOT / "schemas/lane-mapping.schema.json"
        assert schema_path.exists()
        with open(schema_path, 'r') as f:
            schema = json.load(f)
        assert "$schema" in schema
        assert "$id" in schema
    
    def test_autonomy_gap_schema_valid(self):
        """Test autonomy-gap schema is valid JSON."""
        schema_path = CONSUMER_ROOT / "schemas/autonomy-gap.schema.json"
        assert schema_path.exists()
        with open(schema_path, 'r') as f:
            schema = json.load(f)
        assert "$schema" in schema
        assert "$id" in schema


class TestFixtures:
    """Test fixture files are valid."""
    
    def test_example_manifest_valid(self, example_manifest_path):
        """Test example manifest fixture is valid JSON."""
        assert example_manifest_path.exists()
        with open(example_manifest_path, 'r') as f:
            manifest = json.load(f)
        assert manifest["schema_version"] == "prompt-parallel-dispatch/v1"
        assert "run_id" in manifest
        assert "lanes" in manifest
    
    def test_example_panel_valid(self, example_panel_path):
        """Test example panel fixture is valid JSON."""
        assert example_panel_path.exists()
        with open(example_panel_path, 'r') as f:
            panel = json.load(f)
        assert "panel_id" in panel
        assert "lane_id" in panel
        assert "prompt_content" in panel
    
    def test_example_checkpoint_valid(self, example_checkpoint_path):
        """Test example checkpoint fixture is valid JSON."""
        assert example_checkpoint_path.exists()
        with open(example_checkpoint_path, 'r') as f:
            checkpoint = json.load(f)
        assert checkpoint["handoff_version"] == "live-thread-p02-checkpoint/v1"
        assert "threads" in checkpoint


class TestManifestIngestion:
    """Test Triage manifest ingestion as first-class machine input."""
    
    def test_ingest_manifest(self, consumer, example_manifest_path):
        """Test manifest ingestion."""
        manifest = consumer.ingest_manifest(example_manifest_path)
        assert isinstance(manifest, TriageManifest)
        assert manifest.schema_version == "prompt-parallel-dispatch/v1"
        assert manifest.run_id == "triage-2026-09-19-001"
        assert manifest.graph_width == 2
        assert manifest.parallel_disposition == "REQUIRED"
        assert len(manifest.lanes) == 2
    
    def test_manifest_lanes_parsed(self, consumer, example_manifest_path):
        """Test manifest lanes are correctly parsed."""
        manifest = consumer.ingest_manifest(example_manifest_path)
        lane = manifest.lanes[0]
        assert isinstance(lane, TriageLane)
        assert lane.lane_id == "lane-01-policy"
        assert lane.mission != ""
        assert lane.status == "PLANNED"


class TestPanelIngestion:
    """Test Triage panel ingestion as first-class machine input."""
    
    def test_ingest_panel(self, consumer, example_panel_path):
        """Test panel ingestion."""
        panel = consumer.ingest_panel(example_panel_path)
        assert isinstance(panel, TriagePanel)
        assert panel.panel_id == "panel-01"
        assert panel.lane_id == "lane-01-policy"
        assert panel.sprint_name == "P07 Triage ASB Consumer Floor"
        assert len(panel.prompt_content) > 0
    
    def test_panel_scope_parsed(self, consumer, example_panel_path):
        """Test panel scope is correctly parsed."""
        panel = consumer.ingest_panel(example_panel_path)
        assert len(panel.owned_scope) > 0
        assert len(panel.forbidden_scope) > 0
        assert "tooling/harness/triage-consumer/consumer.policy.json" in panel.owned_scope


class TestAutonomyGapClassification:
    """Test AUTONOMY_GAP classification."""
    
    def test_no_manifest_or_panels(self, consumer):
        """Test no gap when no manifest or panels."""
        gap = consumer.classify_autonomy_gap()
        assert isinstance(gap, AutonomyGap)
        assert gap.gap_detected is False
        assert gap.gap_reason == AutonomyGapReason.NO_MANIFEST_OR_PANELS
    
    def test_gap_detected_with_unmapped_lanes(self, consumer, example_manifest_path):
        """Test AUTONOMY_GAP detected when lanes are unmapped."""
        manifest = consumer.ingest_manifest(example_manifest_path)
        gap = consumer.classify_autonomy_gap(manifest=manifest, lane_mappings=[])
        assert gap.gap_detected is True
        assert gap.gap_reason == AutonomyGapReason.ADAPTERS_UNAVAILABLE
        assert gap.ready_lanes_count == 2
        assert gap.unmapped_lanes_count == 2
        assert len(gap.unmapped_lane_ids) == 2
    
    def test_no_gap_when_all_lanes_mapped(self, consumer, example_manifest_path):
        """Test no AUTONOMY_GAP when all lanes are mapped."""
        manifest = consumer.ingest_manifest(example_manifest_path)
        lane_mappings = [
            LaneMapping(
                lane_id="lane-01-policy",
                asb_descriptor_kind=AsbDescriptorKind.CURSOR_CLOUD_AGENT,
                mapping_confidence=MappingConfidence.HIGH,
                execution_ready=True
            ),
            LaneMapping(
                lane_id="lane-02-schemas",
                asb_descriptor_kind=AsbDescriptorKind.CURSOR_CLOUD_AGENT,
                mapping_confidence=MappingConfidence.HIGH,
                execution_ready=True
            )
        ]
        gap = consumer.classify_autonomy_gap(manifest=manifest, lane_mappings=lane_mappings)
        assert gap.gap_detected is False
        assert gap.gap_reason == AutonomyGapReason.ALL_LANES_MAPPED


class TestLaneMapping:
    """Test lane mapping to ASB descriptors."""
    
    def test_map_runtime_tool_to_cloud_agent(self, consumer, example_manifest_path):
        """Test runtime_tool lanes map to cursor-cloud-agent."""
        manifest = consumer.ingest_manifest(example_manifest_path)
        lane = manifest.lanes[0]  # Has runtime_tool launch mode
        mapping = consumer.map_lane_to_asb_descriptor(lane)
        assert isinstance(mapping, LaneMapping)
        assert mapping.asb_descriptor_kind == AsbDescriptorKind.CURSOR_CLOUD_AGENT
        assert mapping.mapping_confidence == MappingConfidence.HIGH
        assert mapping.execution_ready is True
    
    def test_map_argv_deterministic_to_local(self, consumer):
        """Test deterministic argv lanes map to local-argv."""
        lane = TriageLane(
            lane_id="test-lane",
            mission="Run pytest",
            dependencies=[],
            owned_mutation_surfaces=[],
            forbidden_surfaces=[],
            adapter={"kind": "local_process", "rung": 5},
            launch={"mode": "argv", "argv": ["python3", "-m", "pytest", "-v"]},
            expected_artifacts=[],
            validation=[],
            convergence_owner="test",
            status="PLANNED"
        )
        mapping = consumer.map_lane_to_asb_descriptor(lane)
        assert mapping.asb_descriptor_kind == AsbDescriptorKind.LOCAL_ARGV
        assert mapping.mapping_confidence == MappingConfidence.HIGH
        assert mapping.execution_ready is True
        assert mapping.argv == ["python3", "-m", "pytest", "-v"]


class TestMergeGateClassification:
    """Test merge-gate classification with degraded provider + local_proof."""
    
    def test_continue_with_degraded_and_local_proof(self, consumer):
        """Test CONTINUE when degraded checks + local proof exists."""
        required_checks = [
            {"name": "CI", "conclusion": "skipped"}
        ]
        result = consumer.apply_merge_gate_classification(
            required_checks=required_checks,
            local_proof_exists=True,
            degradation_reason="actions_minute_exhaustion"
        )
        assert result == "CONTINUE"
    
    def test_blocked_without_local_proof(self, consumer):
        """Test BLOCKED when degraded checks but no local proof."""
        required_checks = [
            {"name": "CI", "conclusion": "skipped"}
        ]
        result = consumer.apply_merge_gate_classification(
            required_checks=required_checks,
            local_proof_exists=False,
            degradation_reason="actions_minute_exhaustion"
        )
        assert result == "BLOCKED"
    
    def test_continue_with_no_degraded_checks(self, consumer):
        """Test CONTINUE when no degraded checks."""
        required_checks = [
            {"name": "CI", "conclusion": "success"}
        ]
        result = consumer.apply_merge_gate_classification(
            required_checks=required_checks,
            local_proof_exists=False,
            degradation_reason=None
        )
        assert result == "CONTINUE"


class TestCheckpointProcessing:
    """Test checkpoint processing and first_unproven_gate extraction."""
    
    def test_extract_first_unproven_gate(self, consumer, example_checkpoint_path):
        """Test extracting first_unproven_gate from checkpoint."""
        with open(example_checkpoint_path, 'r') as f:
            checkpoint = json.load(f)
        
        first_unproven = consumer.extract_first_unproven_gate(checkpoint)
        assert first_unproven == "merge-gate-validation"
    
    def test_extract_none_for_empty_checkpoint(self, consumer):
        """Test extracting from empty checkpoint returns None."""
        checkpoint = {"threads": []}
        first_unproven = consumer.extract_first_unproven_gate(checkpoint)
        assert first_unproven is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
