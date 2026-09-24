from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "tooling" / "profiles" / "windows" / "harness" / "agent-fleet-readiness"
REPORTER = ROOT / "tooling" / "profiles" / "windows" / "Get-AgentFleetReadinessBoundary.ps1"

class ContractFailure(RuntimeError):
    pass

def check(value: object, message: str) -> None:
    if not value:
        raise ContractFailure(message)

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def run_reporter(case: dict) -> dict:
    pwsh = shutil.which("pwsh")
    check(pwsh is not None, "pwsh is required for the executable boundary contract")
    with tempfile.TemporaryDirectory(prefix="asb-fleet-boundary-") as temp:
        root = Path(temp)
        if case.get("fleetStateExists"):
            (root / "state.json").write_text("{}\n", encoding="utf-8")
        if case.get("powerShellOperatorExists"):
            (root / "Start-AgentSwitchboard.ps1").write_text("# fixture\n", encoding="utf-8")
        if case.get("cmdShimExists"):
            (root / "agent-switchboard.cmd").write_text("@echo off\n", encoding="ascii")
        out = root / "out"
        command = [pwsh, "-NoLogo", "-NoProfile", "-File", str(REPORTER), "-InstallRoot", str(root), "-Emit", "Json", "-OutputRoot", str(out)]
        if "cmdShimExitCode" in case:
            command.extend(["-CmdShimExitCode", str(case["cmdShimExitCode"])])
        if case.get("cmdShimEvidence"):
            command.extend(["-CmdShimEvidence", str(case["cmdShimEvidence"])])
        completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
        check(completed.returncode == 0, f"{case['name']}: reporter failed: {completed.stderr.strip()}")
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise ContractFailure(f"{case['name']}: reporter emitted invalid JSON: {completed.stdout!r}") from exc
        check(str(root) in payload["startupReadinessCommand"], f"{case['name']}: startup reporter lost InstallRoot")
        return payload

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
    check("-InstallRoot \"<InstallRoot>\"" in contract["powerShellReadinessRoute"]["canonicalFollowup"], "custom InstallRoot is not preserved")

    superseded = "\n".join(contract["explicitlySuperseded"])
    for token in ("Hermes", "machine-profile", "Get-AgentSwitchboardStartupReport.ps1", "skill", "hook"):
        check(token in superseded, f"superseded owner missing: {token}")

    for case in fixtures["cases"]:
        payload = run_reporter(case)
        check(payload["classification"] == case["expectedClassification"], f"{case['name']}: {payload['classification']}")
        check(payload["nextAction"] == case["expectedNextAction"], f"{case['name']}: {payload['nextAction']}")
        check(payload["tracked"] is False, f"{case['name']}: generated status is marked tracked")

    generated = artifacts["generatedArtifacts"] + artifacts["observedArtifacts"]
    for item in generated:
        check(item["tracked"] is False, f"runtime/local artifact marked tracked: {item['id']}")

    text = json.dumps(workflow)
    for token in ("Start-AgentSwitchboard.ps1", "-ListAgents", "Get-AgentSwitchboardStartupReport.ps1", "-InstallRoot", "Access is denied", "exit 5"):
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
