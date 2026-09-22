"""Dependency-free regression floor for the salvaged Wayfinder core."""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "harness" / "wayfinder"
FIXTURES = HARNESS / "fixtures"
SCHEMAS = HARNESS / "schemas"
DONOR = "84fdeffd12f2ee307994d1eb6feb48173b6e0502"
VENDOR = ROOT / "third_party" / "mattpocock-skills" / DONOR

EXPECTED_BLOBS = {
    "wayfinder/SKILL.md": "e4984ed327e12ba65303f4b5de2eb75c01e99c16",
    "research/SKILL.md": "0ba594a07f306479baa67104381f48e209ab6aae",
    "prototype/SKILL.md": "094571156140f5993cce8557dc31383c82817f3e",
    "grilling/SKILL.md": "95bd01ee9049a7e08120d54af9cd6ceeef282335",
    "domain-modeling/SKILL.md": "d0f7e1a5ccb06a7184056ff9af02b67bc77f9dda",
    "to-spec/SKILL.md": "3fd64959895b7eb095a13d797e1c7544f1f08c8f",
    "to-tickets/SKILL.md": "96deac51d4391a3f691478d48f85f43261516c08",
}


def _load(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, str(HARNESS))
contract = _load("wayfinder_contract", HARNESS / "wayfinder_contract.py")
tracker_mod = _load("wayfinder_github_tracker", HARNESS / "github_tracker.py")


def _git_blob(path: Path) -> str:
    rel = path.relative_to(ROOT).as_posix()
    return subprocess.check_output(
        ["git", "rev-parse", f"HEAD:{rel}"],
        cwd=ROOT,
        text=True,
    ).strip().lower()


def _expect_contract_error(callback) -> None:
    try:
        callback()
    except contract.WayfinderContractError:
        return
    raise AssertionError("expected WayfinderContractError")


class SchemaViolation(AssertionError):
    pass


def _matches_type(value, expected: str) -> bool:
    if expected == "null":
        return value is None
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    raise SchemaViolation(f"unsupported schema type: {expected}")


def _validate_schema(value, schema: dict, path: str = "$") -> None:
    if "oneOf" in schema:
        matches = 0
        for option in schema["oneOf"]:
            try:
                _validate_schema(value, option, path)
                matches += 1
            except SchemaViolation:
                pass
        if matches != 1:
            raise SchemaViolation(
                f"{path}: expected exactly one oneOf match, got {matches}"
            )
        return

    for item in schema.get("allOf", []):
        condition = item.get("if")
        consequence = item.get("then")
        if condition is not None and consequence is not None:
            try:
                _validate_schema(value, condition, path)
            except SchemaViolation:
                continue
            _validate_schema(value, consequence, path)
        else:
            _validate_schema(value, item, path)

    if "const" in schema and value != schema["const"]:
        raise SchemaViolation(f"{path}: const mismatch")
    if "enum" in schema and value not in schema["enum"]:
        raise SchemaViolation(f"{path}: value not in enum")

    expected = schema.get("type")
    if expected is not None:
        allowed = expected if isinstance(expected, list) else [expected]
        if not any(_matches_type(value, item) for item in allowed):
            raise SchemaViolation(
                f"{path}: expected {allowed}, got {type(value).__name__}"
            )

    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            raise SchemaViolation(f"{path}: missing required {missing}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise SchemaViolation(f"{path}: unexpected properties {extras}")
        for key, child in value.items():
            if key in properties:
                _validate_schema(child, properties[key], f"{path}.{key}")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            raise SchemaViolation(f"{path}: too few items")
        if schema.get("uniqueItems"):
            normalized = [
                json.dumps(item, sort_keys=True, separators=(",", ":"))
                for item in value
            ]
            if len(normalized) != len(set(normalized)):
                raise SchemaViolation(f"{path}: duplicate items")
        if "items" in schema:
            for index, child in enumerate(value):
                _validate_schema(child, schema["items"], f"{path}[{index}]")

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            raise SchemaViolation(f"{path}: string too short")
        if schema.get("format") == "uri":
            parsed = urlparse(value)
            if not parsed.scheme:
                raise SchemaViolation(f"{path}: invalid URI")


def _expect_schema_error(value, schema: dict) -> None:
    try:
        _validate_schema(value, schema)
    except SchemaViolation:
        return
    raise AssertionError("expected schema validation failure")


def test_pinned_donor_lineage() -> None:
    for rel, expected in EXPECTED_BLOBS.items():
        path = VENDOR / rel
        assert path.is_file(), rel
        assert _git_blob(path) == expected, rel


def test_schema_and_fixture_floor() -> None:
    ticket_schema = json.loads(
        (SCHEMAS / "decision-ticket.schema.json").read_text(encoding="utf-8")
    )
    map_schema = json.loads(
        (SCHEMAS / "map.schema.json").read_text(encoding="utf-8")
    )
    spec_schema = json.loads(
        (SCHEMAS / "spec.schema.json").read_text(encoding="utf-8")
    )
    for schema in (ticket_schema, map_schema, spec_schema):
        assert schema["type"] == "object"
        assert schema.get("additionalProperties") is False

    tickets = [
        json.loads((FIXTURES / name).read_text(encoding="utf-8"))
        for name in (
            "ticket-research.json",
            "ticket-prototype.json",
            "ticket-grilling.json",
            "ticket-task.json",
        )
    ]
    map_fixture = json.loads(
        (FIXTURES / "map.json").read_text(encoding="utf-8")
    )
    spec_fixture = json.loads(
        (FIXTURES / "spec.json").read_text(encoding="utf-8")
    )

    for fixture in tickets:
        _validate_schema(fixture, ticket_schema)
    _validate_schema(map_fixture, map_schema)
    _validate_schema(spec_fixture, spec_schema)

    assert map_fixture["notYetSpecified"] == []
    assert map_fixture["spec"]["status"] == "published"
    assert map_fixture["spec"]["ref"] == (
        "tooling/harness/wayfinder/fixtures/spec.json"
    )
    assert spec_fixture["sourceMap"]["ref"] == map_fixture["tracker"]["mapRef"]
    assert (ROOT / map_fixture["sourceContribution"]).is_file()

    missing = copy.deepcopy(tickets[0])
    missing.pop("question")
    _expect_schema_error(missing, ticket_schema)

    extra = copy.deepcopy(tickets[0])
    extra["unexpected"] = True
    _expect_schema_error(extra, ticket_schema)

    wrong_gate = copy.deepcopy(tickets[0])
    wrong_gate["type"] = "prototype"
    _expect_schema_error(wrong_gate, ticket_schema)

    open_assigned = copy.deepcopy(tickets[0])
    open_assigned["status"] = "open"
    open_assigned["assignee"] = "agent"
    open_assigned["resolution"] = None
    _expect_schema_error(open_assigned, ticket_schema)


def test_ticket_gates_and_human_boundaries() -> None:
    TicketType = contract.TicketType
    assert contract.ticket_gate(TicketType.RESEARCH)["requiredSkills"] == ["research"]
    assert contract.ticket_gate(TicketType.PROTOTYPE)["interaction"] == "hitl"
    assert contract.ticket_gate(TicketType.GRILLING)["requiredSkills"] == [
        "grilling",
        "domain-modeling",
    ]
    assert contract.ticket_gate(TicketType.TASK)["requiresTaskCompletion"] is True

    prototype = contract.DecisionTicket(
        "P1",
        "Prototype",
        TicketType.PROTOTYPE,
        "Which behavior should we keep?",
        1,
        label="wayfinder:prototype",
    )
    prototype.claim("agent")
    _expect_contract_error(
        lambda: prototype.resolve(
            contract.ResolutionEvidence(
                invoked_skills=("prototype",),
                artifact_urls=("artifact://prototype",),
                human_response_count=1,
                human_verdict_observed=False,
                resolution_comment_url="https://example.test/resolution",
            ),
            "accepted",
        )
    )

    grilling = contract.DecisionTicket(
        "G1",
        "Decision",
        TicketType.GRILLING,
        "Which trade-off does the human choose?",
        2,
        label="wayfinder:grilling",
    )
    grilling.claim("agent")
    _expect_contract_error(
        lambda: grilling.resolve(
            contract.ResolutionEvidence(
                invoked_skills=("grilling", "domain-modeling"),
                human_response_count=0,
                resolution_comment_url="https://example.test/resolution",
            ),
            "agent guessed",
        )
    )


def test_add_ticket_failure_does_not_mutate_map() -> None:
    TicketType = contract.TicketType
    existing = contract.DecisionTicket(
        "R1", "Research", TicketType.RESEARCH, "What is true?", 1,
        label="wayfinder:research",
    )
    mapping = contract.WayfinderMap(
        map_id="M1",
        title="Map",
        destination="Destination",
        tickets={"R1": existing},
    )
    invalid = contract.DecisionTicket(
        "G1",
        "Invalid",
        TicketType.GRILLING,
        "Blocked by missing ticket?",
        2,
        blocked_by=("MISSING",),
        label="wayfinder:grilling",
    )
    _expect_contract_error(lambda: mapping.add_ticket(invalid))
    assert set(mapping.tickets) == {"R1"}
    assert [item.ticket_id for item in mapping.frontier()] == ["R1"]


def test_cycle_and_fog_batch_fail_without_partial_mutation() -> None:
    TicketType = contract.TicketType
    a = contract.DecisionTicket(
        "A", "Alpha", TicketType.TASK, "Alpha task?", 1,
        blocked_by=("B",), label="wayfinder:task",
    )
    b = contract.DecisionTicket(
        "B", "Beta", TicketType.TASK, "Beta task?", 2,
        blocked_by=("A",), label="wayfinder:task",
    )
    cyclic = contract.WayfinderMap(
        map_id="CYCLE",
        title="Cycle",
        destination="Reject cycles",
        tickets={"A": a, "B": b},
    )
    _expect_contract_error(cyclic.validate)

    root = contract.DecisionTicket(
        "R1", "Root", TicketType.RESEARCH, "Root fact?", 1,
        label="wayfinder:research",
    )
    mapping = contract.WayfinderMap(
        map_id="M2",
        title="Fog map",
        destination="Atomic graduation",
        tickets={"R1": root},
        not_yet_specified=["two tickets become precise together"],
    )
    valid = contract.DecisionTicket(
        "T2", "Valid", TicketType.TASK, "First new task?", 2,
        blocked_by=("R1",), label="wayfinder:task",
    )
    invalid = contract.DecisionTicket(
        "T3", "Invalid", TicketType.TASK, "Second new task?", 3,
        blocked_by=("MISSING",), label="wayfinder:task",
    )
    _expect_contract_error(
        lambda: mapping.graduate_fog(
            "two tickets become precise together",
            [valid, invalid],
        )
    )
    assert set(mapping.tickets) == {"R1"}
    assert mapping.not_yet_specified == [
        "two tickets become precise together"
    ]


def test_frontier_and_spec_lifecycle() -> None:
    TicketType = contract.TicketType
    research = contract.DecisionTicket(
        "R1", "Research", TicketType.RESEARCH, "What is true?", 1,
        label="wayfinder:research",
    )
    grilling = contract.DecisionTicket(
        "G1", "Choose", TicketType.GRILLING, "What should we do?", 2,
        blocked_by=("R1",), label="wayfinder:grilling",
    )
    mapping = contract.WayfinderMap(
        map_id="M1",
        title="Map",
        destination="Clear implementation route",
        tickets={"R1": research, "G1": grilling},
        not_yet_specified=["later detail"],
    )
    assert [item.ticket_id for item in mapping.frontier()] == ["R1"]

    research.claim("agent")
    research.resolve(
        contract.ResolutionEvidence(
            invoked_skills=("research",),
            artifact_urls=("artifact://research",),
            primary_source_count=1,
            resolution_comment_url="https://example.test/r1",
        ),
        "primary-source result",
    )
    mapping.record_resolution("R1")
    assert [item.ticket_id for item in mapping.frontier()] == ["G1"]

    grilling.claim("agent")
    grilling.resolve(
        contract.ResolutionEvidence(
            invoked_skills=("grilling", "domain-modeling"),
            human_response_count=1,
            resolution_comment_url="https://example.test/g1",
        ),
        "human decision",
    )
    mapping.record_resolution("G1")
    assert mapping.spec_ready() is False
    mapping.not_yet_specified.clear()
    assert mapping.spec_ready() is True
    packet = mapping.build_spec_packet(
        title="Clear implementation route",
        problem_statement="The implementation route must preserve settled decisions.",
        solution="Synthesize the settled decision map into one temporary specification.",
        user_stories=["As an implementer, I can trace the spec to settled decisions."],
        implementation_decisions=["Decision tickets remain the rationale authority."],
        testing_decisions=["Validate the generated packet against the spec contract."],
        further_notes=["The temporary spec retires after accepted implementation."],
        status="ready-for-agent",
    )
    schema = json.loads(
        (SCHEMAS / "spec.schema.json").read_text(encoding="utf-8")
    )
    _validate_schema(packet, schema)
    assert packet["schema"] == "agentswitchboard.wayfinder-spec.v1"
    assert packet["sourceMap"]["ref"] == "M1"
    assert packet["decisionSources"] == [
        {"title": "Research", "ref": "https://example.test/r1"},
        {"title": "Choose", "ref": "https://example.test/g1"},
    ]
    assert packet["lifecycle"] == "temporary-until-implementation"
    assert packet["primaryDecisionAuthority"] == "tracker-decision-tickets"

    _expect_contract_error(
        lambda: contract.validate_session_resolution_types(
            [TicketType.PROTOTYPE], chart_mode=True
        )
    )
    _expect_contract_error(
        lambda: contract.validate_session_resolution_types(
            [TicketType.GRILLING, TicketType.PROTOTYPE]
        )
    )


def test_tracker_command_construction_without_live_mutation() -> None:
    calls: list[tuple[list[str], str | None]] = []

    def fake_runner(args, stdin=None):
        argv = list(args)
        calls.append((argv, stdin))
        joined = " ".join(argv)
        if "auth status" in joined or "repo view" in joined or "label create" in joined:
            return tracker_mod.CommandResult(0, "ok\n", "")
        if "issue create" in joined and "wayfinder:map" in joined:
            return tracker_mod.CommandResult(
                0, "https://github.com/EndeavorEverlasting/AgentSwitchboard/issues/200\n", ""
            )
        if "issue create" in joined and "wayfinder:research" in joined:
            return tracker_mod.CommandResult(
                0, "https://github.com/EndeavorEverlasting/AgentSwitchboard/issues/201\n", ""
            )
        if "issues/202 --jq .id" in joined:
            return tracker_mod.CommandResult(0, "9002\n", "")
        if "dependencies/blocked_by" in joined:
            return tracker_mod.CommandResult(0, "{}\n", "")
        if "/sub_issues?per_page=100" in joined:
            return tracker_mod.CommandResult(
                0,
                json.dumps([
                    [{"number": 301, "state": "open", "assignees": []}],
                    [{"number": 302, "state": "open", "assignees": []}],
                ]),
                "",
            )
        return tracker_mod.CommandResult(0, "https://example.test/result\n", "")

    tracker = tracker_mod.GitHubWayfinderTracker(
        "EndeavorEverlasting/AgentSwitchboard",
        runner=fake_runner,
    )
    tracker.preflight()
    tracker.ensure_labels()
    map_number, _ = tracker.create_map("Map", "Destination")
    assert map_number == 200
    ticket_number, _ = tracker.create_decision_ticket(
        map_number=200,
        title="Research",
        question="Which source owns this fact?",
        ticket_type=contract.TicketType.RESEARCH,
    )
    assert ticket_number == 201
    tracker.add_blocker(child_number=201, blocker_number=202)
    children = tracker.map_children(200)
    assert [item["number"] for item in children] == [301, 302]
    assert any("--parent" in argv and "200" in argv for argv, _ in calls)
    assert any("issue_id=9002" in argv for argv, _ in calls)
    assert any(
        "--paginate" in argv and "--slurp" in argv
        for argv, _ in calls
        if "/sub_issues?per_page=100" in " ".join(argv)
    )


def main() -> None:
    test_pinned_donor_lineage()
    test_schema_and_fixture_floor()
    test_ticket_gates_and_human_boundaries()
    test_add_ticket_failure_does_not_mutate_map()
    test_cycle_and_fog_batch_fail_without_partial_mutation()
    test_frontier_and_spec_lifecycle()
    test_tracker_command_construction_without_live_mutation()
    print("PASS: Wayfinder core salvage contracts")


if __name__ == "__main__":
    main()
