from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Iterable, Mapping, Sequence


class WayfinderContractError(ValueError):
    """Raised when a map/ticket transition violates the Wayfinder contract."""


class TicketType(str, Enum):
    RESEARCH = "research"
    PROTOTYPE = "prototype"
    GRILLING = "grilling"
    TASK = "task"


class InteractionMode(str, Enum):
    AFK = "afk"
    HITL = "hitl"
    EITHER = "either"


class TicketStatus(str, Enum):
    OPEN = "open"
    CLAIMED = "claimed"
    RESOLVED = "resolved"
    OUT_OF_SCOPE = "out-of-scope"


@dataclass(frozen=True)
class TicketRule:
    interaction: InteractionMode
    required_skills: tuple[str, ...]
    requires_artifact: bool = False
    requires_primary_sources: bool = False
    requires_human_response: bool = False
    requires_task_completion: bool = False


TICKET_RULES: Mapping[TicketType, TicketRule] = {
    TicketType.RESEARCH: TicketRule(
        interaction=InteractionMode.AFK,
        required_skills=("research",),
        requires_artifact=True,
        requires_primary_sources=True,
    ),
    TicketType.PROTOTYPE: TicketRule(
        interaction=InteractionMode.HITL,
        required_skills=("prototype",),
        requires_artifact=True,
        requires_human_response=True,
    ),
    TicketType.GRILLING: TicketRule(
        interaction=InteractionMode.HITL,
        required_skills=("grilling", "domain-modeling"),
        requires_human_response=True,
    ),
    TicketType.TASK: TicketRule(
        interaction=InteractionMode.EITHER,
        required_skills=(),
        requires_task_completion=True,
    ),
}


@dataclass(frozen=True)
class ResolutionEvidence:
    invoked_skills: tuple[str, ...] = ()
    artifact_urls: tuple[str, ...] = ()
    primary_source_count: int = 0
    human_response_count: int = 0
    human_verdict_observed: bool = False
    task_completed: bool = False
    resolution_comment_url: str | None = None


@dataclass
class DecisionTicket:
    ticket_id: str
    title: str
    ticket_type: TicketType
    question: str
    order: int
    status: TicketStatus = TicketStatus.OPEN
    assignee: str | None = None
    blocked_by: tuple[str, ...] = ()
    tracker_url: str | None = None
    label: str | None = None
    resolution_gist: str | None = None
    resolution_url: str | None = None

    @property
    def expected_label(self) -> str:
        return f"wayfinder:{self.ticket_type.value}"

    @property
    def rule(self) -> TicketRule:
        return TICKET_RULES[self.ticket_type]

    def validate_identity(self) -> None:
        if not self.ticket_id.strip():
            raise WayfinderContractError("ticket id is required")
        if not self.title.strip():
            raise WayfinderContractError(f"{self.ticket_id}: ticket title is required")
        if not self.question.strip():
            raise WayfinderContractError(f"{self.ticket_id}: ticket question is required")
        if self.label is not None and self.label != self.expected_label:
            raise WayfinderContractError(
                f"{self.ticket_id}: label {self.label!r} disagrees with ticket type; expected {self.expected_label!r}"
            )
        if self.status is TicketStatus.CLAIMED and not self.assignee:
            raise WayfinderContractError(f"{self.ticket_id}: claimed ticket must have an assignee")
        if self.status is TicketStatus.OPEN and self.assignee:
            raise WayfinderContractError(f"{self.ticket_id}: assigned ticket must be marked claimed")
        if self.status is TicketStatus.RESOLVED and not self.resolution_url:
            raise WayfinderContractError(f"{self.ticket_id}: resolved ticket requires a resolution URL")

    def validate_resolution(self, evidence: ResolutionEvidence) -> None:
        self.validate_identity()
        if self.status is not TicketStatus.CLAIMED:
            raise WayfinderContractError(f"{self.ticket_id}: claim the ticket before resolving it")
        if not self.assignee:
            raise WayfinderContractError(f"{self.ticket_id}: claimed ticket requires an assignee")

        rule = self.rule
        invoked = set(evidence.invoked_skills)
        missing = [skill for skill in rule.required_skills if skill not in invoked]
        if missing:
            raise WayfinderContractError(
                f"{self.ticket_id}: {self.ticket_type.value} gate missing required skill(s): {', '.join(missing)}"
            )
        if rule.requires_artifact and not evidence.artifact_urls:
            raise WayfinderContractError(f"{self.ticket_id}: {self.ticket_type.value} gate requires a concrete artifact")
        if rule.requires_primary_sources and evidence.primary_source_count < 1:
            raise WayfinderContractError(f"{self.ticket_id}: research gate requires at least one primary source")
        if rule.requires_human_response and evidence.human_response_count < 1:
            raise WayfinderContractError(f"{self.ticket_id}: HITL gate requires an observed human response")
        if self.ticket_type is TicketType.PROTOTYPE and not evidence.human_verdict_observed:
            raise WayfinderContractError(f"{self.ticket_id}: prototype gate requires an observed human verdict")
        if rule.requires_task_completion and not evidence.task_completed:
            raise WayfinderContractError(f"{self.ticket_id}: task gate remains open until the prerequisite is completed")
        if not evidence.resolution_comment_url:
            raise WayfinderContractError(f"{self.ticket_id}: resolution must be recorded on the tracker")

    def claim(self, assignee: str) -> None:
        self.validate_identity()
        if self.status is not TicketStatus.OPEN or self.assignee:
            raise WayfinderContractError(f"{self.ticket_id}: only an open unclaimed ticket can be claimed")
        if not assignee.strip():
            raise WayfinderContractError(f"{self.ticket_id}: assignee is required")
        self.assignee = assignee
        self.status = TicketStatus.CLAIMED

    def resolve(self, evidence: ResolutionEvidence, gist: str) -> None:
        self.validate_resolution(evidence)
        if not gist.strip():
            raise WayfinderContractError(f"{self.ticket_id}: map context pointer requires a one-line gist")
        self.status = TicketStatus.RESOLVED
        self.resolution_url = evidence.resolution_comment_url
        self.resolution_gist = gist.strip()


@dataclass(frozen=True)
class DecisionPointer:
    title: str
    url: str
    gist: str


@dataclass
class WayfinderMap:
    map_id: str
    title: str
    destination: str
    tracker_url: str | None = None
    notes: tuple[str, ...] = ()
    tickets: dict[str, DecisionTicket] = field(default_factory=dict)
    not_yet_specified: list[str] = field(default_factory=list)
    out_of_scope: list[str] = field(default_factory=list)
    decisions: list[DecisionPointer] = field(default_factory=list)

    def validate(self) -> None:
        if not self.map_id.strip() or not self.title.strip() or not self.destination.strip():
            raise WayfinderContractError("map id, title, and destination are required")
        orders: set[int] = set()
        for ticket in self.tickets.values():
            ticket.validate_identity()
            if ticket.order in orders:
                raise WayfinderContractError(f"duplicate ticket order: {ticket.order}")
            orders.add(ticket.order)
            for blocker in ticket.blocked_by:
                if blocker not in self.tickets:
                    raise WayfinderContractError(f"{ticket.ticket_id}: unknown blocker {blocker}")
                if blocker == ticket.ticket_id:
                    raise WayfinderContractError(f"{ticket.ticket_id}: ticket cannot block itself")

    def _blocker_is_open(self, blocker_id: str) -> bool:
        blocker = self.tickets[blocker_id]
        # A blocker only clears by being resolved. If it is ruled out of scope,
        # dependents must be explicitly re-scoped/closed/rewired rather than
        # silently becoming eligible on an invalidated route.
        return blocker.status is not TicketStatus.RESOLVED

    def frontier(self) -> list[DecisionTicket]:
        self.validate()
        frontier = []
        for ticket in sorted(self.tickets.values(), key=lambda item: item.order):
            if ticket.status is not TicketStatus.OPEN:
                continue
            if ticket.assignee:
                continue
            if any(self._blocker_is_open(blocker_id) for blocker_id in ticket.blocked_by):
                continue
            frontier.append(ticket)
        return frontier

    def add_ticket(self, ticket: DecisionTicket) -> None:
        if ticket.ticket_id in self.tickets:
            raise WayfinderContractError(f"duplicate ticket id: {ticket.ticket_id}")
        self.tickets[ticket.ticket_id] = ticket
        self.validate()

    def record_resolution(self, ticket_id: str) -> DecisionPointer:
        ticket = self.tickets[ticket_id]
        if ticket.status is not TicketStatus.RESOLVED or not ticket.resolution_url or not ticket.resolution_gist:
            raise WayfinderContractError(f"{ticket_id}: ticket must be resolved before adding its map pointer")
        pointer = DecisionPointer(ticket.title, ticket.resolution_url, ticket.resolution_gist)
        if any(existing.url == pointer.url for existing in self.decisions):
            raise WayfinderContractError(f"{ticket_id}: resolution is already indexed on the map")
        self.decisions.append(pointer)
        return pointer

    def graduate_fog(self, fog_entry: str, new_tickets: Sequence[DecisionTicket]) -> None:
        if fog_entry not in self.not_yet_specified:
            raise WayfinderContractError("fog entry must exist before it can graduate")
        if not new_tickets:
            raise WayfinderContractError("graduating fog requires at least one newly precise ticket")
        for ticket in new_tickets:
            self.add_ticket(ticket)
        self.not_yet_specified.remove(fog_entry)

    def spec_ready(self) -> bool:
        self.validate()
        unresolved = [
            ticket
            for ticket in self.tickets.values()
            if ticket.status not in (TicketStatus.RESOLVED, TicketStatus.OUT_OF_SCOPE)
        ]
        return not unresolved and not self.not_yet_specified

    def build_spec_packet(self) -> dict[str, object]:
        if not self.spec_ready():
            raise WayfinderContractError("spec cannot be synthesized while decision tickets or fog remain")
        return {
            "map": {"id": self.map_id, "title": self.title, "url": self.tracker_url},
            "destination": self.destination,
            "decisionSources": [
                {"title": pointer.title, "url": pointer.url, "gist": pointer.gist}
                for pointer in self.decisions
            ],
            "outOfScope": list(self.out_of_scope),
            "lifecycle": "temporary-until-implementation",
            "primaryDecisionAuthority": "tracker-decision-tickets",
        }


def validate_session_resolution_types(
    ticket_types: Iterable[TicketType], *, chart_mode: bool = False
) -> None:
    types = list(ticket_types)
    if chart_mode and any(ticket_type is not TicketType.RESEARCH for ticket_type in types):
        raise WayfinderContractError("chart mode may dispatch/resolve research only; non-research tickets belong to later sessions")
    non_research_count = sum(ticket_type is not TicketType.RESEARCH for ticket_type in types)
    if non_research_count > 1:
        raise WayfinderContractError("resolve at most one non-research decision ticket per session")


def ticket_gate(ticket_type: TicketType) -> dict[str, object]:
    rule = TICKET_RULES[ticket_type]
    return {
        "type": ticket_type.value,
        "label": f"wayfinder:{ticket_type.value}",
        "interaction": rule.interaction.value,
        "requiredSkills": list(rule.required_skills),
        "requiresArtifact": rule.requires_artifact,
        "requiresPrimarySources": rule.requires_primary_sources,
        "requiresHumanResponse": rule.requires_human_response,
        "requiresTaskCompletion": rule.requires_task_completion,
    }
