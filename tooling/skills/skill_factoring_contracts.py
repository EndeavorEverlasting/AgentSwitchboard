from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable, Sequence

REGISTRY_PATH = Path("tooling/skills/harness/command-delivery/skill-factoring.registry.json")
ROUTING_FIXTURE_PATH = Path("tooling/skills/harness/command-delivery/fixtures/routing-cases.fixture.json")
BOUNDARY_FIXTURE_PATH = Path("tooling/skills/harness/command-delivery/fixtures/powershell-boundary-cases.fixture.json")
SCHEMA_PATH = Path("tooling/skills/harness/command-delivery/schemas/skill-factoring-registry.schema.json")

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


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def route_case(payload: dict) -> tuple[str | None, list[str]]:
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


def validate_interactive_powershell(snippets: Sequence[str], delivery_mode: str) -> BoundaryResult:
    if delivery_mode != "interactive-copy-paste":
        return BoundaryResult("PASS", None, "Boundary rules do not apply to a saved script file.")

    if not snippets:
        return BoundaryResult("FAIL", "empty-artifact", "No executable snippet was supplied.")

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
        while index < len(lines):
            stripped = lines[index].strip()
            if stripped and stripped[0] == fence[0] and len(stripped) >= len(fence) and set(stripped) == {fence[0]}:
                break
            body.append(lines[index])
            index += 1
        if language in {"powershell", "pwsh", "ps1"}:
            blocks.append("\n".join(body))
        index += 1
    return blocks


def validate_registry(root: Path, registry: dict) -> list[Finding]:
    findings: list[Finding] = []
    dispositions = registry.get("dispositions", [])
    skill_ids = [item.get("skillId") for item in dispositions]
    triggers = [item.get("deterministicTrigger") for item in dispositions]

    findings.append(Finding("registry/dispositions", "PASS" if len(dispositions) >= 7 else "FAIL", f"{len(dispositions)} in-scope dispositions"))
    findings.append(Finding("registry/unique-skill-owners", "PASS" if len(skill_ids) == len(set(skill_ids)) else "FAIL", "skill IDs must be unique"))
    findings.append(Finding("registry/unique-primary-triggers", "PASS" if len(triggers) == len(set(triggers)) else "FAIL", "deterministic triggers must have one primary owner"))

    allowed = {"KEEP", "SPLIT", "MERGE", "RETIRE", "REWIRE"}
    required_arrays = ["requiredInputs", "producedOutputs", "preconditions", "forbiddenConditions", "guardrails", "owningFiles"]
    for item in dispositions:
        skill_id = str(item.get("skillId", "<missing>"))
        findings.append(Finding(f"disposition/{skill_id}", "PASS" if item.get("disposition") in allowed else "FAIL", str(item.get("disposition"))))
        for key in required_arrays:
            value = item.get(key)
            findings.append(Finding(f"contract/{skill_id}/{key}", "PASS" if isinstance(value, list) and len(value) > 0 else "FAIL", f"{len(value) if isinstance(value, list) else 0} entries"))
        proof = str(item.get("proofCeiling", "")).strip()
        findings.append(Finding(f"contract/{skill_id}/proof-ceiling", "PASS" if proof else "FAIL", proof or "missing"))
        for relative in item.get("owningFiles", []):
            findings.append(Finding(f"owner-file/{skill_id}/{relative}", "PASS" if (root / relative).is_file() else "FAIL", relative))

    precedence = registry.get("primaryTriggerPrecedence", [])
    findings.append(Finding("registry/precedence-covers-triggers", "PASS" if set(precedence) == set(triggers) else "FAIL", f"precedence={len(precedence)} triggers={len(triggers)}"))
    return findings


def validate_skill_boundaries(root: Path) -> list[Finding]:
    checks = {
        ".ai/skills/powershell-interactive-execution/SKILL.md": [
            "Trigger ID: `powershell.interactive-snippet`",
            "## Preconditions",
            "## Produced outputs",
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


def run_contracts(root: Path, candidate_path: Path | None = None, candidate_delivery_mode: str = "interactive-copy-paste") -> tuple[list[Finding], dict]:
    registry = load_json(root / REGISTRY_PATH)
    routing = load_json(root / ROUTING_FIXTURE_PATH)
    boundary = load_json(root / BOUNDARY_FIXTURE_PATH)

    findings = validate_registry(root, registry)
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

    candidate_summary: dict = {"requested": False}
    if candidate_path is not None:
        resolved = candidate_path.resolve()
        candidate_summary = {"requested": True, "path": str(resolved), "blocks": 0, "results": []}
        if not resolved.is_file():
            findings.append(Finding("candidate/path", "FAIL", f"missing candidate: {resolved}"))
        else:
            if resolved.suffix.lower() in {".md", ".markdown"}:
                snippets = extract_powershell_blocks(resolved.read_text(encoding="utf-8"))
            else:
                snippets = [resolved.read_text(encoding="utf-8")]
            candidate_summary["blocks"] = len(snippets)
            if not snippets:
                findings.append(Finding("candidate/powershell-blocks", "FAIL", "no PowerShell block found"))
            for index, snippet in enumerate(snippets):
                result = validate_interactive_powershell([snippet], candidate_delivery_mode)
                candidate_summary["results"].append(asdict(result))
                findings.append(Finding(f"candidate/block-{index + 1}", result.status, f"{result.rule}: {result.detail}"))

    return findings, candidate_summary


def write_report(output_root: Path, findings: Iterable[Finding], candidate: dict) -> tuple[Path, Path, str]:
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
