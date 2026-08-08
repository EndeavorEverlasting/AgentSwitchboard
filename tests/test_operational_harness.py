#!/usr/bin/env python3
"""Dependency-free completeness contract for the AgentSwitchboard operational harness."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "harness" / "operational"


def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_file(relative: str) -> Path:
    path = ROOT / relative
    require(path.is_file(), f"missing required file: {relative}")
    return path


def main() -> None:
    required = [
        "HARNESS.md",
        "tooling/harness/operational/manifest.json",
        "tooling/harness/operational/codebase-map.json",
        "tooling/harness/operational/workflow-registry.json",
        "tooling/harness/operational/artifact-registry.json",
        "tooling/harness/operational/validator-registry.json",
        "tooling/harness/operational/workflows/task-intake.workflow.json",
        "tooling/harness/operational/workflows/pre-commit-validation.workflow.json",
        "tooling/harness/operational/workflows/failure-recovery.workflow.json",
        "tooling/harness/operational/workflows/handoff.workflow.json",
        "tooling/harness/operational/schemas/operational-harness-status.schema.json",
        "tooling/harness/operational/schemas/operational-harness-handoff.schema.json",
        "tooling/harness/operational/templates/operator-report.template.md",
        "tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1",
        "tooling/harness/operational/Get-OperationalHarnessStatus.py",
        ".ai/skills/operational-harness-routing/SKILL.md",
        "scripts/Test-OperationalHarness.ps1",
        "tests/test_operational_harness.py",
        "docs/harness/operational-harness.md",
        ".github/workflows/operational-harness.yml",
    ]
    for relative in required:
        require_file(relative)

    manifest = load("tooling/harness/operational/manifest.json")
    require(manifest["schemaVersion"] == 1, "manifest schemaVersion")
    require(manifest["harnessId"] == "agentswitchboard.operational-harness.v1", "manifest harnessId")
    require(manifest["generatedEvidence"]["tracked"] is False, "generated evidence must be untracked")
    require(manifest["hooks"]["implicitInstallationAllowed"] is False, "hooks must be opt-in")
    for path in manifest["entrypoints"].values():
        require_file(path)
    require(manifest["safety"]["networkRequired"] is False, "operational harness may not require network")
    require(manifest["safety"]["liveTargetMutationAllowed"] is False, "live mutation forbidden")
    require(manifest["safety"]["productMutationAllowed"] is False, "product mutation forbidden")
    require(manifest["safety"]["destructiveGitAllowed"] is False, "destructive Git forbidden")
    require(manifest["safety"]["governanceMutationOwned"] is False, "governance mutation not owned")

    codebase = load("tooling/harness/operational/codebase-map.json")
    structure_paths = {item["path"] for item in codebase["structure"]}
    for expected in ("AGENTS.md", ".ai/harness/", ".ai/skills/", "scripts/", "tests/", ".github/workflows/"):
        require(expected in structure_paths, f"codebase map missing {expected}")
    require(codebase["commands"]["build"]["command"] == "none", "generic build must not be invented")
    require(codebase["commands"]["deploy"]["command"] == "none", "generic deploy must not be invented")
    traps = "\n".join(codebase["knownTraps"]).lower()
    require("current shell" in traps and "git checkout" in traps, "cwd/git trap missing")
    require(".trim()" in traps, "null Trim trap missing")
    require("hooks implicitly" in traps, "implicit hook trap missing")
    require("runtime" in traps, "proof promotion trap missing")

    workflow_registry = load("tooling/harness/operational/workflow-registry.json")
    workflows = {item["workflowId"]: item for item in workflow_registry["workflows"]}
    expected_workflows = {"task-intake", "pre-commit-validation", "failure-recovery", "handoff"}
    require(set(workflows) == expected_workflows, "workflow registry must contain exact lifecycle workflows")
    for item in workflows.values():
        require_file(item["path"])
        require_file(item["skill"])
    specialized = "\n".join(item["skill"] for item in workflow_registry["specializedRouting"])
    for skill in (
        ".ai/skills/environment-capability-routing/SKILL.md",
        ".ai/skills/end-to-end-runtime-validation/SKILL.md",
        ".ai/skills/windows-profile-launch-mode-validation/SKILL.md",
        ".ai/skills/pi-fusion-orchestration/SKILL.md",
    ):
        require(skill in specialized, f"specialized route missing {skill}")
        require_file(skill)

    for workflow_id in expected_workflows:
        data = load(f"tooling/harness/operational/workflows/{workflow_id}.workflow.json")
        require(data["workflowId"] == workflow_id, f"workflow id mismatch: {workflow_id}")
        require(data.get("steps"), f"workflow steps missing: {workflow_id}")
        require(data.get("outputs"), f"workflow outputs missing: {workflow_id}")
        require(data.get("proofCeiling"), f"workflow proof ceiling missing: {workflow_id}")

    artifacts = load("tooling/harness/operational/artifact-registry.json")
    require(artifacts["trackedGeneratedArtifacts"] is False, "artifact outputs must be untracked")
    ids = {item["artifactId"] for item in artifacts["artifacts"]}
    require(ids == {"operational-harness-status", "operational-harness-operator-report", "operational-harness-validation-ledger", "operational-harness-handoff"}, "artifact roles mismatch")
    for item in artifacts["artifacts"]:
        require(item["tracked"] is False, f"artifact must be untracked: {item['artifactId']}")
        require(item["proofCeiling"], f"artifact proof ceiling missing: {item['artifactId']}")

    validators = load("tooling/harness/operational/validator-registry.json")
    validator_ids = {item["id"] for item in validators["validators"]}
    for expected in ("operational-python", "operational-powershell", "diff-check", "harness-doctrine", "repository-family", "agent-documentation"):
        require(expected in validator_ids, f"validator registry missing {expected}")
    for item in validators["validators"]:
        require(item["mutatesTarget"] is False, f"registered validator mutates target: {item['id']}")
        require(item["proof"], f"validator proof missing: {item['id']}")

    for schema in (
        "tooling/harness/operational/schemas/operational-harness-status.schema.json",
        "tooling/harness/operational/schemas/operational-harness-handoff.schema.json",
    ):
        data = load(schema)
        require(data["$schema"] == "https://json-schema.org/draft/2020-12/schema", f"schema draft: {schema}")
        require(data["title"], f"schema title: {schema}")

    skill = require_file(".ai/skills/operational-harness-routing/SKILL.md").read_text(encoding="utf-8")
    for token in (
        "id: operational-harness-routing", "status: canonical", "## Trigger", "## Inputs", "## Procedure", "## Outputs", "## Deterministic validation", "## Forbidden scope", "## Stop and escalate", "Do not assume the current shell directory is a checkout",
    ):
        require(token in skill, f"skill token missing: {token}")

    hook = require_file("tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1").read_text(encoding="utf-8")
    require("Test-OperationalHarness.ps1" in hook, "hook must run owning validator")
    require("diff --cached --check" in hook, "hook must run staged diff check")
    for forbidden in ("core.hookspath", "git config", "reset --hard", "git clean", "force-push"):
        require(forbidden not in hook.lower(), f"hook contains forbidden behavior: {forbidden}")

    workflow = require_file(".github/workflows/operational-harness.yml").read_text(encoding="utf-8")
    for token in (
        "python3 tests/test_operational_harness.py",
        "scripts/Test-OperationalHarness.ps1",
        "git diff --check",
        "tests/test_environment_capability_harness.py",
        "tests/test_device_profile_launcher_contract.py",
        "git worktree add --detach",
        "[INHERITED-BASELINE]",
        "[REGRESSION]",
    ):
        require(token in workflow, f"CI token missing: {token}")

    guide = require_file("docs/harness/operational-harness.md").read_text(encoding="utf-8")
    for token in ("newcomer control surface", "task-intake", "pre-commit-validation", "failure-recovery", "handoff", "Artifact registry", "Optional hook", "Proof ceiling"):
        require(token in guide, f"operator guide token missing: {token}")

    with tempfile.TemporaryDirectory() as temp_dir:
        result = subprocess.run(
            [sys.executable, str(HARNESS / "Get-OperationalHarnessStatus.py"), "--task", "validate a cross-environment tmux task", "--output-root", temp_dir],
            cwd=Path(temp_dir), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        require(result.returncode == 0, f"status reporter exit={result.returncode} stdout={result.stdout!r} stderr={result.stderr!r}")
        for name in ("operational-harness-status.json", "operational-harness-report.md", "operational-harness-validation-ledger.json", "operational-harness-handoff.json"):
            require((Path(temp_dir) / name).is_file(), f"status reporter missing {name}")
        status = json.loads((Path(temp_dir) / "operational-harness-status.json").read_text(encoding="utf-8"))
        require(status["routing"]["workflow"] == "pre-commit-validation", "task routing should select validation")
        require(status["routing"]["specializedSkill"] == ".ai/skills/environment-capability-routing/SKILL.md", "cross-environment task should route to environment skill")

    print("PASS: operational harness completeness and routing contract")


if __name__ == "__main__":
    main()
