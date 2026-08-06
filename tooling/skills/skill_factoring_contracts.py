from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

REGISTRY_PATH = Path("tooling/skills/harness/command-delivery/skill-factoring.registry.json")
ROUTING_FIXTURE_PATH = Path("tooling/skills/harness/command-delivery/fixtures/routing-cases.fixture.json")
BOUNDARY_FIXTURE_PATH = Path("tooling/skills/harness/command-delivery/fixtures/powershell-boundary-cases.fixture.json")
SCHEMA_PATH = Path("tooling/skills/harness/command-delivery/schemas/skill-factoring-registry.schema.json")
TRIGGER_MAP_PATH = Path("TRIGGERS.md")

DETACHED_CONTINUATION = re.compile(r"^\s*(elseif|else|catch|finally)\b", re.IGNORECASE)
ATTACHED_CONTINUATION = re.compile(r"}\s*(elseif|else|catch|finally)\b", re.IGNORECASE)
FENCE_OPEN = re.compile(r"^\s*(`{3,}|~{3,})\s*([^\s`]*)\s*$")


@dataclass(frozen=True)
class Finding:
    check: str
    status: str
    detail: str


@dataclass(frozen=True)
class BoundaryResult:
    status: str
    rule: str | None
    detail: str


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return payload


def route_case(payload: dict[str, Any]) -> tuple[str | None, list[str]]:
    intent = str(payload.get("intent", ""))
    shell = str(payload.get("shell", "")).lower()
    delivery = str(payload.get("deliveryMode", ""))
    operator_facing = bool(payload.get("operatorFacing", False))

    primary: str | None
    required: list[str] = []

    if intent == "gnhf-prompt":
        primary = "gnhf-prompt-compilation"
    elif intent == "stale-checkout-exact-head":
        primary = "stale-checkout-exact-head-bootstrap"
    elif intent == "runtime-end-to-end":
        primary = "end-to-end-runtime-validation"
    elif intent == "workstation-certification":
        primary = "windows-profile-live-certification"
    elif intent == "repo-intake":
        primary = "repo-intake"
    elif intent == "command" and shell in {"powershell", "pwsh", "windows-powershell"} and delivery == "interactive-copy-paste":
        primary = "powershell-interactive-execution"
    elif intent == "command" and operator_facing:
        primary = "operator-command-envelope"
    else:
        primary = None

    if primary in {
        "gnhf-prompt-compilation",
        "stale-checkout-exact-head-bootstrap",
        "end-to-end-runtime-validation",
        "windows-profile-live-certification",
    }:
        if operator_facing:
            required.append("operator-command-envelope")
        if shell in {"powershell", "pwsh", "windows-powershell"} and delivery == "interactive-copy-paste":
            required.append("powershell-interactive-execution")
    elif primary == "powershell-interactive-execution" and operator_facing:
        required.append("operator-command-envelope")

    return primary, sorted(set(required))


def _powershell_structure_error(text: str) -> str | None:
    stack: list[tuple[str, int]] = []
    matching = {"}": "{", "]": "[", ")": "("}
    opening = set(matching.values())
    state = "normal"
    index = 0
    line = 1
    escaped = False
    here_end: str | None = None
    at_line_start = True

    while index < len(text):
        char = text[index]
        next_two = text[index : index + 2]

        if char == "\n":
            line += 1
            at_line_start = True
            if state == "line-comment":
                state = "normal"
            index += 1
            escaped = False
            continue

        if state == "line-comment":
            index += 1
            continue
        if state == "block-comment":
            if next_two == "#>":
                state = "normal"
                index += 2
            else:
                index += 1
            continue
        if state in {"single-quote", "double-quote"}:
            quote = "'" if state == "single-quote" else '"'
            if escaped:
                escaped = False
            elif char == "`":
                escaped = True
            elif char == quote:
                if state == "single-quote" and index + 1 < len(text) and text[index + 1] == "'":
                    index += 2
                    continue
                state = "normal"
            index += 1
            continue
        if state == "here-string":
            if at_line_start and here_end and text.startswith(here_end, index):
                after = index + len(here_end)
                if after == len(text) or text[after] in "\r\n":
                    state = "normal"
                    here_end = None
                    index = after
                    at_line_start = False
                    continue
            at_line_start = False
            index += 1
            continue

        if next_two == "<#":
            state = "block-comment"
            index += 2
            at_line_start = False
            continue
        if char == "#":
            state = "line-comment"
            index += 1
            at_line_start = False
            continue
        if next_two in {"@'", '@"'}:
            state = "here-string"
            here_end = "'@" if next_two == "@'" else '"@'
            index += 2
            at_line_start = False
            continue
        if char == "'":
            state = "single-quote"
            index += 1
            at_line_start = False
            continue
        if char == '"':
            state = "double-quote"
            index += 1
            at_line_start = False
            continue
        if char in opening:
            stack.append((char, line))
        elif char in matching:
            if not stack or stack[-1][0] != matching[char]:
                return f"Unexpected closing delimiter {char!r} on line {line}."
            stack.pop()
        at_line_start = False
        index += 1

    if state == "block-comment":
        return "Unterminated block comment."
    if state in {"single-quote", "double-quote"}:
        return "Unterminated quoted string."
    if state == "here-string":
        return "Unterminated here-string."
    if stack:
        delimiter, opened_line = stack[-1]
        return f"Unclosed delimiter {delimiter!r} opened on line {opened_line}."
    if text.rstrip().endswith("`"):
        return "Trailing PowerShell continuation escape leaves the submission incomplete."
    return None


def validate_interactive_powershell(snippets: Sequence[str], delivery_mode: str) -> BoundaryResult:
    if not snippets:
        return BoundaryResult("FAIL", "empty-artifact", "No executable snippet was supplied.")

    for index, snippet in enumerate(snippets):
        structure_error = _powershell_structure_error(snippet)
        if structure_error:
            return BoundaryResult(
                "FAIL",
                "incomplete-powershell-syntax",
                f"Snippet {index + 1} is not a complete PowerShell syntax unit: {structure_error}",
            )

    if delivery_mode != "interactive-copy-paste":
        return BoundaryResult("PASS", None, "The saved script is structurally complete; interactive submission rules do not apply.")

    for index, snippet in enumerate(snippets):
        first_line = next((line for line in snippet.splitlines() if line.strip()), "")
        if DETACHED_CONTINUATION.search(first_line):
            return BoundaryResult(
                "FAIL",
                "detached-continuation-snippet",
                f"Snippet {index + 1} begins with a continuation keyword and can be orphaned after the previous submission executes.",
            )

    continuation_lines = [
        line
        for snippet in snippets
        for line in snippet.splitlines()
        if DETACHED_CONTINUATION.search(line) or ATTACHED_CONTINUATION.search(line)
    ]
    if not continuation_lines:
        return BoundaryResult("PASS", None, "No continuation keyword depends on a previous interactive submission.")

    if len(snippets) > 1:
        return BoundaryResult(
            "FAIL",
            "detached-continuation-snippet",
            "A compound statement is split across multiple interactive submissions.",
        )

    snippet = snippets[0]
    lines = [line for line in snippet.splitlines() if line.strip()]
    if len(lines) == 1:
        return BoundaryResult("PASS", None, "The compound statement is one physical submission line.")

    for line in lines:
        if DETACHED_CONTINUATION.search(line):
            return BoundaryResult(
                "FAIL",
                "continuation-not-attached",
                "A continuation keyword starts a new physical line instead of remaining attached to the preceding closing brace.",
            )

    attached_count = sum(1 for line in lines if ATTACHED_CONTINUATION.search(line))
    if attached_count != len(continuation_lines):
        return BoundaryResult(
            "FAIL",
            "continuation-not-attached",
            "Every else, elseif, catch, and finally must appear on the same physical line as the preceding closing brace.",
        )

    if lines[0].strip() != "& {" or lines[-1].strip() != "}":
        return BoundaryResult(
            "FAIL",
            "compound-block-not-atomic",
            "A multiline interactive compound statement must be enclosed in one outer '& { ... }' script block.",
        )

    return BoundaryResult("PASS", None, "The multiline compound statement is one outer script block with attached continuations.")


def extract_powershell_blocks(markdown: str) -> list[str]:
    blocks: list[str] = []
    lines = markdown.splitlines()
    index = 0
    while index < len(lines):
        match = FENCE_OPEN.match(lines[index])
        if not match:
            index += 1
            continue
        fence = match.group(1)
        language = match.group(2).lower()
        index += 1
        body: list[str] = []
        closed = False
        while index < len(lines):
            stripped = lines[index].strip()
            if stripped and stripped[0] == fence[0] and len(stripped) >= len(fence) and set(stripped) == {fence[0]}:
                closed = True
                break
            body.append(lines[index])
            index += 1
        if not closed:
            raise ValueError(f"Unterminated Markdown fence for language {language or '<none>'}.")
        if language in {"powershell", "pwsh", "ps1"}:
            blocks.append("\n".join(body))
        index += 1
    return blocks


def _schema_type_matches(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }.get(expected, False)


def validate_json_schema(instance: Any, schema: dict[str, Any], path: str = "$") -> list[str]:
    errors: list[str] = []
    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: expected const {schema['const']!r}, got {instance!r}")
    if "enum" in schema and instance not in schema["enum"]:
        errors.append(f"{path}: value {instance!r} is not in enum {schema['enum']!r}")

    expected_type = schema.get("type")
    if isinstance(expected_type, str) and not _schema_type_matches(instance, expected_type):
        errors.append(f"{path}: expected type {expected_type}, got {type(instance).__name__}")
        return errors

    if isinstance(instance, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                errors.append(f"{path}: missing required property {key!r}")
        min_properties = schema.get("minProperties")
        if isinstance(min_properties, int) and len(instance) < min_properties:
            errors.append(f"{path}: expected at least {min_properties} properties")
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for key, child_schema in properties.items():
                if key in instance and isinstance(child_schema, dict):
                    errors.extend(validate_json_schema(instance[key], child_schema, f"{path}.{key}"))
            if schema.get("additionalProperties") is False:
                unexpected = sorted(set(instance) - set(properties))
                for key in unexpected:
                    errors.append(f"{path}: unexpected property {key!r}")

    if isinstance(instance, list):
        min_items = schema.get("minItems")
        if isinstance(min_items, int) and len(instance) < min_items:
            errors.append(f"{path}: expected at least {min_items} items")
        if schema.get("uniqueItems") is True:
            normalized = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in instance]
            if len(normalized) != len(set(normalized)):
                errors.append(f"{path}: items must be unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(instance):
                errors.extend(validate_json_schema(item, item_schema, f"{path}[{index}]"))

    if isinstance(instance, str):
        min_length = schema.get("minLength")
        if isinstance(min_length, int) and len(instance) < min_length:
            errors.append(f"{path}: expected minimum length {min_length}")
    return errors


def validate_registry(root: Path, registry: dict[str, Any], schema: dict[str, Any]) -> list[Finding]:
    findings: list[Finding] = []
    schema_errors = validate_json_schema(registry, schema)
    findings.append(
        Finding(
            "registry/schema",
            "PASS" if not schema_errors else "FAIL",
            "complete schema validation passed" if not schema_errors else "; ".join(schema_errors),
        )
    )

    dispositions = registry.get("dispositions", [])
    if not isinstance(dispositions, list):
        dispositions = []
    skill_ids = [item.get("skillId") for item in dispositions if isinstance(item, dict)]
    triggers = [item.get("deterministicTrigger") for item in dispositions if isinstance(item, dict)]

    findings.append(Finding("registry/dispositions", "PASS" if len(dispositions) >= 7 else "FAIL", f"{len(dispositions)} in-scope dispositions"))
    findings.append(Finding("registry/unique-skill-owners", "PASS" if len(skill_ids) == len(set(skill_ids)) else "FAIL", "skill IDs must be unique"))
    findings.append(Finding("registry/unique-primary-triggers", "PASS" if len(triggers) == len(set(triggers)) else "FAIL", "deterministic triggers must have one primary owner"))

    allowed = {"KEEP", "SPLIT", "MERGE", "RETIRE", "REWIRE"}
    required_arrays = ["requiredInputs", "producedOutputs", "preconditions", "forbiddenConditions", "guardrails", "owningFiles"]
    for raw_item in dispositions:
        if not isinstance(raw_item, dict):
            findings.append(Finding("disposition/<invalid>", "FAIL", "disposition must be an object"))
            continue
        skill_id = str(raw_item.get("skillId", "<missing>"))
        findings.append(Finding(f"disposition/{skill_id}", "PASS" if raw_item.get("disposition") in allowed else "FAIL", str(raw_item.get("disposition"))))
        for key in required_arrays:
            value = raw_item.get(key)
            findings.append(Finding(f"contract/{skill_id}/{key}", "PASS" if isinstance(value, list) and len(value) > 0 else "FAIL", f"{len(value) if isinstance(value, list) else 0} entries"))
        proof = str(raw_item.get("proofCeiling", "")).strip()
        findings.append(Finding(f"contract/{skill_id}/proof-ceiling", "PASS" if proof else "FAIL", proof or "missing"))
        for relative in raw_item.get("owningFiles", []):
            findings.append(Finding(f"owner-file/{skill_id}/{relative}", "PASS" if (root / relative).is_file() else "FAIL", relative))

    precedence = registry.get("primaryTriggerPrecedence", [])
    findings.append(Finding("registry/precedence-covers-triggers", "PASS" if set(precedence) == set(triggers) else "FAIL", f"precedence={len(precedence) if isinstance(precedence, list) else 0} triggers={len(triggers)}"))

    trigger_map_path = root / TRIGGER_MAP_PATH
    trigger_map = trigger_map_path.read_text(encoding="utf-8") if trigger_map_path.is_file() else ""
    for trigger, skill_id in zip(triggers, skill_ids):
        findings.append(
            Finding(
                f"trigger-map/{trigger}",
                "PASS" if isinstance(trigger, str) and f"`{trigger}`" in trigger_map and isinstance(skill_id, str) and f"`{skill_id}`" in trigger_map else "FAIL",
                f"canonical map must register {trigger!r} -> {skill_id!r}",
            )
        )
    return findings


def validate_skill_boundaries(root: Path) -> list[Finding]:
    checks = {
        ".ai/skills/powershell-interactive-execution/SKILL.md": [
            "Trigger ID: `powershell.interactive-snippet`",
            "## Preconditions",
            "## Outputs",
            "## Owning files",
            "scripts/Test-SkillFactoringContracts.ps1",
            "} elseif",
            "} else",
            "} catch",
            "} finally",
        ],
        ".ai/skills/operator-command-envelope/SKILL.md": [
            "Trigger ID: `operator.command-artifact`",
            "powershell-interactive-execution",
            "does not own shell grammar",
        ],
        ".ai/skills/stale-checkout-exact-head-bootstrap/SKILL.md": [
            "powershell-interactive-execution",
            "operator-command-envelope",
            "Test-SkillFactoringContracts.ps1",
        ],
    }
    findings: list[Finding] = []
    for relative, markers in checks.items():
        path = root / relative
        if not path.is_file():
            findings.append(Finding(f"skill/{relative}", "FAIL", "missing"))
            continue
        text = path.read_text(encoding="utf-8")
        for marker in markers:
            findings.append(Finding(f"skill/{relative}/{marker}", "PASS" if marker in text else "FAIL", marker))
    return findings


def resolve_candidate_path(root: Path, candidate_path: Path) -> Path:
    return (candidate_path if candidate_path.is_absolute() else root / candidate_path).resolve()


def run_contracts(root: Path, candidate_path: Path | None = None, candidate_delivery_mode: str = "interactive-copy-paste") -> tuple[list[Finding], dict[str, Any]]:
    registry = load_json(root / REGISTRY_PATH)
    schema = load_json(root / SCHEMA_PATH)
    routing = load_json(root / ROUTING_FIXTURE_PATH)
    boundary = load_json(root / BOUNDARY_FIXTURE_PATH)

    findings = validate_registry(root, registry, schema)
    findings.extend(validate_skill_boundaries(root))

    for case in routing.get("cases", []):
        primary, required = route_case(case["input"])
        expected_primary = case.get("expectedPrimary")
        expected_required = sorted(case.get("expectedRequired", []))
        findings.append(Finding(f"route/{case['id']}/primary", "PASS" if primary == expected_primary else "FAIL", f"expected={expected_primary!r} actual={primary!r}"))
        findings.append(Finding(f"route/{case['id']}/required", "PASS" if required == expected_required else "FAIL", f"expected={expected_required!r} actual={required!r}"))

    for case in boundary.get("cases", []):
        result = validate_interactive_powershell(case.get("snippets", []), case.get("deliveryMode", "interactive-copy-paste"))
        expected = case.get("expected")
        expected_rule = case.get("expectedRule")
        pass_status = result.status == expected and (expected_rule is None or result.rule == expected_rule)
        findings.append(Finding(f"boundary/{case['id']}", "PASS" if pass_status else "FAIL", f"expected={expected}/{expected_rule} actual={result.status}/{result.rule}: {result.detail}"))

    candidate_summary: dict[str, Any] = {"requested": False}
    if candidate_path is not None:
        resolved = resolve_candidate_path(root, candidate_path)
        candidate_summary = {"requested": True, "path": str(resolved), "blocks": 0, "results": []}
        if not resolved.is_file():
            findings.append(Finding("candidate/path", "FAIL", f"missing candidate: {resolved}"))
        else:
            try:
                if resolved.suffix.lower() in {".md", ".markdown"}:
                    snippets = extract_powershell_blocks(resolved.read_text(encoding="utf-8"))
                else:
                    snippets = [resolved.read_text(encoding="utf-8")]
            except ValueError as exc:
                findings.append(Finding("candidate/markdown-fence", "FAIL", str(exc)))
                snippets = []
            candidate_summary["blocks"] = len(snippets)
            if not snippets and not any(f.check == "candidate/markdown-fence" for f in findings):
                findings.append(Finding("candidate/powershell-blocks", "FAIL", "no PowerShell block found"))
            for index, snippet in enumerate(snippets):
                result = validate_interactive_powershell([snippet], candidate_delivery_mode)
                candidate_summary["results"].append(asdict(result))
                findings.append(Finding(f"candidate/block-{index + 1}", result.status, f"{result.rule}: {result.detail}"))

    return findings, candidate_summary


def write_report(output_root: Path, findings: Iterable[Finding], candidate: dict[str, Any]) -> tuple[Path, Path, str]:
    output_root.mkdir(parents=True, exist_ok=True)
    findings_list = list(findings)
    failed = [finding for finding in findings_list if finding.status != "PASS"]
    status = "PASS" if not failed else "FAIL"
    payload = {
        "schema": "agentswitchboard.skill-factoring-contract-report.v1",
        "status": status,
        "checks": len(findings_list),
        "failed": len(failed),
        "findings": [asdict(finding) for finding in findings_list],
        "candidate": candidate,
        "proofCeiling": "Repository skill ownership, deterministic trigger routing, fixture boundaries, and candidate command syntax-unit checks only. No operator-machine command execution or runtime behavior is proven.",
    }
    json_path = output_root / "skill-factoring-report.json"
    md_path = output_root / "skill-factoring-report.md"
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    rows = "\n".join(f"| {f.check} | {f.status} | {f.detail.replace('|', '/')} |" for f in findings_list)
    md_path.write_text(
        "# AgentSwitchboard Skill Factoring Contract\n\n"
        f"- Status: **{status}**\n"
        f"- Checks: **{len(findings_list)}**\n"
        f"- Failed: **{len(failed)}**\n\n"
        "| Check | Status | Detail |\n|---|---|---|\n"
        f"{rows}\n\n## Proof ceiling\n\n{payload['proofCeiling']}\n",
        encoding="utf-8",
    )
    return json_path, md_path, status


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate AgentSwitchboard skill factoring and interactive PowerShell boundaries.")
    parser.add_argument("--root", default=".")
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--candidate-path")
    parser.add_argument("--candidate-delivery-mode", default="interactive-copy-paste", choices=["interactive-copy-paste", "script-file"])
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    candidate = Path(args.candidate_path) if args.candidate_path else None
    findings, candidate_summary = run_contracts(root, candidate, args.candidate_delivery_mode)
    json_path, md_path, status = write_report(Path(args.output_root).resolve(), findings, candidate_summary)
    print(f"Skill factoring status: {status}")
    print(f"JSON: {json_path}")
    print(f"Report: {md_path}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
