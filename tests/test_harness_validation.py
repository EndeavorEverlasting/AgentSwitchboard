"""Unit tests for the repository-family harness Python validator.

These tests run without PowerShell and validate the same contract surface
that scripts/Test-RepositoryFamilyHarness.ps1 checks on Windows.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = REPO_ROOT / "scripts" / "validate_harness.py"


def test_validator_script_exists() -> None:
    assert VALIDATOR.is_file(), "Python validator must be present"


def test_validator_exits_zero_on_current_repo() -> None:
    result = subprocess.run(
        [sys.executable, str(VALIDATOR)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"validator failed: {result.stdout}\n{result.stderr}"
    assert "passed / 0 failed" in result.stdout, "validator must report all checks passing"


def test_validator_output_contains_required_checks() -> None:
    result = subprocess.run(
        [sys.executable, str(VALIDATOR)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0
    stdout = result.stdout
    for marker in [
        "manifest/harness-id",
        "registry/repository-count",
        "artifact-registry/count",
        "workflow/forbidden/clone",
        "schema/.ai/harness/schemas/run-context.schema.json/draft",
    ]:
        assert marker in stdout, f"missing expected check: {marker}"


def test_manifest_declares_untracked_evidence() -> None:
    manifest_path = REPO_ROOT / ".ai" / "harness" / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    assert manifest["generatedEvidence"]["tracked"] is False


def test_registry_has_four_repositories() -> None:
    registry_path = REPO_ROOT / ".ai" / "harness" / "repository-family.registry.json"
    registry = json.loads(registry_path.read_text(encoding="utf-8-sig"))
    assert len(registry["repositories"]) == 4


def test_artifact_registry_all_untracked() -> None:
    artifact_path = REPO_ROOT / ".ai" / "harness" / "artifact-registry.json"
    artifacts = json.loads(artifact_path.read_text(encoding="utf-8-sig"))
    for artifact in artifacts["artifacts"]:
        assert artifact["tracked"] is False
        assert artifact["sensitivity"] == "local-operational"


def test_workflow_forbids_mutation() -> None:
    workflow_path = REPO_ROOT / ".ai" / "harness" / "workflows" / "repository-family-intake.workflow.json"
    workflow = json.loads(workflow_path.read_text(encoding="utf-8-sig"))
    forbidden = workflow["forbidden"]
    for token in ["clone", "fetch", "push", "merge", "provider invocation", "live target mutation"]:
        assert token in forbidden, f"missing forbidden token: {token}"


def test_registry_does_not_embed_machine_paths() -> None:
    registry_path = REPO_ROOT / ".ai" / "harness" / "repository-family.registry.json"
    raw = registry_path.read_text(encoding="utf-8-sig")
    assert not os.path.isabs(raw) or "/home/" not in raw
