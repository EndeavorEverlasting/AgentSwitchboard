#!/usr/bin/env python3
"""Deterministic pre-render fact compiler for cross-project communications."""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

ADAPTER_SCHEMA = "agentswitchboard.comms-project-adapter/v1"
EVIDENCE_SCHEMA = "agentswitchboard.comms-evidence-packet/v1"
RESULT_SCHEMA = "agentswitchboard.comms-compiled-facts/v1"


class CommsCompilerError(ValueError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CommsCompilerError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise CommsCompilerError(f"expected JSON object: {path}")
    return payload


def validate_adapter(adapter: dict[str, Any]) -> None:
    if adapter.get("schemaVersion") != ADAPTER_SCHEMA:
        raise CommsCompilerError("unsupported project-adapter schemaVersion")
    if not isinstance(adapter.get("adapterId"), str) or not adapter["adapterId"].strip():
        raise CommsCompilerError("adapterId is required")

    project = adapter.get("project")
    if not isinstance(project, dict) or not project.get("id"):
        raise CommsCompilerError("project.id is required")

    authority = adapter.get("authority")
    if not isinstance(authority, dict):
        raise CommsCompilerError("authority is required")
    sources = authority.get("sources")
    if not isinstance(sources, list) or not sources:
        raise CommsCompilerError("authority.sources must be non-empty")
    source_ids = [str(source.get("id", "")) for source in sources if isinstance(source, dict)]
    if not all(source_ids) or len(set(source_ids)) != len(source_ids):
        raise CommsCompilerError("authority source IDs must be unique and non-empty")

    intents = adapter.get("intents")
    if not isinstance(intents, dict) or not intents:
        raise CommsCompilerError("intents must be non-empty")
    for name, intent in intents.items():
        if not isinstance(intent, dict):
            raise CommsCompilerError(f"intent {name!r} must be an object")
        for field in ("identityField", "classificationField", "statusField"):
            if not isinstance(intent.get(field), str) or not intent[field]:
                raise CommsCompilerError(f"intent {name!r} missing {field}")
        statuses = intent.get("requiredStatuses")
        if not isinstance(statuses, list) or not statuses or len(set(statuses)) != len(statuses):
            raise CommsCompilerError(
                f"intent {name!r} requiredStatuses must be unique and non-empty"
            )
        required_sources = intent.get("requiredSources")
        if not isinstance(required_sources, list) or not required_sources:
            raise CommsCompilerError(f"intent {name!r} requiredSources must be non-empty")
        unknown = sorted(set(required_sources) - set(source_ids))
        if unknown:
            raise CommsCompilerError(f"intent {name!r} references unknown sources: {unknown}")
        fields = intent.get("allowedRenderFields")
        if not isinstance(fields, list) or not fields:
            raise CommsCompilerError(f"intent {name!r} allowedRenderFields must be non-empty")


def compile_evidence(adapter: dict[str, Any], evidence: dict[str, Any]) -> dict[str, Any]:
    validate_adapter(adapter)
    violations: list[dict[str, Any]] = []

    def add(code: str, message: str, **details: Any) -> None:
        violation = {"code": code, "message": message}
        if details:
            violation["details"] = details
        violations.append(violation)

    if evidence.get("schemaVersion") != EVIDENCE_SCHEMA:
        add("EVIDENCE_SCHEMA_UNSUPPORTED", "evidence packet schemaVersion is unsupported")

    project_id = str(adapter["project"]["id"])
    if evidence.get("projectId") != project_id:
        add(
            "PROJECT_MISMATCH",
            "evidence packet project does not match adapter",
            expected=project_id,
            observed=evidence.get("projectId"),
        )

    intent_name = evidence.get("intent")
    intent = adapter["intents"].get(intent_name)
    if not isinstance(intent, dict):
        add("INTENT_UNSUPPORTED", "evidence packet intent is not supported", observed=intent_name)
        return _result(adapter, evidence, None, violations, Counter())

    observed_sources = {
        str(source.get("id", ""))
        for source in evidence.get("sources", [])
        if isinstance(source, dict) and source.get("id")
    }
    for source_id in intent["requiredSources"]:
        if source_id not in observed_sources:
            add("REQUIRED_SOURCE_MISSING", "required evidence source is missing", sourceId=source_id)

    topics = evidence.get("topics", [])
    if not isinstance(topics, list):
        add("TOPICS_INVALID", "topics must be an array")
        topics = []
    leaks = sorted(set(intent.get("forbiddenTopics", [])).intersection(str(topic) for topic in topics))
    if leaks:
        add("FORBIDDEN_TOPIC_PRESENT", "unrelated topic leaked into evidence packet", topics=leaks)

    items = evidence.get("items")
    if not isinstance(items, list):
        add("ITEMS_INVALID", "items must be an array")
        items = []

    expected_count = evidence.get("expectedItemCount")
    if not isinstance(expected_count, int) or expected_count < 0:
        add("EXPECTED_COUNT_INVALID", "expectedItemCount must be a non-negative integer")
    elif len(items) != expected_count:
        add(
            "POPULATION_COUNT_MISMATCH",
            "observed item population does not match expectedItemCount",
            expected=expected_count,
            observed=len(items),
        )

    identity_field = intent["identityField"]
    classification_field = intent["classificationField"]
    status_field = intent["statusField"]
    identities: list[str] = []
    statuses: list[str] = []

    for index, item in enumerate(items):
        if not isinstance(item, dict):
            add("ITEM_INVALID", "item must be an object", index=index)
            continue
        identity = str(item.get(identity_field, "")).strip()
        classification = str(item.get(classification_field, "")).strip()
        status = str(item.get(status_field, "")).strip()
        if not identity:
            add("IDENTITY_MISSING", "item identity is missing", index=index)
        else:
            identities.append(identity)
        if not classification:
            add(
                "CLASSIFICATION_MISSING",
                "item classification is missing",
                index=index,
                identity=identity,
            )
        if not status:
            add("STATUS_MISSING", "item status is missing", index=index, identity=identity)
        else:
            statuses.append(status)

    duplicate_ids = sorted(
        identity for identity, count in Counter(identities).items() if count > 1
    )
    if duplicate_ids:
        add("DUPLICATE_IDENTITY", "item identities must be unique", identities=duplicate_ids)

    required_statuses = set(intent["requiredStatuses"])
    unexpected_statuses = sorted(set(statuses) - required_statuses)
    if unexpected_statuses:
        add(
            "UNEXPECTED_STATUS",
            "evidence packet contains unsupported status",
            statuses=unexpected_statuses,
        )

    status_counts = Counter(statuses)
    expected_status_counts = evidence.get("expectedStatusCounts")
    if not isinstance(expected_status_counts, dict):
        add("EXPECTED_STATUS_COUNTS_INVALID", "expectedStatusCounts must be an object")
        expected_status_counts = {}
    else:
        expected_keys = set(str(key) for key in expected_status_counts)
        if expected_keys != required_statuses:
            add(
                "EXPECTED_STATUS_SET_MISMATCH",
                "expectedStatusCounts keys must exactly match requiredStatuses",
                expected=sorted(required_statuses),
                observed=sorted(expected_keys),
            )
        for status in sorted(required_statuses):
            expected_value = expected_status_counts.get(status)
            if not isinstance(expected_value, int) or expected_value < 0:
                add(
                    "EXPECTED_STATUS_COUNT_INVALID",
                    "status count must be a non-negative integer",
                    status=status,
                )
                continue
            observed_value = status_counts.get(status, 0)
            if observed_value != expected_value:
                add(
                    "STATUS_COUNT_MISMATCH",
                    "observed status count does not match expected count",
                    status=status,
                    expected=expected_value,
                    observed=observed_value,
                )

    requested_fields = evidence.get("requestedRenderFields", intent["allowedRenderFields"])
    if not isinstance(requested_fields, list):
        add("RENDER_FIELDS_INVALID", "requestedRenderFields must be an array")
        requested_fields = []
    forbidden_fields = sorted(
        set(str(field) for field in requested_fields) - set(intent["allowedRenderFields"])
    )
    if forbidden_fields:
        add(
            "RENDER_FIELD_NOT_ALLOWED",
            "requested render field is not permitted by adapter",
            fields=forbidden_fields,
        )

    return _result(adapter, evidence, intent, violations, status_counts)


def _result(
    adapter: dict[str, Any],
    evidence: dict[str, Any],
    intent: dict[str, Any] | None,
    violations: list[dict[str, Any]],
    status_counts: Counter[str],
) -> dict[str, Any]:
    allowed_fields = list(intent.get("allowedRenderFields", [])) if intent else []
    group_by = intent.get("groupBy") if intent else None
    return {
        "schemaVersion": RESULT_SCHEMA,
        "result": "PASS" if not violations else "FAIL",
        "projectId": evidence.get("projectId"),
        "adapterId": adapter.get("adapterId"),
        "intent": evidence.get("intent"),
        "coverage": {
            "expectedItemCount": evidence.get("expectedItemCount"),
            "observedItemCount": len(evidence.get("items", []))
            if isinstance(evidence.get("items"), list)
            else 0,
            "observedStatusCounts": {key: status_counts[key] for key in sorted(status_counts)},
        },
        "renderContract": {
            "fields": allowed_fields,
            "groupBy": group_by,
            "proseGenerationAuthorized": not violations,
        },
        "violations": sorted(
            violations,
            key=lambda item: (
                item["code"],
                item["message"],
                json.dumps(item.get("details", {}), sort_keys=True),
            ),
        ),
        "proofCeiling": (
            "Deterministic contract and synthetic-fixture proof only; "
            "no live Drive/Gmail/LLM/provider execution is proven."
        ),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    try:
        result = compile_evidence(load_json(args.adapter), load_json(args.evidence))
    except CommsCompilerError as exc:
        print(f"comms-compiler error: {exc}")
        return 1

    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    print(rendered, end="")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    return 0 if result["result"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
