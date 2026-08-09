from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DONOR = "84fdeffd12f2ee307994d1eb6feb48173b6e0502"
VENDOR = ROOT / "third_party/mattpocock-skills" / DONOR
EXPECTED = {
    "prototype/LOGIC.md": "5f5a3fd5a8cbd69c029854e9881ddc6e87ae5093",
    "prototype/UI.md": "76c0f6012b016af04d6105fa696a9a0e29dfa53a",
    "domain-modeling/CONTEXT-FORMAT.md": "eaf2a18573f0a2d8c69ed53e29e4d9e21baf81d8",
    "domain-modeling/ADR-FORMAT.md": "da7e78ec1c220cd0aedf7ad36424c9398034f375",
}


def committed_blob(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    return subprocess.check_output(["git", "rev-parse", f"HEAD:{relative}"], cwd=ROOT, text=True).strip().lower()


def main() -> None:
    for relative, expected in EXPECTED.items():
        path = VENDOR / relative
        assert path.is_file(), relative
        assert committed_blob(path) == expected, f"{relative}: committed donor companion drift"

    prototype = (ROOT / ".ai/skills/prototype/SKILL.md").read_text(encoding="utf-8")
    assert "prototype/LOGIC.md" in prototype
    assert "prototype/UI.md" in prototype
    domain = (ROOT / ".ai/skills/domain-modeling/SKILL.md").read_text(encoding="utf-8")
    assert "domain-modeling/CONTEXT-FORMAT.md" in domain
    assert "domain-modeling/ADR-FORMAT.md" in domain

    print("PASS: Wayfinder donor companion-source Git-object integrity and adapted-skill references")


if __name__ == "__main__":
    main()
