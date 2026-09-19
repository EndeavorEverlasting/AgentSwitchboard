from __future__ import annotations

import copy
import datetime as dt
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


class SchemaValidationError(AssertionError):
    pass


def load_json(relative: str):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def iter_string_values(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from iter_string_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_string_values(child)


def assert_public_coordination_privacy_safe(paths: list[Path]) -> None:
    values: list[str] = []
    for path in paths:
        if path.suffix.lower() == ".json":
            values.extend(iter_string_values(json.loads(path.read_text(encoding="utf-8"))))
        else:
            values.append(path.read_text(encoding="utf-8"))

    forbidden_patterns = (
        re.compile(r"(?i)[A-Z]:[\\/]+Users[\\/]+[^\\/\r\n\"']+"),
        re.compile(r"(?i)OneDrive\s*-\s*[^\\/\r\n\"']+"),
    )
    for value in values:
        for pattern in forbidden_patterns:
            assert pattern.search(value) is None, (
                f"private workstation path leaked into public coordination: {pattern.pattern}"
            )


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
    raise SchemaValidationError(f"unsupported schema type: {expected}")


def validate_json_schema(value, schema: dict, path: str = "$") -> None:
    if "oneOf" in schema:
        matches = 0
        for option in schema["oneOf"]:
            try:
                validate_json_schema(value, option, path)
                matches += 1
            except SchemaValidationError:
                pass
        if matches != 1:
            raise SchemaValidationError(f"{path}: expected exactly one oneOf match, got {matches}")
        return

    if "const" in schema and value != schema["const"]:
        raise SchemaValidationError(f"{path}: expected const {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        raise SchemaValidationError(f"{path}: value {value!r} is not in enum")

    expected_type = schema.get("type")
    if expected_type is not None:
        allowed = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(_matches_type(value, candidate) for candidate in allowed):
            raise SchemaValidationError(f"{path}: expected type {allowed}, got {type(value).__name__}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [name for name in required if name not in value]
        if missing:
            raise SchemaValidationError(f"{path}: missing required properties {missing}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value).difference(properties))
            if extras:
                raise SchemaValidationError(f"{path}: unexpected properties {extras}")
        for name, child in value.items():
            if name in properties:
                validate_json_schema(child, properties[name], f"{path}.{name}")

    if isinstance(value, list):
        minimum_items = schema.get("minItems")
        if minimum_items is not None and len(value) < minimum_items:
            raise SchemaValidationError(f"{path}: expected at least {minimum_items} item(s)")
        item_schema = schema.get("items")
        if item_schema:
            for index, child in enumerate(value):
                validate_json_schema(child, item_schema, f"{path}[{index}]")

    if isinstance(value, str):
        minimum_length = schema.get("minLength")
        if minimum_length is not None and len(value) < minimum_length:
            raise SchemaValidationError(f"{path}: string shorter than {minimum_length}")
        pattern = schema.get("pattern")
        if pattern and re.search(pattern, value) is None:
            raise SchemaValidationError(f"{path}: string does not match {pattern!r}")
        value_format = schema.get("format")
        if value_format == "date-time":
            try:
                parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError as exc:
                raise SchemaValidationError(f"{path}: invalid date-time") from exc
            if parsed.tzinfo is None:
                raise SchemaValidationError(f"{path}: date-time must include timezone")
        elif value_format == "uri":
            parsed_uri = urlparse(value)
            if not parsed_uri.scheme or not parsed_uri.netloc:
                raise SchemaValidationError(f"{path}: invalid absolute URI")

    if isinstance(value, int) and not isinstance(value, bool):
        minimum = schema.get("minimum")
        if minimum is not None and value < minimum:
            raise SchemaValidationError(f"{path}: integer below minimum {minimum}")


def main() -> None:
    registry = load_json("plans/plan-registry.json")
    schema = load_json("plans/schemas/public-plan.schema.json")
    startup_schema = load_json("tooling/gnhf/schemas/agent-startup-readiness.schema.json")
    fixture = load_json("tooling/gnhf/fixtures/startup-readiness/state.partial.json")

    assert registry["schemaVersion"] == 1
    assert registry["policy"]["planIsNotPullRequest"] is True
    assert registry["policy"]["machineReadableRequired"] is True
    assert schema["additionalProperties"] is False
    assert startup_schema["additionalProperties"] is False

    public_coordination_paths = [
        ROOT / "plans/plan-registry.json",
        ROOT / ".ai/WORK_QUEUE.md",
    ]
    validated_plans: list[dict] = []
    for entry in registry["plans"]:
        plan_path = ROOT / entry["path"]
        summary_path = ROOT / entry["summaryPath"]
        assert plan_path.is_file(), entry["path"]
        assert summary_path.is_file(), entry["summaryPath"]
        public_coordination_paths.extend((plan_path, summary_path))
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        validate_json_schema(plan, schema)
        validated_plans.append(plan)
        assert plan["planId"] == entry["planId"]
        assert plan["visibility"] == "public"
        assert plan["repository"] == "EndeavorEverlasting/AgentSwitchboard"
        assert plan["tasks"]
        assert plan["forbiddenScope"]
        assert plan["proof"]["ceiling"]

    malformed = copy.deepcopy(validated_plans[0])
    malformed["unexpectedContractField"] = True
    try:
        validate_json_schema(malformed, schema)
    except SchemaValidationError:
        pass
    else:
        raise AssertionError("public plan schema validator accepted an undeclared property")

    assert_public_coordination_privacy_safe(public_coordination_paths)

    readme = (ROOT / "plans/README.md").read_text(encoding="utf-8")
    assert "plan" in readme.lower() and "pull request" in readme.lower()
    assert "must not become the only place" in readme

    skill = (ROOT / ".ai/skills/public-plan-coordination/SKILL.md").read_text(encoding="utf-8")
    for token in (
        "id: public-plan-coordination",
        "status: canonical",
        "## Trigger",
        "## Inputs",
        "## Procedure",
        "## Outputs",
        "## Deterministic validation",
        "## Forbidden scope",
        "## Stop and escalate",
    ):
        assert token in skill, token

    launcher = (ROOT / "AgentSwitchboard.cmd").read_text(encoding="utf-8")
    assert launcher.index("Get-AgentSwitchboardStartupReport.ps1") < launcher.index("Start-AgentSwitchboard.ps1")
    assert "%ERRORLEVEL%" in launcher

    startup = (ROOT / "tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1").read_text(encoding="utf-8")
    for forbidden in (
        "Invoke-WebRequest",
        "winget install",
        "npm install",
        "opencode auth login",
        "gh auth login",
        "git push",
    ):
        assert forbidden.lower() not in startup.lower(), forbidden

    assert fixture["agents"]["opencode"]["available"] is True
    assert fixture["agents"]["goose"]["available"] is False
    assert "proofCeiling" in startup_schema["required"]

    template_registry = load_json("templates/repository-agent-contract/plans/plan-registry.json")
    assert template_registry["policy"]["planIsNotPullRequest"] is True
    assert (ROOT / "templates/repository-agent-contract/plans/schemas/public-plan.schema.json").is_file()

    print("PASS: public plan and startup readiness contracts")


if __name__ == "__main__":
    main()
