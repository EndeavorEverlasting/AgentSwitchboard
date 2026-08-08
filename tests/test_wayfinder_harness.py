from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling/harness/wayfinder"
sys.path.insert(0, str(HARNESS))

from wayfinder_contract import (  # noqa: E402
    DecisionTicket,
    ResolutionEvidence,
    TicketType,
    WayfinderContractError,
    WayfinderMap,
    ticket_gate,
    validate_session_resolution_types,
)
from github_tracker import CommandResult, GitHubWayfinderTracker  # noqa: E402

DONOR = "84fdeffd12f2ee307994d1eb6feb48173b6e0502"
VENDOR = ROOT / "third_party/mattpocock-skills" / DONOR
FIXTURES = HARNESS / "fixtures"
EXPECTED_IMPORTED_BLOBS = {
    "wayfinder/SKILL.md": "e4984ed327e12ba65303f4b5de2eb75c01e99c16",
    "research/SKILL.md": "0ba594a07f306479baa67104381f48e209ab6aae",
    "prototype/SKILL.md": "094571156140f5993cce8557dc31383c82817f3e",
    "grilling/SKILL.md": "95bd01ee9049a7e08120d54af9cd6ceeef282335",
    "domain-modeling/SKILL.md": "d0f7e1a5ccb06a7184056ff9af02b67bc77f9dda",
    "to-spec/SKILL.md": "3fd64959895b7eb095a13d797e1c7544f1f08c8f",
    "to-tickets/SKILL.md": "96deac51d4391a3f691478d48f85f43261516c08",
    "issue-tracker-github.md": "bf595e2470597fcd316d8b316ad861f05ed630be",
    "issue-tracker-local.md": "fbda5e04217fcdb73b513720f513abbe0b3014ed",
    "LICENSE": "f1dd2c09108dde1a5f56097cee8461b3ea834499",
}


def git_blob_sha(path: Path) -> str:
    data = path.read_bytes()
    payload = f"blob {len(data)}\0".encode() + data
    return hashlib.sha1(payload).hexdigest()


def expect_contract_error(callback) -> None:
    try:
        callback()
    except WayfinderContractError:
        return
    raise AssertionError("expected WayfinderContractError")


def json_validator(name: str):
    from jsonschema import Draft202012Validator, FormatChecker

    schema = json.loads((HARNESS / "schemas" / name).read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def validate_json_schemas_and_fixtures() -> None:
    from jsonschema import ValidationError

    ticket_validator = json_validator("decision-ticket.schema.json")
    map_validator = json_validator("map.schema.json")
    spec_validator = json_validator("spec.schema.json")

    map_validator.validate(json.loads((FIXTURES / "map.json").read_text(encoding="utf-8")))
    for name in ("research", "prototype", "grilling", "task"):
        ticket_validator.validate(json.loads((FIXTURES / f"ticket-{name}.json").read_text(encoding="utf-8")))
    spec_validator.validate(json.loads((FIXTURES / "spec.json").read_text(encoding="utf-8")))

    grilling = json.loads((FIXTURES / "ticket-grilling.json").read_text(encoding="utf-8"))
    unsafe = dict(grilling)
    unsafe["interaction"] = "afk"
    try:
        ticket_validator.validate(unsafe)
    except ValidationError:
        pass
    else:
        raise AssertionError("grilling ticket must reject AFK interaction")

    prototype = json.loads((FIXTURES / "ticket-prototype.json").read_text(encoding="utf-8"))
    wrong_label = dict(prototype)
    wrong_label["label"] = "wayfinder:research"
    try:
        ticket_validator.validate(wrong_label)
    except ValidationError:
        pass
    else:
        raise AssertionError("prototype ticket must reject a mismatched type label")


def validate_contract_model() -> None:
    assert ticket_gate(TicketType.RESEARCH)["requiredSkills"] == ["research"]
    assert ticket_gate(TicketType.PROTOTYPE)["interaction"] == "hitl"
    assert ticket_gate(TicketType.GRILLING)["requiredSkills"] == ["grilling", "domain-modeling"]
    assert ticket_gate(TicketType.TASK)["requiresTaskCompletion"] is True

    research = DecisionTicket(
        "R1", "Research GitHub dependency APIs", TicketType.RESEARCH,
        "Which native API expresses blocked-by relationships?", 1,
        label="wayfinder:research",
    )
    grilling = DecisionTicket(
        "G1", "Choose decision authority", TicketType.GRILLING,
        "Where must a decision live so it is not duplicated?", 2,
        blocked_by=("R1",), label="wayfinder:grilling",
    )
    prototype = DecisionTicket(
        "P1", "Prototype the map UI", TicketType.PROTOTYPE,
        "What tracker presentation makes the frontier legible?", 3,
        blocked_by=("G1",), label="wayfinder:prototype",
    )
    mapping = WayfinderMap(
        map_id="M1",
        title="Wayfind ASB planner",
        destination="A fully decided implementation specification.",
        tickets={ticket.ticket_id: ticket for ticket in (research, grilling, prototype)},
        not_yet_specified=["Implementation ticket granularity after the prototype verdict."],
    )
    assert [ticket.ticket_id for ticket in mapping.frontier()] == ["R1"]

    research.claim("agent-a")
    expect_contract_error(
        lambda: research.resolve(
            ResolutionEvidence(
                invoked_skills=("research",),
                artifact_urls=("https://example.test/research",),
                primary_source_count=0,
                resolution_comment_url="https://example.test/comment",
            ),
            "GitHub exposes native issue dependencies.",
        )
    )
    research.resolve(
        ResolutionEvidence(
            invoked_skills=("research",),
            artifact_urls=("https://example.test/research",),
            primary_source_count=2,
            resolution_comment_url="https://example.test/r1-comment",
        ),
        "GitHub native issue dependencies express blocked-by relationships.",
    )
    mapping.record_resolution("R1")
    assert [ticket.ticket_id for ticket in mapping.frontier()] == ["G1"]

    grilling.claim("agent-b")
    expect_contract_error(
        lambda: grilling.resolve(
            ResolutionEvidence(
                invoked_skills=("grilling", "domain-modeling"),
                human_response_count=0,
                resolution_comment_url="https://example.test/g1-comment",
            ),
            "Tracker ticket owns the decision.",
        )
    )
    grilling.resolve(
        ResolutionEvidence(
            invoked_skills=("grilling", "domain-modeling"),
            human_response_count=2,
            resolution_comment_url="https://example.test/g1-comment",
        ),
        "Tracker ticket owns the detailed decision; the map stores only a pointer.",
    )
    mapping.record_resolution("G1")

    prototype.claim("agent-c")
    expect_contract_error(
        lambda: prototype.resolve(
            ResolutionEvidence(
                invoked_skills=("prototype",),
                artifact_urls=("https://example.test/prototype",),
                human_response_count=1,
                human_verdict_observed=False,
                resolution_comment_url="https://example.test/p1-comment",
            ),
            "Prototype accepted.",
        )
    )
    prototype.resolve(
        ResolutionEvidence(
            invoked_skills=("prototype",),
            artifact_urls=("https://example.test/prototype",),
            human_response_count=1,
            human_verdict_observed=True,
            resolution_comment_url="https://example.test/p1-comment",
        ),
        "Human selected the tracker-first frontier presentation.",
    )
    mapping.record_resolution("P1")
    assert mapping.spec_ready() is False

    mapping.not_yet_specified.clear()
    assert mapping.spec_ready() is True
    packet = mapping.build_spec_packet()
    assert packet["primaryDecisionAuthority"] == "tracker-decision-tickets"
    assert packet["lifecycle"] == "temporary-until-implementation"

    expect_contract_error(lambda: validate_session_resolution_types([TicketType.GRILLING], chart_mode=True))
    expect_contract_error(lambda: validate_session_resolution_types([TicketType.GRILLING, TicketType.PROTOTYPE]))
    validate_session_resolution_types([TicketType.RESEARCH, TicketType.RESEARCH], chart_mode=True)

    task = DecisionTicket(
        "T1", "Provision access", TicketType.TASK,
        "Provision the prerequisite account so its API can be evaluated.", 4,
        label="wayfinder:task",
    )
    task.claim("agent-d")
    expect_contract_error(
        lambda: task.resolve(
            ResolutionEvidence(task_completed=False, resolution_comment_url="https://example.test/t1-comment"),
            "Access provisioned.",
        )
    )


def validate_tracker_adapter() -> None:
    calls: list[tuple[list[str], str | None]] = []

    def fake_runner(args, stdin=None):
        argv = list(args)
        calls.append((argv, stdin))
        joined = " ".join(argv)
        if "auth status" in joined or "repo view" in joined or "label create" in joined:
            return CommandResult(0, "ok\n", "")
        if "issue create" in joined and "wayfinder:map" in joined:
            return CommandResult(0, "https://github.com/EndeavorEverlasting/AgentSwitchboard/issues/200\n", "")
        if "issue create" in joined and "wayfinder:research" in joined:
            return CommandResult(0, "https://github.com/EndeavorEverlasting/AgentSwitchboard/issues/201\n", "")
        if "issues/202 --jq .id" in joined:
            return CommandResult(0, "9002\n", "")
        if "dependencies/blocked_by" in joined:
            return CommandResult(0, "{}\n", "")
        if "issues/200/sub_issues" in joined:
            return CommandResult(0, json.dumps([
                {"number": 201, "state": "open", "assignees": []},
                {"number": 202, "state": "open", "assignees": [{"login": "other"}]},
                {"number": 203, "state": "open", "assignees": []},
            ]), "")
        if "issues/201" in joined:
            return CommandResult(0, json.dumps({
                "number": 201,
                "state": "open",
                "assignees": [],
                "issue_dependencies_summary": {"blocked_by": 0},
            }), "")
        if "issues/203" in joined:
            return CommandResult(0, json.dumps({
                "number": 203,
                "state": "open",
                "assignees": [],
                "issue_dependencies_summary": {"blocked_by": 1},
            }), "")
        if "issue edit" in joined or "issue comment" in joined or "issue close" in joined:
            return CommandResult(0, "https://example.test/result\n", "")
        return CommandResult(1, "", f"unexpected command: {joined}")

    tracker = GitHubWayfinderTracker("EndeavorEverlasting/AgentSwitchboard", runner=fake_runner)
    tracker.preflight()
    tracker.ensure_labels()
    map_number, _ = tracker.create_map("Map", "## Destination\n\nDone")
    assert map_number == 200
    ticket_number, _ = tracker.create_decision_ticket(
        map_number=200,
        title="Research dependency API",
        question="Which API should ASB use?",
        ticket_type=TicketType.RESEARCH,
    )
    assert ticket_number == 201
    assert any("--parent" in call[0] and "200" in call[0] for call in calls)
    tracker.add_blocker(child_number=201, blocker_number=202)
    assert any("issue_id=9002" in call[0] for call in calls)
    assert [item["number"] for item in tracker.frontier(200)] == [201]
    tracker.claim(201)
    tracker.post_resolution(201, "Resolved from primary sources")
    tracker.close_ticket(201)


def validate_imported_sources() -> None:
    for relative, expected in EXPECTED_IMPORTED_BLOBS.items():
        path = VENDOR / relative
        assert path.is_file(), relative
        assert git_blob_sha(path) == expected, f"{relative}: imported source drift"

    manifest = json.loads((HARNESS / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["authority"]["donorCommit"] == DONOR
    assert manifest["ticketTypes"]["grilling"]["requiredSkills"] == ["grilling", "domain-modeling"]
    assert manifest["lifecycle"]["chartStopsBeforeNonResearchResolution"] is True
    assert manifest["lifecycle"]["specLifecycle"] == "temporary-until-implementation"


def validate_skill_surface() -> None:
    expected = {
        "wayfinder": ["chart mode", "Ticket gates", "Stop"],
        "research": ["primary sources", "Wayfinder"],
        "prototype": ["throwaway", "human verdict"],
        "grilling": ["human", "frontier"],
        "domain-modeling": ["CONTEXT.md", "ADR"],
        "to-spec": ["temporary-until-implementation", "decision tickets"],
        "to-tickets": ["implementation tickets", "tracer-bullet"],
    }
    for skill, tokens in expected.items():
        text = (ROOT / ".ai/skills" / skill / "SKILL.md").read_text(encoding="utf-8")
        for token in tokens:
            assert token.lower() in text.lower(), f"{skill}: missing {token}"


def main() -> None:
    validate_imported_sources()
    validate_skill_surface()
    validate_json_schemas_and_fixtures()
    validate_contract_model()
    validate_tracker_adapter()
    print("PASS: ASB Wayfinder imported-source, fixture, ticket-gate, tracker, frontier, HITL, and temporary-spec contracts")


if __name__ == "__main__":
    main()
