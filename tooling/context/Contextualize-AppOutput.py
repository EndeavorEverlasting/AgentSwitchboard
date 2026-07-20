#!/usr/bin/env python3
"""Offline app-output contextualization for AgentSwitchboard.

This tool reads supplied output; it never launches or attaches to an application.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

SCHEMA = "agentswitchboard.app-output-context/v1"
REGISTRY_SCHEMA = "ai-harness-prompt-registry/v1"
SURFACES = ("regular_ai_prompt", "gnhf_launch_artifact")
SEVERITY_ORDER = {"none": 0, "info": 1, "warning": 2, "error": 3, "blocked": 4}

TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z0-9_.:/-]{2,}")
EMAIL_RE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.I)
PRIVATE_IP_RE = re.compile(
    r"(?<![\d.])(?:"
    r"10(?:\.\d{1,3}){3}|"
    r"127(?:\.\d{1,3}){3}|"
    r"169\.254(?:\.\d{1,3}){2}|"
    r"172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|"
    r"192\.168(?:\.\d{1,3}){2}"
    r")(?![\d.])"
)
WINDOWS_USER_RE = re.compile(r"(?i)\b[A-Z]:\\Users\\[^\\\s]+")
UNIX_HOME_RE = re.compile(r"(?<![\w/])/home/[^/\s]+")
SECRET_PATTERNS = (
    re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{8,}"),
    re.compile(r"(?i)\b(api[_ -]?key|token|secret|password)\s*[:=]\s*[^\s,;]+"),
)
SIGNALS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("blocked", "blocked", ("blocked", "cannot continue", "permission denied", "unauthorized", "forbidden")),
    ("timeout", "error", ("timeout", "timed out", "deadline exceeded")),
    ("exception", "error", ("exception", "traceback", "stack trace", "fatal")),
    ("failure", "error", ("failed", "failure", "error", "non-zero", "exit code")),
    ("missing_dependency", "error", ("not found", "missing dependency", "command not found", "enoent")),
    ("validation", "warning", ("validation", "schema", "contract", "assertion", "mismatch")),
    ("warning", "warning", ("warning", "warn", "deprecated")),
    ("success", "info", ("success", "passed", "complete", "completed", "ready")),
)
STOPWORDS = {
    "about", "after", "again", "against", "also", "because", "before", "being", "between",
    "could", "does", "each", "from", "have", "into", "more", "most", "only", "other",
    "output", "same", "should", "some", "such", "than", "that", "their", "then", "there",
    "these", "they", "this", "through", "using", "when", "where", "which", "while", "with",
    "would", "your", "agent", "application", "prompt",
}


@dataclass(frozen=True)
class ParsedOutput:
    format: str
    records: list[str]


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def load_registry(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise ValueError(f"Prompt registry not found: {path}")
    if path.name.lower().endswith(".gz.b64"):
        try:
            payload = gzip.decompress(base64.b64decode(path.read_text(encoding="ascii").strip()))
        except Exception as exc:
            raise ValueError(f"Prompt registry bundle is invalid: {exc}") from exc
        raw = payload.decode("utf-8")
    else:
        raw = load_text(path)
    try:
        registry = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Prompt registry is not valid JSON: {exc}") from exc
    if registry.get("schemaVersion") != REGISTRY_SCHEMA:
        raise ValueError(f"Unsupported prompt registry schema: {registry.get('schemaVersion')!r}")
    prompts = registry.get("prompts")
    if not isinstance(prompts, list) or not prompts:
        raise ValueError("Prompt registry must contain a non-empty prompts array.")
    seen: set[str] = set()
    for prompt in prompts:
        prompt_id = str(prompt.get("id", ""))
        if not re.fullmatch(r"P\d{2,3}", prompt_id):
            raise ValueError(f"Invalid prompt ID: {prompt_id!r}")
        if prompt_id in seen:
            raise ValueError(f"Duplicate prompt ID: {prompt_id}")
        seen.add(prompt_id)
        surface = prompt.get("executionSurface")
        if surface not in SURFACES:
            raise ValueError(f"Prompt {prompt_id} has unsupported execution surface: {surface!r}")
    return registry


def parse_output(raw: str) -> ParsedOutput:
    stripped = raw.strip()
    if not stripped:
        return ParsedOutput("text", [])
    try:
        value = json.loads(stripped)
    except json.JSONDecodeError:
        jsonl: list[str] = []
        nonempty = [line for line in raw.splitlines() if line.strip()]
        if nonempty:
            for line in nonempty:
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    jsonl = []
                    break
                jsonl.extend(flatten_json(value))
        if jsonl:
            return ParsedOutput("jsonl", jsonl)
        return ParsedOutput("text", [line.strip() for line in raw.splitlines() if line.strip()])
    return ParsedOutput("json", flatten_json(value))


def flatten_json(value: Any, prefix: str = "") -> list[str]:
    records: list[str] = []
    if isinstance(value, dict):
        for key in sorted(value):
            child = f"{prefix}.{key}" if prefix else str(key)
            records.extend(flatten_json(value[key], child))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            records.extend(flatten_json(item, f"{prefix}[{index}]"))
    else:
        rendered = json.dumps(value, ensure_ascii=False) if value is not None else "null"
        records.append(f"{prefix}={rendered}" if prefix else rendered)
    return records


def redact(text: str) -> str:
    value = text
    value = SECRET_PATTERNS[0].sub(lambda match: f"{match.group(1)} <redacted>", value)
    value = SECRET_PATTERNS[1].sub(lambda match: f"{match.group(1)}=<redacted>", value)
    value = EMAIL_RE.sub("<redacted-email>", value)
    value = PRIVATE_IP_RE.sub("<redacted-private-ip>", value)
    value = WINDOWS_USER_RE.sub("%USERPROFILE%", value)
    value = UNIX_HOME_RE.sub("$HOME", value)
    return value


def normalize_records(records: Iterable[str], max_record_chars: int = 800) -> list[str]:
    normalized: list[str] = []
    for record in records:
        item = redact(str(record)).strip()
        if not item:
            continue
        item = re.sub(r"\s+", " ", item)
        if len(item) > max_record_chars:
            item = item[: max_record_chars - 1] + "…"
        normalized.append(item)
    return normalized


def classify_signals(records: list[str]) -> tuple[list[dict[str, Any]], str]:
    joined = "\n".join(records).lower()
    signals: list[dict[str, Any]] = []
    highest = "none"
    for signal_id, severity, needles in SIGNALS:
        matches = [needle for needle in needles if needle in joined]
        if matches:
            signals.append({"signalId": signal_id, "severity": severity, "matches": matches[:4]})
            if SEVERITY_ORDER[severity] > SEVERITY_ORDER[highest]:
                highest = severity
    if highest == "none" and records:
        highest = "info"
    return signals, highest


def keywords(records: list[str], limit: int = 24) -> list[str]:
    counts: Counter[str] = Counter()
    for record in records:
        for token in TOKEN_RE.findall(record.lower()):
            token = token.strip("._:/-")
            if len(token) < 3 or token in STOPWORDS or token.startswith("redacted"):
                continue
            counts[token] += 1
    return [token for token, _ in counts.most_common(limit)]


def prompt_haystack(prompt: dict[str, Any]) -> str:
    fields = (
        "id", "name", "moment", "promptType", "promptClass", "sprintPathRole",
        "useThisWhen", "doNotUseWhen", "expectedOutput", "text",
    )
    return "\n".join(str(prompt.get(field, "")) for field in fields).lower()


def rank_prompts(
    registry: dict[str, Any],
    records: list[str],
    surface: str,
    top: int,
) -> list[dict[str, Any]]:
    terms = keywords(records)
    signal_text = "\n".join(records).lower()
    ranked: list[tuple[int, int, str, dict[str, Any]]] = []
    for prompt in registry["prompts"]:
        if prompt.get("executionSurface") != surface:
            continue
        haystack = prompt_haystack(prompt)
        score = 0
        matched: list[str] = []
        for term in terms:
            if term in haystack:
                weight = min(4, 1 + signal_text.count(term))
                score += weight
                matched.append(term)
        use_when = str(prompt.get("useThisWhen", "")).lower()
        if use_when and any(term in use_when for term in terms):
            score += 3
        do_not = str(prompt.get("doNotUseWhen", "")).lower()
        if do_not and any(term in do_not for term in terms):
            score = max(0, score - 4)
        if score <= 0:
            continue
        sequence = int(prompt.get("sequence", 10_000))
        ranked.append((score, -sequence, str(prompt["id"]), {
            "promptId": str(prompt["id"]),
            "name": str(prompt.get("name", "")),
            "score": score,
            "executionSurface": surface,
            "matchedTerms": sorted(set(matched))[:8],
            "useThisWhen": str(prompt.get("useThisWhen", ""))[:240],
            "requiredVariables": [str(item) for item in prompt.get("requiredVariables", [])],
        }))
    ranked.sort(key=lambda item: (-item[0], -item[1], item[2]))
    return [item[3] for item in ranked[:top]]


def choose_excerpts(records: list[str], limit: int = 6, max_chars: int = 360) -> list[str]:
    scored: list[tuple[int, int, str]] = []
    needles = tuple(needle for _, _, values in SIGNALS for needle in values)
    for index, record in enumerate(records):
        lowered = record.lower()
        score = sum(3 for needle in needles if needle in lowered)
        if any(marker in lowered for marker in ("exit", "exception", "failed", "blocked", "timeout")):
            score += 2
        scored.append((score, -index, record[:max_chars]))
    scored.sort(reverse=True)
    excerpts = [entry[2] for entry in scored[:limit] if entry[2]]
    return excerpts


def build_instruction(highest: str, candidates: list[dict[str, Any]]) -> tuple[str, str]:
    if highest in {"blocked", "error"}:
        action = "Diagnose the highest-severity failure, preserve the proof ceiling, and repair only the owned surface."
    elif highest == "warning":
        action = "Reconcile warnings and contract drift before claiming completion."
    else:
        action = "Verify the observed state against the requested acceptance criteria before continuing."
    if candidates:
        route = "Use the highest-ranked prompt-kit procedure only after filling its required variables from current repository evidence."
    else:
        route = "No prompt-kit match cleared the deterministic threshold; inspect the output and choose a workflow explicitly."
    return action, route


def contextualize(
    raw: str,
    registry: dict[str, Any],
    *,
    source_app: str,
    surface: str,
    top: int = 3,
    max_packet_chars: int = 8_000,
) -> dict[str, Any]:
    if surface not in SURFACES:
        raise ValueError(f"Unsupported execution surface: {surface}")
    parsed = parse_output(raw)
    records = normalize_records(parsed.records)
    signals, highest = classify_signals(records)
    candidates = rank_prompts(registry, records, surface, top)
    action, route = build_instruction(highest, candidates)
    packet: dict[str, Any] = {
        "schema": SCHEMA,
        "generatedUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "application": source_app,
            "format": parsed.format,
            "sha256": sha256_text(raw),
            "rawOutputStored": False,
            "recordCount": len(records),
        },
        "context": {
            "highestSeverity": highest,
            "signals": signals,
            "keywords": keywords(records, 16),
            "excerpts": choose_excerpts(records),
        },
        "promptKit": {
            "schemaVersion": str(registry["schemaVersion"]),
            "kitVersion": str(registry.get("kitVersion", "unknown")),
            "requestedExecutionSurface": surface,
            "candidates": candidates,
            "crossSurfaceFallbackAllowed": False,
        },
        "instructionPacket": {
            "action": action,
            "routing": route,
            "suggestedPromptIds": [item["promptId"] for item in candidates],
            "requiredVariables": sorted({
                variable for item in candidates for variable in item["requiredVariables"]
            }),
            "proofRule": "Supplied output is evidence to interpret, not proof that the application, agent, or target succeeded.",
        },
        "proof": {
            "level": "offline-contextualization",
            "ceiling": "Offline parsing, redaction, signal extraction, deterministic prompt-kit ranking, and compact instruction rendering only. No application execution, provider response, repository mutation, target behavior, or runtime success is proven.",
        },
    }
    encoded = json.dumps(packet, ensure_ascii=False, separators=(",", ":"))
    if len(encoded) > max_packet_chars:
        packet["context"]["excerpts"] = packet["context"]["excerpts"][:2]
        packet["context"]["keywords"] = packet["context"]["keywords"][:8]
        packet["promptKit"]["candidates"] = packet["promptKit"]["candidates"][:1]
        packet["instructionPacket"]["suggestedPromptIds"] = [
            item["promptId"] for item in packet["promptKit"]["candidates"]
        ]
        packet["instructionPacket"]["requiredVariables"] = sorted({
            variable
            for item in packet["promptKit"]["candidates"]
            for variable in item["requiredVariables"]
        })
    return packet


def render_report(packet: dict[str, Any]) -> str:
    candidates = packet["promptKit"]["candidates"]
    candidate_lines = [
        f"- {item['promptId']} — {item['name']} (score {item['score']}; matches: {', '.join(item['matchedTerms']) or 'none'})"
        for item in candidates
    ] or ["- No deterministic prompt-kit match."]
    signal_lines = [
        f"- {item['signalId']}: {item['severity']} ({', '.join(item['matches'])})"
        for item in packet["context"]["signals"]
    ] or ["- No known failure or warning signal."]
    excerpt_lines = [f"- `{item}`" for item in packet["context"]["excerpts"]] or ["- No non-empty records."]
    return "\n".join([
        "# APP OUTPUT CONTEXT",
        "",
        f"- Application: `{packet['source']['application']}`",
        f"- Input format: `{packet['source']['format']}`",
        f"- Input SHA-256: `{packet['source']['sha256']}`",
        f"- Highest severity: `{packet['context']['highestSeverity']}`",
        f"- Execution surface: `{packet['promptKit']['requestedExecutionSurface']}`",
        "",
        "## Signals",
        *signal_lines,
        "",
        "## Minimized excerpts",
        *excerpt_lines,
        "",
        "## Prompt-kit candidates",
        *candidate_lines,
        "",
        "## Agent instruction",
        packet["instructionPacket"]["action"],
        "",
        packet["instructionPacket"]["routing"],
        "",
        f"Proof rule: {packet['instructionPacket']['proofRule']}",
        "",
        f"Proof ceiling: {packet['proof']['ceiling']}",
        "",
    ])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Parse supplied app output into a compact prompt-kit-aware instruction packet.")
    parser.add_argument("--input", required=True, type=Path, help="UTF-8 text, JSON, or JSONL output file.")
    parser.add_argument("--prompt-registry", required=True, type=Path, help="ai-harness-prompt-registry/v1 JSON or .gz.b64 bundle.")
    parser.add_argument("--source-app", required=True, help="Stable public application or adapter label; do not include private hostnames.")
    parser.add_argument("--execution-surface", required=True, choices=SURFACES)
    parser.add_argument("--output-root", required=True, type=Path, help="Directory outside the source repository.")
    parser.add_argument("--top", type=int, default=3, choices=range(1, 6), metavar="1-5")
    parser.add_argument("--max-packet-chars", type=int, default=8_000)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        raw = load_text(args.input)
        registry = load_registry(args.prompt_registry)
        packet = contextualize(
            raw,
            registry,
            source_app=args.source_app,
            surface=args.execution_surface,
            top=args.top,
            max_packet_chars=args.max_packet_chars,
        )
        args.output_root.mkdir(parents=True, exist_ok=True)
        json_path = args.output_root / "app-output-context.json"
        report_path = args.output_root / "app-output-context.md"
        json_path.write_text(json.dumps(packet, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        report_path.write_text(render_report(packet), encoding="utf-8")
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(f"Context JSON: {json_path}")
    print(f"English report: {report_path}")
    print(f"Proof ceiling: {packet['proof']['ceiling']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
