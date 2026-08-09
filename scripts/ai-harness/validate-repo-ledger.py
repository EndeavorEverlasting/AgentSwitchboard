#!/usr/bin/env python3
"""Validate AgentSwitchboard's repo-local shared work ledger adoption."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPO_ROOT / ".ai" / "repo-ledger-adoption.json"
QUEUE_PATH = REPO_ROOT / ".ai" / "WORK_QUEUE.md"
README_PATH = REPO_ROOT / ".ai" / "README.md"
EXPECTED_CONTRACT_COMMIT = "3751c004fcf928e5d364226a1e08ae445f68b634"
EXPECTED_DONOR_COMMIT = "9351c952b057ae4520b1ea0d388e1d8908f4c093"
EXPECTED_DONOR_PATHS = {
    ".ai/README.md",
    ".ai/WORK_QUEUE.md",
    ".ai/authority.json",
    "scripts/ai-harness/validate-work-queue.mjs",
}
ALLOWED_STATUSES = {"READY", "CLAIMED", "VERIFY", "REVIEW", "MERGE", "OPERATOR", "BLOCKED", "DONE"}
CONTINUATION_STATUSES = {"READY", "CLAIMED", "VERIFY", "REVIEW", "MERGE"}
ALLOWED_PRIORITIES = {"P0", "P1", "P2", "P3"}
REQUIRED_FIELDS = [
    "Status",
    "Priority",
    "Owner",
    "Branch / PR",
    "Scope",
    "Forbidden",
    "Dependencies",
    "References",
    "Acceptance gate",
    "Gate",
    "Last proof",
    "Next action",
    "Updated",
]
DONE_NEXT_ACTION = "none; no safe actionable work remains"
DURABLE_PROOF = re.compile(
    r"(?:\b(?:commit|merge):[0-9a-f]{7,40}\b|\b(?:workflow|run):#?\d+\b|\bartifact:\S+|\boperator-proof:\S+)",
    re.IGNORECASE,
)
EXACT_COMMIT = re.compile(r"^[0-9a-f]{40}$")
TASK_HEADING = re.compile(r"^## (ASQ-\d{3,}) — (.+)$", re.MULTILINE)
ANY_QUEUE_HEADING = re.compile(r"^##\s+([A-Z][A-Z0-9]{1,7}Q-[^\n]*)$", re.MULTILINE)
FIELD = re.compile(r"^- \*\*([^*]+):\*\*[ \t]*(.*)$", re.MULTILINE)


def die(errors: list[str]) -> None:
    print(f"[repo-ledger] FAIL ({len(errors)})", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)


def exact_commit(value: object) -> bool:
    return bool(EXACT_COMMIT.fullmatch(str(value or "")))


def main() -> int:
    errors: list[str] = []
    for path in (MANIFEST_PATH, QUEUE_PATH, README_PATH):
        if not path.is_file():
            errors.append(f"missing local adoption path: {path.relative_to(REPO_ROOT)}")
    if errors:
        die(errors)

    try:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        die([f"invalid adoption manifest: {exc}"])

    if manifest.get("schema") != "RepoLedgerAdoption.v1":
        errors.append("schema must be RepoLedgerAdoption.v1")
    if manifest.get("repository") != "EndeavorEverlasting/AgentSwitchboard":
        errors.append("repository identity drifted")
    if manifest.get("adoptionStatus") != "implemented":
        errors.append("adoptionStatus must be implemented")

    contract = manifest.get("contract", {})
    if contract.get("repository") != "EndeavorEverlasting/BlacksmithGuild":
        errors.append("shared contract owner drifted")
    if contract.get("commit") != EXPECTED_CONTRACT_COMMIT:
        errors.append("shared contract pin drifted; explicit compatibility update required")
    if not exact_commit(contract.get("commit")):
        errors.append("shared contract ref must be an exact 40-hex commit")
    if contract.get("path") != ".tbg/workflows/repo-ledger-interoperability.contract.json":
        errors.append("shared contract path drifted")
    if contract.get("version") != "RepoLedgerInteroperability.v1":
        errors.append("shared contract version drifted")

    donor = manifest.get("donor", {})
    if donor.get("repository") != "EndeavorEverlasting/AxTask":
        errors.append("donor repository drifted")
    if donor.get("commit") != EXPECTED_DONOR_COMMIT:
        errors.append("donor commit drifted; a new shared-contract version is required")
    if not exact_commit(donor.get("commit")):
        errors.append("donor ref must be an exact 40-hex commit")
    if set(donor.get("sourcePaths", [])) != EXPECTED_DONOR_PATHS:
        errors.append("donor source paths do not match v1 provenance")

    local = manifest.get("local", {})
    if local.get("ledgerPath") != ".ai/WORK_QUEUE.md":
        errors.append("local ledger path drifted")
    if local.get("validatorPath") != "scripts/ai-harness/validate-repo-ledger.py":
        errors.append("local validator path drifted")
    if local.get("taskNamespace") != "ASQ":
        errors.append("ASQ namespace drifted")
    if local.get("format") != "markdown":
        errors.append("local ledger format drifted")

    authority = manifest.get("authority", {})
    if authority.get("runtimeOwner") != "EndeavorEverlasting/AgentSwitchboard":
        errors.append("AgentSwitchboard must remain local runtime/task authority")
    if authority.get("contractOwner") != "EndeavorEverlasting/BlacksmithGuild":
        errors.append("portable contract owner drifted")
    if authority.get("noCircularAuthority") is not True:
        errors.append("noCircularAuthority must be true")
    if manifest.get("proofCeiling") != "repository_harness_only":
        errors.append("adoption proof ceiling drifted")

    for bad_ref in ("main", "master", "HEAD", "feat/repo-ledger", "v1.0.0", "3751c004fcf9"):
        if exact_commit(bad_ref):
            errors.append(f"stale-reference probe unexpectedly accepted {bad_ref!r}")

    queue = QUEUE_PATH.read_text(encoding="utf-8")
    if "RepoLedgerInteroperability.v1" not in queue:
        errors.append("queue is missing the shared contract version pointer")
    if "`AGENTS.md`" not in queue:
        errors.append("queue must remain explicitly subordinate to AGENTS.md")

    all_queue_headings = list(ANY_QUEUE_HEADING.finditer(queue))
    matches = list(TASK_HEADING.finditer(queue))
    if not matches:
        errors.append("queue must contain at least one ASQ task")
    if len(all_queue_headings) != len(matches):
        errors.append("queue contains a task heading outside the ASQ namespace or canonical format")

    seen: set[str] = set()
    for index, match in enumerate(matches):
        task_id, title = match.group(1), match.group(2).strip()
        start = match.start()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(queue)
        block = queue[start:end]
        fields = {m.group(1).strip(): m.group(2).strip() for m in FIELD.finditer(block)}

        if task_id in seen:
            errors.append(f"{task_id}: duplicate task id")
        seen.add(task_id)
        if not title:
            errors.append(f"{task_id}: title is empty")
        for field in REQUIRED_FIELDS:
            if field not in fields:
                errors.append(f"{task_id}: missing field {field!r}")
            elif not fields[field]:
                errors.append(f"{task_id}: field {field!r} must not be blank")

        status = fields.get("Status", "")
        priority = fields.get("Priority", "")
        owner = fields.get("Owner", "")
        gate = fields.get("Gate", "")
        proof = fields.get("Last proof", "")
        next_action = fields.get("Next action", "")

        if status and status not in ALLOWED_STATUSES:
            errors.append(f"{task_id}: invalid status {status!r}")
        if priority and priority not in ALLOWED_PRIORITIES:
            errors.append(f"{task_id}: invalid priority {priority!r}")
        if status == "CLAIMED" and owner in {"", "unclaimed"}:
            errors.append(f"{task_id}: CLAIMED requires a concrete owner/session")
        if status in CONTINUATION_STATUSES and next_action in {"", DONE_NEXT_ACTION}:
            errors.append(f"{task_id}: {status} requires an executable next action")
        if status in {"BLOCKED", "OPERATOR"}:
            if gate in {"", "none"}:
                errors.append(f"{task_id}: {status} requires an exact Gate")
            if next_action in {"", DONE_NEXT_ACTION}:
                errors.append(f"{task_id}: {status} requires an executable next action")
        if status == "DONE":
            if not DURABLE_PROOF.search(proof):
                errors.append(f"{task_id}: DONE requires a durable proof token")
            if gate != "none":
                errors.append(f"{task_id}: DONE requires Gate: none")
            if next_action != DONE_NEXT_ACTION:
                errors.append(f"{task_id}: DONE requires the canonical no-work-remains next action")

    if errors:
        die(errors)

    print(
        "[repo-ledger] PASS "
        f"repo=AgentSwitchboard contract={EXPECTED_CONTRACT_COMMIT[:12]} "
        f"donor={EXPECTED_DONOR_COMMIT[:12]} namespace=ASQ tasks={len(matches)} stale-ref-probes=PASS"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
