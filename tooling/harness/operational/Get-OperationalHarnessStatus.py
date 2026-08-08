#!/usr/bin/env python3
"""Read-only AgentSwitchboard operational harness status and report generator."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
import os

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[3]
HARNESS_ROOT = ROOT / "tooling" / "harness" / "operational"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def git(*args: str) -> tuple[int, str]:
    result = subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode, result.stdout.strip()


def select_route(task: str, registry: dict) -> tuple[str, str | None]:
    lowered = task.lower()
    specialized = None
    special_rules = (
        (("android", "termux", "ssh", "tmux", "wsl", "linux", "windows", "environment", "remote host"), ".ai/skills/environment-capability-routing/SKILL.md"),
        (("runtime proof", "end to end", "end-to-end", "visible runtime"), ".ai/skills/end-to-end-runtime-validation/SKILL.md"),
        (("launch mode", "open-or-activate", "new instance", "new-instance"), ".ai/skills/windows-profile-launch-mode-validation/SKILL.md"),
        (("pi harness", "opinion fusion", "autovalidate"), ".ai/skills/pi-fusion-orchestration/SKILL.md"),
    )
    for needles, route in special_rules:
        if any(needle in lowered for needle in needles):
            specialized = route
            break

    if any(word in lowered for word in ("handoff", "transfer", "continue later", "next agent")):
        workflow = "handoff"
    elif any(word in lowered for word in ("failed", "failure", "broken", "repair ci", "fix ci")):
        workflow = "failure-recovery"
    elif any(word in lowered for word in ("before commit", "pre-commit", "validate", "verification")):
        workflow = "pre-commit-validation"
    else:
        workflow = registry.get("defaultWorkflow", "task-intake")
    return workflow, specialized


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", default="", help="Task text used only for deterministic workflow routing.")
    parser.add_argument("--output-root", type=Path, default=None, help="Directory for untracked generated evidence. Defaults to the OS temporary directory.")
    parser.add_argument("--print-json", action="store_true", help="Print machine-readable status after the report path.")
    args = parser.parse_args()

    manifest = load_json(HARNESS_ROOT / "manifest.json")
    map_data = load_json(HARNESS_ROOT / "codebase-map.json")
    workflows = load_json(HARNESS_ROOT / "workflow-registry.json")
    load_json(HARNESS_ROOT / "artifact-registry.json")
    validators = load_json(HARNESS_ROOT / "validator-registry.json")

    required = [
        "HARNESS.md",
        "AGENTS.md",
        ".ai/agent-contract.json",
        ".ai/harness/manifest.json",
        "tooling/harness/operational/manifest.json",
        "tooling/harness/operational/codebase-map.json",
        "tooling/harness/operational/workflow-registry.json",
        "tooling/harness/operational/artifact-registry.json",
        "tooling/harness/operational/validator-registry.json",
        "tooling/harness/operational/workflows/task-intake.workflow.json",
        "tooling/harness/operational/workflows/pre-commit-validation.workflow.json",
        "tooling/harness/operational/workflows/failure-recovery.workflow.json",
        "tooling/harness/operational/workflows/handoff.workflow.json",
        "tooling/harness/operational/templates/operator-report.template.md",
        "tooling/harness/operational/hooks/Invoke-OperationalHarnessPreCommit.ps1",
        ".ai/skills/operational-harness-routing/SKILL.md",
        "scripts/Test-OperationalHarness.ps1",
        "tests/test_operational_harness.py",
        "docs/harness/operational-harness.md",
        ".github/workflows/operational-harness.yml",
    ]
    components = [{"path": p, "present": (ROOT / p).is_file()} for p in required]
    missing = [item["path"] for item in components if not item["present"]]

    branch_rc, branch = git("symbolic-ref", "--quiet", "--short", "HEAD")
    head_rc, head = git("rev-parse", "HEAD")
    dirty_rc, dirty_text = git("status", "--porcelain")
    remote_rc, remote = git("remote", "get-url", "origin")
    git_state = {
        "available": head_rc == 0,
        "branch": branch if branch_rc == 0 else None,
        "head": head if head_rc == 0 else None,
        "dirty": bool(dirty_text) if dirty_rc == 0 else None,
        "origin": remote if remote_rc == 0 else None,
    }

    workflow, specialized = select_route(args.task, workflows)
    now = datetime.now(timezone.utc)
    run_id = f"{now.strftime('%Y%m%dT%H%M%SZ')}-{os.getpid()}"
    output_dir = args.output_root.resolve() if args.output_root else Path(tempfile.gettempdir()) / "AgentSwitchboard" / "operational-harness" / run_id
    try:
        output_dir.relative_to(ROOT)
    except ValueError:
        pass
    else:
        print("[FAIL] output root must be outside the repository", file=sys.stderr)
        return 2
    output_dir.mkdir(parents=True, exist_ok=True)

    proof_ceiling = manifest["safety"]["proofCeiling"]
    status = {
        "schemaVersion": 1,
        "harnessId": manifest["harnessId"],
        "generatedUtc": now.isoformat().replace("+00:00", "Z"),
        "repository": "EndeavorEverlasting/AgentSwitchboard",
        "git": git_state,
        "components": components,
        "routing": {"task": args.task, "workflow": workflow, "specializedSkill": specialized},
        "proofCeiling": proof_ceiling,
    }

    status_path = output_dir / "operational-harness-status.json"
    report_path = output_dir / "operational-harness-report.md"
    handoff_path = output_dir / "operational-harness-handoff.json"
    ledger_path = output_dir / "operational-harness-validation-ledger.json"
    status_path.write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")

    ledger = {
        "schemaVersion": 1,
        "generatedUtc": status["generatedUtc"],
        "commands": [],
        "note": "Populate with commands actually executed; an empty ledger does not imply validation.",
        "proofCeiling": "Recorded command/exit evidence only.",
    }
    ledger_path.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")

    first_validator = validators["validators"][0]["command"]
    report_lines = [
        "# AgentSwitchboard Operational Harness Report", "", "## Repository state", "",
        "- repository: `EndeavorEverlasting/AgentSwitchboard`",
        f"- branch: `{git_state['branch'] or 'detached-or-unavailable'}`",
        f"- HEAD: `{git_state['head'] or 'unavailable'}`",
        f"- dirty: `{git_state['dirty']}`",
        f"- generated UTC: `{status['generatedUtc']}`", "", "## Harness summary", "",
        f"- working components: `{len(components) - len(missing)}`",
        f"- missing components: `{len(missing)}`",
        f"- selected workflow: `{workflow}`",
        f"- specialized route: `{specialized or 'none'}`", "", "## Working", "",
    ]
    report_lines.extend(f"- `{item['path']}`" for item in components if item["present"])
    report_lines.extend(["", "## Broken or missing", ""])
    report_lines.extend([f"- `{path}`" for path in missing] or ["- none observed"])
    report_lines.extend(["", "## Validator entrypoints", ""])
    report_lines.extend(f"- `{v['id']}`: `{v['command']}` — {v['proof']}" for v in validators["validators"])
    report_lines.extend(["", "## Known traps", ""])
    report_lines.extend(f"- {trap}" for trap in map_data["knownTraps"])
    report_lines.extend(["", "## Proof ceiling", "", proof_ceiling, "", "## Next action", "", f"`{first_validator}`", "", "This report is generated from tracked harness registries plus read-only local Git observation. It is not runtime, deployment, provider, remote-host, or operator-acceptance proof.", ""])
    report_path.write_text("\n".join(report_lines), encoding="utf-8")

    handoff = {
        "schemaVersion": 1,
        "repository": "EndeavorEverlasting/AgentSwitchboard",
        "branch": git_state["branch"],
        "head": git_state["head"],
        "statusArtifact": str(status_path),
        "reportArtifact": str(report_path),
        "validated": [],
        "unproved": ["live runtime", "deployment", "provider/authentication behavior", "remote host behavior", "operator acceptance"],
        "nextCommand": first_validator,
    }
    handoff_path.write_text(json.dumps(handoff, indent=2) + "\n", encoding="utf-8")

    print(f"report={report_path}")
    print(f"status={status_path}")
    print(f"handoff={handoff_path}")
    print(f"validation_ledger={ledger_path}")
    if args.print_json:
        print(json.dumps(status, indent=2))
    if missing:
        print(f"[FAIL] missing {len(missing)} required operational harness component(s)", file=sys.stderr)
        return 1
    print("[PASS] operational harness components present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
