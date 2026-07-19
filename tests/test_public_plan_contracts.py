from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_json(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def main() -> None:
    registry = load_json("plans/plan-registry.json")
    schema = load_json("plans/schemas/public-plan.schema.json")
    startup_schema = load_json("tooling/gnhf/schemas/agent-startup-readiness.schema.json")
    fixture = load_json("tooling/gnhf/fixtures/startup-readiness/state.partial.json")

    assert registry["schemaVersion"] == 1
    assert registry["policy"]["planIsNotPullRequest"] is True
    assert registry["policy"]["machineReadableRequired"] is True
    assert schema["additionalProperties"] is False
    assert startup_schema["additionalProperties"] is False

    for entry in registry["plans"]:
        plan_path = ROOT / entry["path"]
        summary_path = ROOT / entry["summaryPath"]
        assert plan_path.is_file(), entry["path"]
        assert summary_path.is_file(), entry["summaryPath"]
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        assert plan["planId"] == entry["planId"]
        assert plan["visibility"] == "public"
        assert plan["repository"] == "EndeavorEverlasting/AgentSwitchboard"
        assert plan["tasks"]
        assert plan["forbiddenScope"]
        assert plan["proof"]["ceiling"]

    readme = (ROOT / "plans/README.md").read_text(encoding="utf-8")
    assert "plan" in readme.lower() and "pull request" in readme.lower()
    assert "must not become the only place" in readme

    skill = (ROOT / ".ai/skills/public-plan-coordination/SKILL.md").read_text(encoding="utf-8")
    for token in (
        "id: public-plan-coordination",
        "status: canonical",
        "## Trigger",
        "## Inputs",
        "## Procedure",
        "## Outputs",
        "## Deterministic validation",
        "## Forbidden scope",
        "## Stop and escalate",
    ):
        assert token in skill, token

    launcher = (ROOT / "AgentSwitchboard.cmd").read_text(encoding="utf-8")
    assert launcher.index("Get-AgentSwitchboardStartupReport.ps1") < launcher.index("Start-AgentSwitchboard.ps1")
    assert "%ERRORLEVEL%" in launcher

    startup = (ROOT / "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1").read_text(encoding="utf-8")
    for forbidden in (
        "Invoke-WebRequest",
        "winget install",
        "npm install",
        "opencode auth login",
        "gh auth login",
        "git push",
    ):
        assert forbidden.lower() not in startup.lower(), forbidden

    assert fixture["agents"]["opencode"]["available"] is True
    assert fixture["agents"]["goose"]["available"] is False
    assert "proofCeiling" in startup_schema["required"]

    template_registry = load_json("templates/repository-agent-contract/plans/plan-registry.json")
    assert template_registry["policy"]["planIsNotPullRequest"] is True
    assert (ROOT / "templates/repository-agent-contract/plans/schemas/public-plan.schema.json").is_file()

    print("PASS: public plan and startup readiness contracts")


if __name__ == "__main__":
    main()
