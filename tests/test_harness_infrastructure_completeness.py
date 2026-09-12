#!/usr/bin/env python3
"""Dependency-free tracked-completeness contract for AgentSwitchboard harness infrastructure."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "tooling/harness/operational/harness-components.registry.json"

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")

def load(relative: str) -> dict:
    return json.loads(read(relative))

def is_tracked(relative: str) -> bool:
    result = subprocess.run(["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", relative], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    return result.returncode == 0

def main() -> None:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    require(registry["schemaVersion"] == 1, "registry schemaVersion")
    require(registry["registryId"] == "agentswitchboard.harness-components.v1", "registry id")
    safety = registry["safety"]
    for key in ("governanceMutationOwned", "productMutationOwned", "destructiveGitAllowed", "implicitHookInstallationAllowed", "remoteMergeImpliesLocalAvailability", "modelChosenCanonicalPathAllowed", "secondMutableCloneAllowed"):
        require(safety[key] is False, f"safety boundary must remain false: {key}")

    groups = {"codebaseMaps", "workflowSpecs", "artifactRegistries", "validators", "hooks", "skills", "operatorReports", "discoveryAndAutomation"}
    require(set(registry["components"]) == groups, "component groups changed unexpectedly")
    component_paths: list[str] = []
    for group, paths in registry["components"].items():
        require(paths, f"empty harness component group: {group}")
        for relative in paths:
            require((ROOT / relative).is_file(), f"missing component: {relative}")
            require(is_tracked(relative), f"untracked component: {relative}")
            if relative not in component_paths:
                component_paths.append(relative)

    for required in (
        "CODEBASE_MAP.md", "tooling/harness/operational/codebase-map.json",
        "tooling/harness/operational/workflow-registry.json", "tooling/harness/operational/artifact-registry.json",
        "tooling/harness/operational/validator-registry.json",
        "tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1",
        "tooling/harness/operational/hooks/Invoke-OperationalHarnessPrePush.ps1",
        ".ai/skills/operational-harness-routing/SKILL.md", "docs/harness/operational-harness.md",
        "tooling/harness/operational/canonical-path.contract.json",
        "tooling/harness/operational/workflows/canonical-path-proof.workflow.json",
        "tooling/harness/operational/schemas/canonical-path-proof.schema.json",
        ".ai/skills/canonical-path-proof/SKILL.md", "docs/harness/canonical-path-current-state.md",
        "scripts/Test-CanonicalPathHarness.ps1", "tests/test_canonical_path_harness.py",
        "tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json",
    ):
        require(required in component_paths, f"canonical harness owner omitted from registry: {required}")

    adoption_path = "tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json"
    adoption = load(adoption_path)
    require(adoption["workflowId"] == "post-integration-local-adoption", "local adoption workflow id")
    require(adoption["steps"] and adoption["outputs"] and adoption["proofCeiling"], "local adoption workflow incomplete")
    adoption_text = read(adoption_path)
    for token in ("canonical-path.contract.json", "git fetch --all --prune --tags", "refs/remotes/origin/HEAD", "git merge-base --is-ancestor", "git pull --ff-only", "approved isolated worktree", "remote-main-contains-sha", "canonical-development-checkout-current", "production-use-path-current", "real-entrypoint-observes-it"):
        require(token in adoption_text, f"local adoption token missing: {token}")

    skill = read(".ai/skills/post-integration-local-adoption/SKILL.md")
    for token in ("id: post-integration-local-adoption", "status: canonical", "## Trigger", "## Required inputs", "## Procedure", "## Expected outputs", "## Known trap", "## Forbidden scope", "canonical-path.contract.json", "git fetch --all --prune --tags", "git pull --ff-only", "approved isolated worktree", "does not"):
        require(token in skill, f"local adoption skill token missing: {token}")

    workflow_registry = load("tooling/harness/operational/workflow-registry.json")
    preconditions = {item["preconditionId"]: item for item in workflow_registry.get("actionPreconditions", [])}
    require("canonical-path-proof" in preconditions, "canonical-path action precondition missing")
    require(preconditions["canonical-path-proof"]["defaultRequired"] is True, "canonical-path action precondition must be default")
    task_intake = read("tooling/harness/operational/workflows/task-intake.workflow.json")
    require("canonical-path-proof" in task_intake, "task intake must invoke canonical-path precondition")
    require("provider-only remote read" in task_intake.lower(), "task intake exemption boundary missing")

    harness = read("HARNESS.md")
    for token in ("harness-components.registry.json", "Test-HarnessInfrastructureCompleteness.ps1", "operational-harness-routing/SKILL.md", "post-integration-local-adoption.workflow.json", "post-integration-local-adoption/SKILL.md", "workflow-registry.json"):
        require(token in harness, f"HARNESS.md discovery token missing: {token}")

    contract = load("tooling/harness/operational/canonical-path.contract.json")
    require(contract["authority"]["machineProfileOwner"] == "tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json", "canonical path seam must reuse machine profile owner")
    require(contract["authority"]["deepRepairOwner"] == "P92 Canonical Path Prompt", "P92 seam missing")
    require(contract["defaultPolicy"]["required"] is True, "canonical path default required")
    expected_states = ["remote-main-contains-sha", "canonical-development-checkout-current", "production-use-path-current", "real-entrypoint-observes-it"]
    require([item["id"] for item in contract["proofStates"]] == expected_states, "canonical proof-state identity/order drift")
    for key in ("secondMutableCloneAllowed", "destructiveCleanupAllowed", "silentStashAllowed", "modelChosenDirectoryAllowed"):
        require(contract["pathSprawl"][key] is False, f"path-sprawl boundary must remain false: {key}")

    report = read("docs/harness/operational-harness-current-state.md")
    for token in ("## Working", "## Broken / blocked", "## Missing / unproven", "## Operator path", "## Proof ceiling", "canonical-path.contract.json"):
        require(token in report, f"operator state report token missing: {token}")
    canonical_report = read("docs/harness/canonical-path-current-state.md")
    for token in ("## Working", "## Broken / blocked", "## Missing / unproven", "## Operator path", "## Proof ceiling", "PR #149"):
        require(token in canonical_report, f"canonical path report token missing: {token}")

    workflow = read(".github/workflows/harness-infrastructure-completeness.yml")
    for token in ("python3 tests/test_harness_infrastructure_completeness.py", "scripts/Test-HarnessInfrastructureCompleteness.ps1", "tests/test_canonical_path_harness.py", "scripts/Test-CanonicalPathHarness.ps1", "persist-credentials: false", "git diff --check", "runs-on: windows-latest", "runs-on: ubuntu-latest"):
        require(token in workflow, f"hosted harness workflow token missing: {token}")

    canonical_result = subprocess.run([sys.executable, str(ROOT / "tests/test_canonical_path_harness.py")], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    require(canonical_result.returncode == 0, f"canonical path harness failed: {canonical_result.stdout}{canonical_result.stderr}")

    print(f"PASS: harness infrastructure completeness ({len(component_paths)} tracked components)")

if __name__ == "__main__":
    main()
