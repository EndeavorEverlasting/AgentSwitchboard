#!/usr/bin/env python3
"""Dependency-free contracts for the OpenCode free-default repair harness."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WSL = ROOT / "tooling" / "wsl"
HARNESS = WSL / "harness" / "opencode-free-defaults"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    paths = {
        "cmd": ROOT / "Repair-OpenCodeFreeDefaults.cmd",
        "agents": WSL / "AGENTS.md",
        "skill": ROOT / ".ai" / "skills" / "opencode-free-defaults-repair" / "SKILL.md",
        "map": HARNESS / "CODEBASE_MAP.md",
        "workflow": HARNESS / "workflow.json",
        "catalog": HARNESS / "artifact-catalog.json",
        "orchestrator": WSL / "Invoke-OpenCodeFreeDefaultsRepair.ps1",
        "status": WSL / "Get-OpenCodeFreeDefaultsHarnessStatus.ps1",
        "validator": WSL / "Test-OpenCodeFreeDefaultsHarness.ps1",
        "run_schema": WSL / "schemas" / "opencode-free-defaults-run-context.schema.json",
        "registry_schema": WSL / "schemas" / "opencode-free-defaults-artifact-registry.schema.json",
        "handoff_schema": WSL / "schemas" / "opencode-free-defaults-handoff.schema.json",
    }
    for name, path in paths.items():
        require(path.is_file(), f"missing {name}: {path.relative_to(ROOT)}")

    workflow = json.loads(text(paths["workflow"]))
    catalog = json.loads(text(paths["catalog"]))
    run_schema = json.loads(text(paths["run_schema"]))
    registry_schema = json.loads(text(paths["registry_schema"]))
    handoff_schema = json.loads(text(paths["handoff_schema"]))

    require(workflow["workflowId"] == "opencode-free-defaults-repair", "workflow ID mismatch")
    require(workflow["entrypoints"]["oneClick"] == "Repair-OpenCodeFreeDefaults.cmd", "one-click entrypoint missing")
    require(workflow["entrypoints"]["orchestrator"].endswith("Invoke-OpenCodeFreeDefaultsRepair.ps1"), "orchestrator missing")
    require(workflow["entrypoints"]["status"].endswith("Get-OpenCodeFreeDefaultsHarnessStatus.ps1"), "status probe missing")
    require(workflow["localHooks"]["installedByDefault"] is False, "mutating workflow must not install a default hook")
    require(workflow["outputPolicy"]["tracked"] is False, "runtime outputs must remain untracked")

    roles = {item["role"] for item in catalog["artifacts"]}
    require(
        {"run-context", "artifact-registry", "effective-config", "operator-report", "final-handoff"} <= roles,
        "artifact catalog is incomplete",
    )
    require(catalog["tracked"] is False, "artifact catalog must remain local-only")
    require(run_schema["properties"]["workflowId"]["const"] == workflow["workflowId"], "run schema workflow mismatch")
    require(registry_schema["properties"]["workflowId"]["const"] == workflow["workflowId"], "registry schema workflow mismatch")
    require(handoff_schema["properties"]["workflowId"]["const"] == workflow["workflowId"], "handoff schema workflow mismatch")

    cmd = text(paths["cmd"])
    require('cd /d "%~dp0"' in cmd, "CMD must enter the repository root")
    require("Invoke-OpenCodeFreeDefaultsRepair.ps1" in cmd, "CMD must delegate to the orchestrator")

    orchestrator = text(paths["orchestrator"])
    for token in (
        '"fetch", $RemoteName, $RemoteBranch',
        '"merge-base", "--is-ancestor"',
        '"worktree", "add", "--detach"',
        "run-context.json",
        "artifact-registry.json",
        "effective-opencode-config.json",
        "operator-report.md",
        "final-handoff.json",
        "Set-OpenCodeFreeDefaults.ps1",
        "Independent OpenCode configuration inspection",
        "$env:LOCALAPPDATA",
    ):
        require(token in orchestrator, f"orchestrator missing token: {token}")

    for forbidden in (
        "reset --hard",
        "git clean",
        "git push --force",
        "C:\\Users\\Cheex",
        "DEEPSEEK_API_KEY",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "deepseek/deepseek-v4-pro",
    ):
        require(forbidden not in orchestrator, f"orchestrator contains forbidden token: {forbidden}")

    agents = text(paths["agents"])
    skill = text(paths["skill"])
    combined = (agents + "\n" + skill).lower()
    for token in (
        "this subtree owns",
        "isolated detached worktree",
        "run context",
        "artifact registry",
        "english operator report",
        "compressed final handoff",
    ):
        require(token in combined, f"agent guidance missing harness concept: {token}")

    status = text(paths["status"])
    require("git status --short" in status, "status probe must inspect Git read-only")
    require('cat "$HOME/.config/opencode/opencode.json"' in status, "status probe must inspect config without jq")
    require("Set-OpenCodeFreeDefaults.ps1" in status, "status inventory must track the lower-level installer")
    for mutation_token in (
        "& pwsh -NoLogo -NoProfile -File $InstallerPath",
        "Start-Process",
        "Invoke-OpenCodeFreeDefaultsRepair.ps1",
        "apt-get install",
        "worktree add",
    ):
        require(mutation_token not in status, f"status probe contains mutation path: {mutation_token}")

    for path in paths.values():
        raw = path.read_bytes()
        if path.suffix.lower() != ".cmd":
            require(b"\r\n" not in raw, f"CRLF detected in tracked source: {path.relative_to(ROOT)}")
        require(
            all(not line.endswith((b" ", b"\t")) for line in raw.splitlines()),
            f"trailing whitespace: {path.relative_to(ROOT)}",
        )

    print("PASS: OpenCode free-default repair harness contracts")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
