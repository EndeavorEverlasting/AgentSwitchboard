from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling" / "profiles" / "windows"
CONTRACT = BASE / "harness" / "machine-profile" / "personal-workstation-bootstrap.v1.json"
ROLES = BASE / "harness" / "machine-profile" / "environment-role.registry.json"
SCRIPT = BASE / "Get-PersonalWorkstationBootstrapStatus.ps1"
DOC = ROOT / "docs" / "workstation" / "personal-development-workstation.md"


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def validate_contract(data: dict, roles: dict) -> None:
    check(data["schema"] == "agentswitchboard.personal-workstation-bootstrap.v1", "wrong contract schema")
    ids = [stage["id"] for stage in data["stages"]]
    check(len(set(ids)) == len(ids), "stage IDs are not unique")
    check(ids[:3] == ["windows-foundation", "native-agents", "first-repo-smoke"], "code-now dependency floor changed")
    for index, stage in enumerate(data["stages"]):
        for dep in stage["dependencies"]:
            check(dep in ids[:index], f"forward or unknown dependency: {dep}")
        component_ids = [c["id"] for c in stage["components"]]
        check(len(set(component_ids)) == len(component_ids), f"duplicated component in {stage['id']}")
    allowed = {"desktop-workstation", "personal-windows-laptop"}
    check(set(data["roles"]) == allowed, "personal roles incorrectly extended")
    check(set(data["roles"]) <= {r["roleId"] for r in roles["roles"]}, "roles not in canonical registry")
    check(not allowed & set(data["roleExclusions"]), "personal/excluded role overlap")
    check({"admin-box-1", "admin-box-2"} <= set(data["roleExclusions"]), "managed admin boxes no longer excluded")
    check(data["roleSelection"] == "explicit-or-local-binding-only", "implicit role selection enabled")
    check(data["repoPathSource"] == "machine-profile:pathRoles.developmentCheckout", "path owner forked")
    profiles = {p["id"]: set(p["requires"]) for p in data["profiles"]}
    check({"code-now", "engineering-full"} == set(profiles), "profile choice drifted")
    check(profiles["code-now"] == set(ids[:3]), "code-now expanded beyond first useful task")
    check(profiles["engineering-full"] == set(ids), "full profile missing stage")
    check(data["authority"]["crewRuntime"].startswith("FirstMate"), "ASB should not become crew runtime")

    foundation = {x["id"]: x for x in data["stages"][0]["components"]}
    check({"powershell7", "git", "node-lts", "github-cli"} <= set(foundation), "foundation missing tools")
    check(foundation["node-lts"]["minimumMajor"] >= 22, "Auggie Node floor regressed")
    native = {x["id"]: x for x in data["stages"][1]["components"]}
    check(native["codex"]["npmPackage"] == "@openai/codex", "Codex package identity drifted")
    check(native["auggie"]["npmPackage"] == "@augmentcode/auggie", "Auggie package identity drifted")
    check(native["agy"]["id"] != native["auggie"]["id"], "AGY/Auggie conflated")

    src = SCRIPT.read_text(encoding="utf-8")
    guide = DOC.read_text(encoding="utf-8")
    check("Inspect ONLY".lower() in src.lower(), "inspection-only contract not visible")
    check("Get-Command" in src and "status.json" in src and "status.md" in src, "inspector not evidence-backed")
    check("[Parameter(Mandatory)]" in src and "EnvironmentRoleId" in src, "explicit role selector absent")
    check("winget install" in guide and "npm.cmd install -g" in guide, "operator fast path incomplete")
    check("Technician-AgentSwitchboard-Ready.cmd" in guide, "canonical setup path not reused")
    check("Auggie" in guide and "AGY" in guide, "agent identity distinction absent")
    for prohibited in ("Clear-Disk", "Format-Volume", "reset --hard", "Remove-Item -Recurse", "winget install", "npm install"):
        check(prohibited not in src, f"inspector has a mutation phrase: {prohibited}")


def main() -> None:
    data = json.loads(CONTRACT.read_text(encoding="utf-8-sig"))
    roles = json.loads(ROLES.read_text(encoding="utf-8-sig"))
    validate_contract(data, roles)

    # Mutation/negative checks keep repeat failures from being accepted.
    import copy
    broken = copy.deepcopy(data)
    broken["roles"].append("admin-box-1")
    try:
        validate_contract(broken, roles)
    except AssertionError:
        pass
    else:
        raise AssertionError("managed-role contamination unexpectedly passed")
    broken = copy.deepcopy(data)
    broken["stages"][0]["components"][2]["minimumMajor"] = 18
    try:
        validate_contract(broken, roles)
    except AssertionError:
        pass
    else:
        raise AssertionError("Node 18 unexpectedly accepted")
    broken = copy.deepcopy(data)
    broken["stages"][0]["dependencies"] = ["native-agents"]
    try:
        validate_contract(broken, roles)
    except AssertionError:
        pass
    else:
        raise AssertionError("forward dependency unexpectedly accepted")
    print("PASS: personal workstation bootstrap contract / synthetic regressions")


if __name__ == "__main__":
    main()
