"""Dependency-free regression floor for the salvaged Wayfinder core."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType

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


def test_pinned_donor_lineage() -> None:
    for rel, expected in EXPECTED_BLOBS.items():
        path = VENDOR / rel
        assert path.is_file(), rel
        assert _git_blob(path) == expected, rel


def test_schema_and_fixture_floor() -> None:
    for name in ("decision-ticket.schema.json", "map.schema.json", "spec.schema.json"):
        schema = json.loads((SCHEMAS / name).read_text(encoding="utf-8"))
        assert schema["type"] == "object"
        assert schema.get("additionalProperties") is False

    research = json.loads((FIXTURES / "ticket-research.json").read_text(encoding="utf-8"))
    prototype = json.loads((FIXTURES / "ticket-prototype.json").read_text(encoding="utf-8"))
    grilling = json.loads((FIXTURES / "ticket-grilling.json").read_text(encoding="utf-8"))
    task = json.loads((FIXTURES / "ticket-task.json").read_text(encoding="utf-8"))
    assert research["type"] == "research" and research["interaction"] == "afk"
    assert prototype["type"] == "prototype" and prototype["interaction"] == "hitl"
    assert grilling["type"] == "grilling" and grilling["interaction"] == "hitl"
    assert task["type"] == "task"


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
    schema = json.loads((SCHEMAS / "spec.schema.json").read_text(encoding="utf-8"))
    required = set(schema["required"])
    assert set(packet) == set(schema["properties"])
    assert required <= set(packet)
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
    assert any("--parent" in argv and "200" in argv for argv, _ in calls)
    assert any("issue_id=9002" in argv for argv, _ in calls)


def main() -> None:
    test_pinned_donor_lineage()
    test_schema_and_fixture_floor()
    test_ticket_gates_and_human_boundaries()
    test_frontier_and_spec_lifecycle()
    test_tracker_command_construction_without_live_mutation()
    print("PASS: Wayfinder core salvage contracts")


if __name__ == "__main__":
    main()
