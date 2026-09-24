from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling" / "profiles" / "windows" / "harness" / "machine-profile"

class ContractFailure(RuntimeError):
    pass

def check(condition: object, message: str) -> None:
    if not condition:
        raise ContractFailure(message)

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def main() -> None:
    codebase = load(BASE / "codebase-map.json")
    current_registry = load(BASE / "machine-profile.registry.json")
    roles = load(BASE / "environment-role.registry.json")
    role_schema = load(BASE / "schemas" / "environment-role-registry.schema.json")
    traps = load(BASE / "known-traps.registry.json")
    artifacts = load(BASE / "artifact-registry.json")
    workflows = load(BASE / "workflows" / "operational-workflows.json")
    ops = codebase["operationalHarness"]

    check(codebase["canonicalOwner"] == "tooling/profiles/windows/Get-AgentSwitchboardMachineProfile.ps1", "canonical detector owner drifted")
    check(current_registry["pathRoles"]["developmentCheckout"] == r"%USERPROFILE%\dev\AgentSwitchBoard-Live", "current path policy drifted")
    check(ops["salvage"]["sourcePullRequest"] == 64, "PR #64 provenance missing")
    check(ops["salvage"]["sourceHead"] == "45b44b158d7f44e18dfbc6c24120a0c02924f48b", "PR #64 source head drifted")

    check(roles["schema"] == role_schema["properties"]["schema"]["const"], "role registry schema id drifted")
    check(roles["pathPolicyOwner"] == role_schema["properties"]["pathPolicyOwner"]["const"], "role path-policy owner drifted")
    role_ids = [item["roleId"] for item in roles["roles"]]
    check(set(role_ids) == {"personal-windows-laptop","desktop-workstation","admin-box-1","admin-box-2"}, f"role set drifted: {role_ids}")
    for role in roles["roles"]:
        check(role["selectionMode"] == "explicit-or-local-binding", f"role can be inferred: {role['roleId']}")
        check(role["repositoryPathSource"] == "machine-profile:pathRoles.developmentCheckout", f"role owns path policy: {role['roleId']}")
        check(role["committedResolvedPathAllowed"] is False, f"role allows committed local path: {role['roleId']}")

    serialized_roles = json.dumps(roles)
    check("%USERPROFILE%\\Desktop\\Dev" not in serialized_roles, "stale Desktop path policy was revived")
    check("OneDrive -" not in serialized_roles, "tenant-specific path label was revived")

    trap_ids = {item["id"] for item in traps["traps"]}
    check({"remembered-path","role-profile-conflation","path-role-collapse","downstream-after-failure","cwd-relative-next-command","pull-over-local-patch"} <= trap_ids, "operational traps incomplete")
    for artifact in artifacts["generatedArtifacts"]:
        check(artifact["tracked"] is False, f"generated artifact is tracked: {artifact['id']}")
    workflow_ids = {item["workflowId"] for item in workflows["workflows"]}
    check(workflow_ids == {"machine-profile-task-intake","machine-profile-validation","machine-profile-failure-recovery","machine-profile-handoff"}, f"workflow set drifted: {workflow_ids}")

    retired = set(ops["salvage"]["retire"])
    check("historical candidate-validation wrappers" in retired, "stale candidate validator was not retired")
    check("historical pre-commit hook" in retired, "stale hook was not retired")
    check(".ai/skills/machine-profile-bootstrap/SKILL.md" not in ops["requiredTracked"], "operational leaf must not duplicate skill ownership")

    required = [ROOT / path for path in ops["requiredTracked"]]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    check(not missing, f"missing operational harness files: {missing}")

    print("PASS: machine-profile operational harness contract")

if __name__ == "__main__":
    try:
        main()
    except ContractFailure as exc:
        print(f"FAIL: {exc}")
        raise SystemExit(1) from exc
