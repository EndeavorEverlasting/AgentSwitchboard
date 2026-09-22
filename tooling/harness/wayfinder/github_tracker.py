from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from typing import Callable, Sequence

from wayfinder_contract import TicketType, WayfinderContractError


API_VERSION = "2026-03-10"
WAYFINDER_LABELS = {
    "wayfinder:map": ("5319e7", "Wayfinder destination map"),
    "wayfinder:research": ("0e8a16", "AFK primary-source research decision ticket"),
    "wayfinder:prototype": ("fbca04", "HITL throwaway prototype decision ticket"),
    "wayfinder:grilling": ("d876e3", "HITL grilling/domain-modeling decision ticket"),
    "wayfinder:task": ("1d76db", "Prerequisite action that unblocks a decision"),
    "wayfinder:spec": ("0052cc", "Temporary implementation specification synthesized from a clear map"),
    "ready-for-agent": ("0e8a16", "Implementation ticket whose blockers are satisfied")
}


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


Runner = Callable[[Sequence[str], str | None], CommandResult]


def subprocess_runner(args: Sequence[str], stdin: str | None = None) -> CommandResult:
    completed = subprocess.run(
        list(args),
        input=stdin,
        text=True,
        capture_output=True,
        check=False,
    )
    return CommandResult(completed.returncode, completed.stdout, completed.stderr)


def _require_ok(result: CommandResult, operation: str) -> str:
    if result.returncode != 0:
        raise WayfinderContractError(
            f"{operation} failed with exit code {result.returncode}: {result.stderr.strip()}"
        )
    return result.stdout.strip()


def _issue_number_from_url(url: str) -> int:
    match = re.search(r"/issues/(\d+)(?:$|[?#])", url.strip())
    if not match:
        raise WayfinderContractError(f"could not resolve issue number from {url!r}")
    return int(match.group(1))


class GitHubWayfinderTracker:
    """Operational adapter for GitHub issue-backed Wayfinder maps.

    The adapter owns tracker mechanics only. Ticket semantics stay in
    `wayfinder_contract.py` and agent procedure stays in `.ai/skills/wayfinder`.
    """

    def __init__(self, repository: str, runner: Runner = subprocess_runner):
        if repository.count("/") != 1:
            raise ValueError("repository must be owner/name")
        self.repository = repository
        self.owner, self.name = repository.split("/", 1)
        self.runner = runner

    def _run(self, args: Sequence[str], stdin: str | None = None, operation: str = "gh") -> str:
        return _require_ok(self.runner(args, stdin), operation)

    def preflight(self) -> None:
        self._run(["gh", "auth", "status", "--hostname", "github.com"], operation="GitHub auth preflight")
        self._run(
            ["gh", "repo", "view", self.repository, "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            operation="repository preflight",
        )

    def ensure_labels(self) -> None:
        for label, (color, description) in WAYFINDER_LABELS.items():
            self._run(
                [
                    "gh",
                    "label",
                    "create",
                    label,
                    "--repo",
                    self.repository,
                    "--color",
                    color,
                    "--description",
                    description,
                    "--force",
                ],
                operation=f"ensure label {label}",
            )

    def create_map(self, title: str, body: str) -> tuple[int, str]:
        url = self._run(
            [
                "gh",
                "issue",
                "create",
                "--repo",
                self.repository,
                "--title",
                title,
                "--body-file",
                "-",
                "--label",
                "wayfinder:map",
            ],
            stdin=body,
            operation="create Wayfinder map",
        )
        return _issue_number_from_url(url), url

    def create_decision_ticket(
        self,
        *,
        map_number: int,
        title: str,
        question: str,
        ticket_type: TicketType,
    ) -> tuple[int, str]:
        body = f"## Question\n\n{question.strip()}\n"
        url = self._run(
            [
                "gh",
                "issue",
                "create",
                "--repo",
                self.repository,
                "--title",
                title,
                "--body-file",
                "-",
                "--label",
                f"wayfinder:{ticket_type.value}",
                "--parent",
                str(map_number),
            ],
            stdin=body,
            operation=f"create {ticket_type.value} decision ticket",
        )
        return _issue_number_from_url(url), url

    def add_blocker(self, *, child_number: int, blocker_number: int) -> None:
        blocker_db_id = self._run(
            [
                "gh",
                "api",
                f"repos/{self.repository}/issues/{blocker_number}",
                "--jq",
                ".id",
            ],
            operation="resolve blocker database id",
        )
        if not blocker_db_id.isdigit():
            raise WayfinderContractError("GitHub blocker database id was not numeric")
        self._run(
            [
                "gh",
                "api",
                "--method",
                "POST",
                "-H",
                f"X-GitHub-Api-Version: {API_VERSION}",
                f"repos/{self.repository}/issues/{child_number}/dependencies/blocked_by",
                "-F",
                f"issue_id={blocker_db_id}",
            ],
            operation="wire issue dependency",
        )

    def claim(self, ticket_number: int) -> None:
        self._run(
            [
                "gh",
                "issue",
                "edit",
                str(ticket_number),
                "--repo",
                self.repository,
                "--add-assignee",
                "@me",
            ],
            operation="claim Wayfinder ticket",
        )

    def ticket_snapshot(self, ticket_number: int) -> dict:
        raw = self._run(
            [
                "gh",
                "api",
                "-H",
                f"X-GitHub-Api-Version: {API_VERSION}",
                f"repos/{self.repository}/issues/{ticket_number}",
            ],
            operation="read Wayfinder ticket",
        )
        return json.loads(raw)

    def map_children(self, map_number: int) -> list[dict]:
        raw = self._run(
            [
                "gh",
                "api",
                "-H",
                f"X-GitHub-Api-Version: {API_VERSION}",
                f"repos/{self.repository}/issues/{map_number}/sub_issues?per_page=100",
            ],
            operation="list Wayfinder sub-issues",
        )
        data = json.loads(raw)
        if not isinstance(data, list):
            raise WayfinderContractError("GitHub sub-issue response was not a list")
        return data

    def frontier(self, map_number: int) -> list[dict]:
        frontier: list[dict] = []
        for child in self.map_children(map_number):
            if child.get("state") != "open" or child.get("assignees"):
                continue
            detail = self.ticket_snapshot(int(child["number"]))
            summary = detail.get("issue_dependencies_summary") or {}
            blocked_by = summary.get("blocked_by", 0)
            if isinstance(blocked_by, dict):
                blocked_by = blocked_by.get("total_count", blocked_by.get("open", 0))
            if int(blocked_by or 0) > 0:
                continue
            frontier.append(detail)
        return frontier

    def post_resolution(self, ticket_number: int, answer: str) -> str:
        return self._run(
            [
                "gh",
                "issue",
                "comment",
                str(ticket_number),
                "--repo",
                self.repository,
                "--body-file",
                "-",
            ],
            stdin=answer,
            operation="post decision resolution",
        )

    def close_ticket(self, ticket_number: int) -> None:
        self._run(
            ["gh", "issue", "close", str(ticket_number), "--repo", self.repository],
            operation="close decision ticket",
        )

    def update_map_body(self, map_number: int, body: str) -> None:
        self._run(
            [
                "gh",
                "issue",
                "edit",
                str(map_number),
                "--repo",
                self.repository,
                "--body-file",
                "-",
            ],
            stdin=body,
            operation="update Wayfinder map",
        )

    def create_spec(self, *, map_number: int, title: str, body: str) -> tuple[int, str]:
        spec_body = f"## Source map\n\nPart of #{map_number}\n\n{body.strip()}\n"
        url = self._run(
            [
                "gh",
                "issue",
                "create",
                "--repo",
                self.repository,
                "--title",
                title,
                "--body-file",
                "-",
                "--label",
                "wayfinder:spec",
            ],
            stdin=spec_body,
            operation="publish temporary Wayfinder specification",
        )
        return _issue_number_from_url(url), url

    def retire_spec(self, spec_number: int) -> None:
        self._run(
            [
                "gh",
                "issue",
                "close",
                str(spec_number),
                "--repo",
                self.repository,
                "--comment",
                "Implementation accepted; this temporary specification is retired. Decision tickets remain the durable source history.",
            ],
            operation="retire temporary specification",
        )
