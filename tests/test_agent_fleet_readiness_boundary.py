from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling" / "profiles" / "windows" / "harness" / "agent-fleet-readiness"

class ContractFailure(RuntimeError):
    pass

def check(value: object, message: str) -> None:
    if not value:
        raise ContractFailure(message)

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def classify(case: dict) -> tuple[str, str]:
    state = bool(case.get("fleetStateExists"))
    operator = bool(case.get("powerShellOperatorExists"))
    shim = bool(case.get("cmdShimExists"))
    if not state and not operator:
        return "not-bootstrapped", "bootstrap-or-repair"
    if state != operator:
        return "partial-or-inconsistent", "bootstrap-or-repair"
    evidence = str(case.get("cmdShimEvidence", "")).lower()
    blocked = (not shim) or case.get("cmdShimExitCode") == 5 or "access is denied" in evidence
    if blocked:
        return "cmd-shim-blocked", "prove-readiness-through-powershell"
    return "installed-unclassified", "prove-readiness-through-powershell"

def main() -> None:
    contract = load(BASE / "readiness-boundary.contract.json")
    artifacts = load(BASE / "artifact-registry.json")
    fixtures = load(BASE / "fixtures" / "readiness-boundary-cases.json")
    workflow = load(BASE / "workflows" / "prove-readiness-through-powershell.workflow.json")

    check(contract["salvage"]["sourcePullRequest"] == 79, "PR #79 provenance missing")
    check(contract["salvage"]["sourceHead"] == "b3560cd56e98f7b91dfff2e060c8a27d1c76e76a", "PR #79 source head drifted")
    check(contract["currentOwners"]["startupReadinessReporter"] == "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1", "startup reporter ownership drifted")
    check(contract["safety"]["mutatesInstalledFleet"] is False, "boundary classifier may mutate installed fleet")
    check(contract["safety"]["runsCmdShim"] is False, "boundary classifier may execute the blocked shim")
    check(contract["safety"]["authenticatesProviders"] is False, "boundary classifier may authenticate providers")

    superseded = "\n".join(contract["explicitlySuperseded"])
    for token in ("Hermes", "machine-profile", "Get-AgentSwitchboardStartupReport.ps1", "old skill", "old hook"):
        check(token in superseded, f"superseded owner missing: {token}")

    for case in fixtures["cases"]:
        classification, next_action = classify(case)
        check(classification == case["expectedClassification"], f"{case['name']}: {classification}")
        check(next_action == case["expectedNextAction"], f"{case['name']}: {next_action}")

    generated = artifacts["generatedArtifacts"] + artifacts["observedArtifacts"]
    for item in generated:
        check(item["tracked"] is False, f"runtime/local artifact marked tracked: {item['id']}")

    text = json.dumps(workflow)
    for token in ("Start-AgentSwitchboard.ps1", "-ListAgents", "Get-AgentSwitchboardStartupReport.ps1", "Access is denied", "exit 5"):
        check(token in text, f"PowerShell readiness workflow token missing: {token}")
    check("rerun setup solely" in text, "workflow does not forbid unnecessary setup retry")

    current_startup = (ROOT / "tooling" / "gnhf" / "Get-AgentSwitchboardStartupReport.ps1").read_text(encoding="utf-8")
    check("proofLevel = \"local-adapter-readiness\"" in current_startup, "current startup reporter proof boundary drifted")
    current_setup = (ROOT / "tooling" / "gnhf" / "Setup-AgentSwitchboard.ps1").read_text(encoding="utf-8")
    check("[switch]$SkipHermesInstall" in current_setup, "current Hermes deferral owner missing")
    check("Core fleet setup will continue and Hermes will be recorded as BLOCKED" in current_setup, "current graceful Hermes owner missing")

    print("PASS: agent-fleet readiness boundary contract")

if __name__ == "__main__":
    try:
        main()
    except ContractFailure as exc:
        print(f"FAIL: {exc}")
        raise SystemExit(1) from exc
