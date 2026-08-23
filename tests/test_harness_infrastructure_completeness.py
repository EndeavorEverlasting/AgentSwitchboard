#!/usr/bin/env python3
"""Dependency-free tracked-completeness contract for AgentSwitchboard harness infrastructure."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess

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
    for key in ("governanceMutationOwned", "productMutationOwned", "destructiveGitAllowed", "implicitHookInstallationAllowed", "remoteMergeImpliesLocalAvailability"):
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
    ):
        require(required in component_paths, f"canonical harness owner omitted from registry: {required}")

    adoption_path = "tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json"
    adoption = load(adoption_path)
    require(adoption["workflowId"] == "post-integration-local-adoption", "local adoption workflow id")
    require(adoption["steps"] and adoption["outputs"] and adoption["proofCeiling"], "local adoption workflow incomplete")
    adoption_text = read(adoption_path)
    for token in ("git fetch --all --prune --tags", "refs/remotes/origin/HEAD", "git merge-base --is-ancestor", "git pull --ff-only", "isolated worktree", "git ls-files --error-unmatch", "claiming remote merge means a local checkout already has the file"):
        require(token in adoption_text, f"local adoption token missing: {token}")

    skill = read(".ai/skills/post-integration-local-adoption/SKILL.md")
    for token in ("id: post-integration-local-adoption", "status: canonical", "## Trigger", "## Required inputs", "## Procedure", "## Expected outputs", "## Known trap", "## Forbidden scope", "git fetch --all --prune --tags", "git pull --ff-only", "isolated worktree", "does not", "workstation checkout"):
        require(token in skill, f"local adoption skill token missing: {token}")

    harness = read("HARNESS.md")
    for token in ("harness-components.registry.json", "Test-HarnessInfrastructureCompleteness.ps1", "operational-harness-routing/SKILL.md", "post-integration-local-adoption.workflow.json", "post-integration-local-adoption/SKILL.md"):
        require(token in harness, f"HARNESS.md discovery token missing: {token}")

    report = read("docs/harness/operational-harness-current-state.md")
    for token in ("## Working", "## Broken / blocked", "## Missing / unproven", "## Operator path", "## Proof ceiling"):
        require(token in report, f"operator state report token missing: {token}")

    workflow = read(".github/workflows/harness-infrastructure-completeness.yml")
    for token in ("python3 tests/test_harness_infrastructure_completeness.py", "scripts/Test-HarnessInfrastructureCompleteness.ps1", "persist-credentials: false", "git diff --check", "runs-on: windows-latest", "runs-on: ubuntu-latest"):
        require(token in workflow, f"hosted harness workflow token missing: {token}")

    print(f"PASS: harness infrastructure completeness ({len(component_paths)} tracked components)")

if __name__ == "__main__":
    main()
