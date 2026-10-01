#!/usr/bin/env python3
"""Static contract for the Entire CLI provider/continuity boundary."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/architecture/entire-cli-provider-continuity-boundary.md"
MAP = ROOT / "CODEBASE_MAP.md"


def main() -> int:
    assert DOC.is_file(), "missing Entire CLI architecture contract"
    text = DOC.read_text(encoding="utf-8")
    code_map = MAP.read_text(encoding="utf-8")

    required = (
        "provider-neutral Git, provenance, checkpoint, and agent-session transport adapter",
        "It is not an LLM",
        "entire agent-help --json",
        "entire status --json",
        "entire enable --agent opencode --telemetry=false",
        "entire session resume <branch>",
        "entire repo clone /gh/OWNER/REPO <target> --nearest",
        "entire repo mirror add /gh/OWNER/REPO",
        "GitHub and GitHub Actions remain optional provider adapters",
        "Entire transport does not replace repository-owned validation",
        "FirstMate owns live crew orchestration",
        "No silent paid fallback is authorized",
    )
    for marker in required:
        assert marker in text, f"Entire CLI contract missing marker: {marker}"

    assert "entire-cli-provider-continuity-boundary.md" in code_map
    assert "Entire CLI" in code_map
    assert "Git/provenance/session transport" in code_map

    forbidden = (
        "Entire is the inference provider",
        "Entire replaces FirstMate",
        "GitHub Actions is required",
    )
    for marker in forbidden:
        assert marker not in text, f"Entire CLI contract contains forbidden claim: {marker}"

    print("PASS: Entire CLI Git/provenance/session transport boundary is explicit and provider-neutral")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
