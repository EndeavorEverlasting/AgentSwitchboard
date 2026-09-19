#!/usr/bin/env python3
"""Dependency-free canonical-path seam contract for AgentSwitchboard."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))

def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")

def tracked(relative: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", "--", relative],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False,
    )
    return result.returncode == 0

def main() -> None:
    contract_path = "tooling/harness/operational/canonical-path.contract.json"
    workflow_path = "tooling/harness/operational/workflows/canonical-path-proof.workflow.json"
    schema_path = "tooling/harness/operational/schemas/canonical-path-proof.schema.json"
    skill_path = ".ai/skills/canonical-path-proof/SKILL.md"
    report_path = "docs/harness/canonical-path-current-state.md"
    machine_owner = "tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json"
    required = [contract_path, workflow_path, schema_path, skill_path, report_path, machine_owner]
    for relative in required:
        require((ROOT / relative).is_file(), f"missing canonical-path surface: {relative}")
        require(tracked(relative), f"untracked canonical-path surface: {relative}")

    contract = load(contract_path)
    require(contract["schemaVersion"] == 1, "contract schemaVersion")
    require(contract["contractId"] == "agentswitchboard.canonical-path-seam.v1", "contract id")
    require(contract["authority"]["machineProfileOwner"] == machine_owner, "must reuse existing machine-profile owner")
    require(contract["authority"]["deepRepairOwner"] == "P92 Canonical Path Prompt", "P92 deep repair seam missing")
    require(contract["defaultPolicy"]["required"] is True, "canonical path precondition must default required")
    required_before = "\n".join(contract["defaultPolicy"]["requiredBefore"]).lower()
    for token in ("local repository mutation", "validator", "launcher", "operator handoff"):
        require(token in required_before, f"default action precondition missing: {token}")

    roles = {item["role"]: item for item in contract["requiredRoles"]}
    require(set(roles) == {"developmentCheckout","productionUsePath","temporaryWorktreeRoot","realOperatorEntrypoint"}, "role set mismatch")
    binding = contract["currentBindings"]["windowsTechnicianProfile"]
    require(binding["profileOwner"] == machine_owner, "Windows binding must delegate to machine owner")
    require(binding["stableDefaultDevelopmentCheckout"] == r"%USERPROFILE%\dev\AgentSwitchBoard-Live", "stable Windows dev root drift")
    require(binding["temporaryWorktreeRoot"] == r"%LOCALAPPDATA%\AgentSwitchboard\worktrees", "worktree root drift")
    require(binding["pathRelation"] == "same-path", "Windows dev/use relation drift")

    expected_states = [
        "remote-main-contains-sha",
        "canonical-development-checkout-current",
        "production-use-path-current",
        "real-entrypoint-observes-it",
    ]
    states = [item["id"] for item in contract["proofStates"]]
    require(states == expected_states, "proof state order/identity drift")
    for index, state in enumerate(contract["proofStates"][:-1]):
        later = set(expected_states[index+1:])
        require(later.issubset(set(state["doesNotImply"])), f"{state['id']} silently promotes later proof")
    for key in ("secondMutableCloneAllowed","destructiveCleanupAllowed","silentStashAllowed","modelChosenDirectoryAllowed"):
        require(contract["pathSprawl"][key] is False, f"path-sprawl boundary must remain false: {key}")

    workflow = load(workflow_path)
    require(workflow["workflowId"] == "canonical-path-proof", "workflow id")
    workflow_text = read(workflow_path)
    for token in ("git fetch --all --prune --tags","git pull --ff-only","approved isolated worktree",
                  "remote-main-contains-sha","canonical-development-checkout-current",
                  "production-use-path-current","real-entrypoint-observes-it"):
        require(token in workflow_text, f"workflow token missing: {token}")
    for forbidden in ("git reset --hard","git clean","silent stash"):
        require(forbidden in workflow_text.lower(), f"workflow must explicitly forbid: {forbidden}")

    registry = load("tooling/harness/operational/workflow-registry.json")
    preconditions = {item["preconditionId"]: item for item in registry.get("actionPreconditions", [])}
    require("canonical-path-proof" in preconditions, "workflow registry missing default canonical-path precondition")
    require(preconditions["canonical-path-proof"]["defaultRequired"] is True, "canonical-path precondition not default")
    task_intake = read("tooling/harness/operational/workflows/task-intake.workflow.json")
    require("canonical-path-proof" in task_intake, "task intake does not route through canonical path proof")
    require("provider-only remote read" in task_intake.lower(), "task intake exemption boundary missing")

    components = load("tooling/harness/operational/harness-components.registry.json")
    flattened = {p for paths in components["components"].values() for p in paths}
    for relative in (contract_path, workflow_path, schema_path, skill_path, report_path,
                     "scripts/Test-CanonicalPathHarness.ps1", "tests/test_canonical_path_harness.py", machine_owner):
        require(relative in flattened, f"harness component inventory omitted canonical-path surface: {relative}")

    validators = load("tooling/harness/operational/validator-registry.json")
    validator_ids = {item["id"] for item in validators["validators"]}
    require({"canonical-path-python","canonical-path-powershell"}.issubset(validator_ids), "canonical-path validators not registered")

    skill = read(skill_path)
    for token in ("id: canonical-path-proof","status: canonical","## Trigger","## Required inputs","## Procedure",
                  "## Expected outputs","## Known traps","## Deterministic validation","## Forbidden scope"):
        require(token in skill, f"canonical path skill token missing: {token}")
    report = read(report_path)
    for token in ("## Working","## Broken / blocked","## Missing / unproven","## Operator path","## Proof ceiling"):
        require(token in report, f"canonical path operator report missing: {token}")

    schema = load(schema_path)
    require(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "schema draft")
    required_states = set(schema["properties"]["proofStates"]["required"])
    require(required_states == set(expected_states), "receipt schema proof states drift")

    print("PASS: canonical path harness seam")

if __name__ == "__main__":
    main()
