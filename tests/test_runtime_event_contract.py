from __future__ import annotations

import json
from pathlib import Path
from uuid import UUID

ROOT = Path(__file__).resolve().parents[1]


def load(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def is_uuid(value: str) -> bool:
    try:
        UUID(value)
        return True
    except (TypeError, ValueError):
        return False


def reachable(start: str, target: str, edges: list[dict]) -> bool:
    pending = [start]
    seen = {start}
    while pending:
        current = pending.pop(0)
        if current == target:
            return True
        for edge in edges:
            if edge["from"] == current and edge["to"] not in seen:
                seen.add(edge["to"])
                pending.append(edge["to"])
    return False


def envelope_valid(event: dict) -> bool:
    required = {
        "schema", "eventId", "eventType", "source", "occurredUtc",
        "correlationId", "causationId", "sequence", "payload", "metadata",
    }
    return (
        required.issubset(event)
        and event["schema"] == "agentswitchboard.runtime-event.v1"
        and is_uuid(event["eventId"])
        and is_uuid(event["correlationId"])
        and (event["causationId"] is None or is_uuid(event["causationId"]))
        and isinstance(event["sequence"], int)
        and event["sequence"] >= 0
    )


def main() -> None:
    policy = load(".ai/harness/runtime-event-contract.policy.json")
    envelope_schema = load(".ai/harness/schemas/runtime-event-envelope.schema.json")
    topology_schema = load(".ai/harness/schemas/runtime-event-topology.schema.json")
    topology = load(".ai/harness/runtime-event-topology.json")
    root = load(".ai/harness/fixtures/runtime-events/root-event.json")
    successor = load(".ai/harness/fixtures/runtime-events/successor-event.json")
    broken = load(".ai/harness/fixtures/runtime-events/broken-chain-event.json")
    manifest = load(".ai/harness/manifest.json")
    contract = load(".ai/agent-contract.json")
    app_graph = load(".ai/harness/app-composition.graph.json")
    template = load("templates/repository-agent-contract/.ai/harness/runtime-event-contract.policy.json")

    assert policy["policyId"] == "agentswitchboard.runtime-event-contract.v1"
    assert policy["envelope"]["immutableAfterEmission"] is True
    assert policy["causality"]["rootCorrelationEqualsEventId"] is True
    assert policy["causality"]["successorCorrelationInherited"] is True
    assert policy["causality"]["successorCausationEqualsParentEventId"] is True
    assert policy["composition"]["allRuntimeNodesMustBeRegistered"] is True
    assert policy["composition"]["allRuntimeEdgesMustBeRegistered"] is True
    assert policy["evidence"]["staticProofCannotClaimRuntime"] is True

    assert envelope_schema["additionalProperties"] is False
    assert topology_schema["additionalProperties"] is False
    assert set(policy["envelope"]["requiredFields"]).issubset(envelope_schema["required"])

    nodes = topology["nodes"]
    edges = topology["edges"]
    node_ids = [node["id"] for node in nodes]
    edge_ids = [edge["id"] for edge in edges]
    assert topology["status"] == "contract-only"
    assert len(node_ids) == len(set(node_ids))
    assert len(edge_ids) == len(set(edge_ids))
    assert {node["kind"] for node in nodes} == {"source", "observer", "handler", "sink"}
    assert {edge["kind"] for edge in edges} == {"emits", "observes", "dispatches", "emits-successor", "records"}
    assert all(edge["from"] in node_ids and edge["to"] in node_ids for edge in edges)
    source = next(node for node in nodes if node["kind"] == "source")
    sink = next(node for node in nodes if node["kind"] == "sink" and node["evidenceSink"])
    assert reachable(source["id"], sink["id"], edges)

    assert envelope_valid(root)
    assert root["correlationId"] == root["eventId"]
    assert root["causationId"] is None and root["sequence"] == 0
    assert envelope_valid(successor)
    assert successor["eventId"] != root["eventId"]
    assert successor["correlationId"] == root["correlationId"]
    assert successor["causationId"] == root["eventId"]
    assert successor["sequence"] > root["sequence"]
    assert broken["correlationId"] != broken["eventId"]
    assert broken["causationId"] is None and broken["sequence"] > 0

    assert manifest["entrypoints"]["runtimeEventValidator"] == "scripts/Test-RuntimeEventContract.ps1"
    assert manifest["runtimeEvents"]["contractOnly"] is True
    assert manifest["runtimeEvents"]["runtimeExecutionAllowed"] is False
    assert contract["entrypoints"]["runtimeEvents"] == "docs/governance/runtime-event-contract.md"
    assert contract["runtimeEvents"]["contractOnly"] is True
    assert template["localRulesMayWeaken"] is False

    app_nodes = {node["id"] for node in app_graph["nodes"]}
    for node_id in {
        "contract.runtime-event-policy",
        "contract.runtime-event-topology",
        "validator.runtime-events",
        "schema.runtime-event-envelope",
        "schema.runtime-event-topology",
    }:
        assert node_id in app_nodes, node_id

    runtime_doc = (ROOT / "docs/governance/runtime-event-contract.md").read_text(encoding="utf-8")
    assert "Static topology does not prove runtime delivery" in runtime_doc
    assert "Action-commitment rule" in runtime_doc
    print("PASS: runtime event contract and synthetic causality fixtures")


if __name__ == "__main__":
    main()
