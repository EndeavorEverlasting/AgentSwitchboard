#!/usr/bin/env python3
"""Read-only AgentSwitchboard operational harness status and report generator."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[3]
HARNESS_ROOT = ROOT / "tooling" / "harness" / "operational"
REPOSITORY = "EndeavorEverlasting/AgentSwitchboard"


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

    # Registry-owned deterministic routes run first. This allows a specialized
    # harness to make its routing condition executable rather than documentary.
    for item in registry.get("specializedRouting", []):
        needles = tuple(str(needle).lower() for needle in item.get("routingNeedles", []))
        if needles and any(needle in lowered for needle in needles):
            specialized = item.get("skill")
            break

    # Compatibility rules preserve existing domain routing while older entries
    # are migrated to explicit registry-owned routingNeedles.
    if specialized is None:
        special_rules = (
            (("pi harness", "opinion fusion", "autovalidate"), ".ai/skills/pi-fusion-orchestration/SKILL.md"),
            (("launch mode", "open-or-activate", "new instance", "new-instance"), ".ai/skills/windows-profile-launch-mode-validation/SKILL.md"),
            (("runtime proof", "end to end", "end-to-end", "visible runtime"), ".ai/skills/end-to-end-runtime-validation/SKILL.md"),
            (("android", "termux", "ssh", "tmux", "wsl", "linux", "windows", "environment", "remote host"), ".ai/skills/environment-capability-routing/SKILL.md"),
        )
        for needles, route in special_rules:
            if any(needle in lowered for needle in needles):
                specialized = route
                break

    registered = {item["workflowId"]: item for item in registry.get("workflows", [])}
    # Lifecycle precedence is explicit, but trigger text comes from the registry.
    workflow = None
    for workflow_id in ("handoff", "failure-recovery", "pre-commit-validation", "task-intake"):
        item = registered.get(workflow_id)
        if item and any(str(trigger).lower() in lowered for trigger in item.get("triggers", [])):
            workflow = workflow_id
            break

    # Compatibility aliases cover common operator phrasing not intended as registry vocabulary.
    if workflow is None:
        if any(word in lowered for word in ("handoff", "transfer", "continue later", "next agent")):
            workflow = "handoff"
        elif any(word in lowered for word in ("failed", "failure", "broken", "repair ci", "fix ci")):
            workflow = "failure-recovery"
        elif any(word in lowered for word in ("before commit", "pre-commit", "validate", "validation", "verification", "verify")):
            workflow = "pre-commit-validation"
        else:
            workflow = registry.get("defaultWorkflow", "task-intake")
    return workflow, specialized


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--task", default="", help="Task text used only for deterministic workflow routing.")
    parser.add_argument("--output-root", type=Path, default=None, help="Directory for untracked generated evidence. Defaults to the OS temporary directory.")
    parser.add_argument("--print-json", action="store_true", help="Print machine-readable status after the report path.")
    parser.add_argument("--branch-label", default=None, help="Human branch identity to preserve when HEAD is detached.")
    parser.add_argument("--branch-ref", default=None, help="Optional Git ref that must resolve to the observed HEAD.")
    parser.add_argument("--expected-head", default=None, help="Exact HEAD SHA required for this report.")
    parser.add_argument("--pr-number", type=int, default=None, help="Pull request number associated with this verification/handoff.")
    parser.add_argument("--validated-command", action="append", default=[], help="Command the caller already executed successfully. Repeatable; recorded as caller attestation, not independently re-run.")
    parser.add_argument("--gate-complete", action="store_true", help="Attest that the declared validation gate completed successfully before this report was generated.")
    parser.add_argument("--merge-authorized", action="store_true", help="Record that the current task or a standing repository-owner directive already authorizes merging validated in-scope work.")
    parser.add_argument("--merge-authority-source", default=None, help="Human-readable source of merge authority, required with --merge-authorized (for example: current task prompt or standing repository-owner directive).")
    parser.add_argument("--next-command", default=None, help="Explicit executable next gate. If omitted after a complete PR gate, an exact-head merge command is emitted; its owner depends on recorded merge authority.")
    parser.add_argument("--next-owner", default=None, help="Owner of the next action when --next-command is supplied.")
    parser.add_argument("--next-dependency", default=None, help="Dependency blocking the next action when --next-command is supplied.")
    parser.add_argument("--next-proof", default=None, help="Artifact or proof produced by the next action when --next-command is supplied.")
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
        "tooling/harness/operational/hooks/Invoke-OperationalHarnessPrePush.ps1",
        ".ai/skills/operational-harness-routing/SKILL.md",
        "scripts/Test-OperationalHarness.ps1",
        "tests/test_operational_harness.py",
        "docs/harness/operational-harness.md",
        ".github/workflows/operational-harness.yml",
    ]
    registered_skills = {
        str(item.get("skill"))
        for item in [*workflows.get("workflows", []), *workflows.get("specializedRouting", [])]
        if item.get("skill")
    }
    required.extend(sorted(path for path in registered_skills if path not in required))
    components = [{"path": p, "present": (ROOT / p).is_file()} for p in required]
    missing = [item["path"] for item in components if not item["present"]]

    branch_rc, symbolic_branch = git("symbolic-ref", "--quiet", "--short", "HEAD")
    head_rc, head = git("rev-parse", "HEAD")
    dirty_rc, dirty_text = git("status", "--porcelain")
    remote_rc, remote = git("remote", "get-url", "origin")

    if args.expected_head:
        if head_rc != 0 or not head:
            print("[FAIL] HEAD is unavailable but --expected-head was supplied", file=sys.stderr)
            return 3
        if head != args.expected_head:
            print(f"[FAIL] HEAD mismatch expected={args.expected_head} observed={head}", file=sys.stderr)
            return 4

    if args.branch_ref:
        ref_rc, ref_head = git("rev-parse", "--verify", f"{args.branch_ref}^{{commit}}")
        if ref_rc != 0 or not ref_head:
            print(f"[FAIL] branch ref could not be resolved: {args.branch_ref}", file=sys.stderr)
            return 5
        if head_rc != 0 or ref_head != head:
            print(f"[FAIL] branch ref does not resolve to observed HEAD ref={args.branch_ref} ref_head={ref_head} observed={head or 'unavailable'}", file=sys.stderr)
            return 6

    if args.gate_complete and not args.validated_command:
        print("[FAIL] --gate-complete requires at least one --validated-command receipt", file=sys.stderr)
        return 7
    if args.merge_authority_source and not args.merge_authorized:
        print("[FAIL] --merge-authority-source requires --merge-authorized", file=sys.stderr)
        return 8
    if args.merge_authorized and not args.merge_authority_source:
        print("[FAIL] --merge-authorized requires --merge-authority-source", file=sys.stderr)
        return 9
    if args.merge_authorized and (args.pr_number is None or not args.gate_complete):
        print("[FAIL] --merge-authorized requires --pr-number and --gate-complete", file=sys.stderr)
        return 10

    detached = branch_rc != 0
    effective_branch = symbolic_branch if branch_rc == 0 else args.branch_label
    branch_source = "symbolic-ref" if branch_rc == 0 else ("operator-supplied" if args.branch_label else "unavailable")
    git_state = {
        "available": head_rc == 0,
        "branch": effective_branch,
        "branchSource": branch_source,
        "branchRef": args.branch_ref,
        "detached": detached,
        "head": head if head_rc == 0 else None,
        "dirty": bool(dirty_text) if dirty_rc == 0 else None,
        "origin": remote if remote_rc == 0 else None,
    }

    workflow, specialized = select_route(args.task, workflows)
    if args.gate_complete and args.pr_number is not None:
        workflow = "handoff"

    first_validator = validators["validators"][0]["command"]
    if missing:
        next_action = {
            "owner": "current harness agent",
            "dependency": "missing operational harness component(s)",
            "command": first_validator,
            "proof": "passing operational harness completeness result",
        }
    elif args.next_command:
        next_action = {
            "owner": args.next_owner or "declared operator",
            "dependency": args.next_dependency or "none declared",
            "command": args.next_command,
            "proof": args.next_proof or "result of the declared next gate",
        }
    elif args.gate_complete and args.pr_number is not None and head_rc == 0:
        merge_command = f"gh pr merge {args.pr_number} --repo {REPOSITORY} --merge --match-head-commit {head}"
        if args.merge_authorized:
            next_action = {
                "owner": "current harness agent",
                "dependency": f"merge authorized by {args.merge_authority_source}; required checks/reviews must remain satisfied and the exact PR head must remain unchanged",
                "command": merge_command,
                "proof": f"GitHub merge result for PR #{args.pr_number} at exact head {head}",
            }
        else:
            next_action = {
                "owner": "repository owner",
                "dependency": "explicit owner merge authorization and any required review",
                "command": merge_command,
                "proof": f"GitHub merge result for PR #{args.pr_number} at exact head {head}",
            }
    else:
        next_action = {
            "owner": "current harness agent",
            "dependency": "none",
            "command": first_validator,
            "proof": "passing operational harness completeness result",
        }

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
    validation = {
        "gateComplete": args.gate_complete,
        "attestationSource": "caller" if args.validated_command else "none",
        "reportedSuccessfulCommands": args.validated_command,
    }
    status = {
        "schemaVersion": 1,
        "harnessId": manifest["harnessId"],
        "generatedUtc": now.isoformat().replace("+00:00", "Z"),
        "repository": REPOSITORY,
        "git": git_state,
        "pullRequest": args.pr_number,
        "components": components,
        "routing": {"task": args.task, "workflow": workflow, "specializedSkill": specialized},
        "validation": validation,
        "nextAction": next_action,
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
        "commands": [
            {"command": command, "result": "reported-successful-by-caller"}
            for command in args.validated_command
        ],
        "note": "Caller-attested receipts are recorded only when explicitly supplied. The reporter does not infer or re-run them.",
        "gateComplete": args.gate_complete,
        "proofCeiling": "Recorded caller attestation plus repository observations only; not inferred runtime proof.",
    }
    ledger_path.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")

    branch_display = git_state["branch"] or "detached-or-unavailable"
    if git_state["detached"] and git_state["branch"]:
        branch_display += " (detached verification worktree)"
    report_lines = [
        "# AgentSwitchboard Operational Harness Report", "", "## Repository state", "",
        f"- repository: `{REPOSITORY}`",
        f"- branch: `{branch_display}`",
        f"- branch source: `{git_state['branchSource']}`",
        f"- branch ref: `{git_state['branchRef'] or 'not supplied'}`",
        f"- HEAD: `{git_state['head'] or 'unavailable'}`",
        f"- expected HEAD: `{args.expected_head or 'not supplied'}`",
        f"- PR: `#{args.pr_number}`" if args.pr_number is not None else "- PR: `not supplied`",
        f"- dirty: `{git_state['dirty']}`",
        f"- generated UTC: `{status['generatedUtc']}`", "", "## Harness summary", "",
        f"- working components: `{len(components) - len(missing)}`",
        f"- missing components: `{len(missing)}`",
        f"- selected workflow: `{workflow}`",
        f"- specialized route: `{specialized or 'none'}`",
        f"- validation gate complete: `{args.gate_complete}`",
        f"- merge authorized: `{args.merge_authorized}`",
        f"- merge authority source: `{args.merge_authority_source or 'not supplied'}`", "", "## Working", "",
    ]
    report_lines.extend(f"- `{item['path']}`" for item in components if item["present"])
    report_lines.extend(["", "## Broken or missing", ""])
    report_lines.extend([f"- `{path}`" for path in missing] or ["- none observed"])
    report_lines.extend(["", "## Validation receipts", ""])
    report_lines.extend([f"- caller reports success: `{command}`" for command in args.validated_command] or ["- none supplied; do not infer validation"])
    report_lines.extend(["", "## Validator entrypoints", ""])
    report_lines.extend(f"- `{v['id']}`: `{v['command']}` — {v['proof']}" for v in validators["validators"])
    report_lines.extend(["", "## Known traps", ""])
    report_lines.extend(f"- {trap}" for trap in map_data["knownTraps"])
    report_lines.extend([
        "", "## Proof ceiling", "", proof_ceiling,
        "", "## Next action", "",
        f"- owner: `{next_action['owner']}`",
        f"- dependency: {next_action['dependency']}",
        f"- proof produced: {next_action['proof']}",
        f"- command: `{next_action['command']}`", "",
        "This report is generated from tracked harness registries plus read-only local Git observation and explicit caller receipts. Merge authority is recorded only when --merge-authorized and --merge-authority-source are supplied; merge execution is never inferred. It is not runtime, deployment, provider, remote-host, merge-result, or operator-acceptance proof.", "",
    ])
    report_path.write_text("\n".join(report_lines), encoding="utf-8")

    unproved = ["live runtime", "deployment", "provider/authentication behavior", "remote host behavior", "operator acceptance"]
    if not args.merge_authorized:
        unproved.append("merge authorization")
    handoff = {
        "schemaVersion": 1,
        "repository": REPOSITORY,
        "branch": git_state["branch"],
        "branchRef": git_state["branchRef"],
        "head": git_state["head"],
        "pullRequest": args.pr_number,
        "statusArtifact": str(status_path),
        "reportArtifact": str(report_path),
        "validated": args.validated_command,
        "validationGateComplete": args.gate_complete,
        "unproved": unproved,
        "nextOwner": next_action["owner"],
        "nextDependency": next_action["dependency"],
        "nextProof": next_action["proof"],
        "nextCommand": next_action["command"],
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
