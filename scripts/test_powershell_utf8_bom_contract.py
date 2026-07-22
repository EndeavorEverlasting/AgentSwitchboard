#!/usr/bin/env python3
"""Cross-platform UTF-8 BOM contract validator for tracked PowerShell files.

BlacksmithGuild doctrine requires every tracked *.ps1, *.psm1, and *.psd1
file to carry a UTF-8 BOM. This script enforces that contract on the
AgentSwitchboard repository so mixed-execution-domain PowerShell files stay
valid for both Windows PowerShell 5.1 and PowerShell 7.

Exit code 0 when all checked files pass; 1 otherwise.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
UTF8_BOM = b"\xef\xbb\xbf"

# Patterns that should be checked for BOM. Exclude .git, ignored temp paths,
# and non-tracked generated evidence roots.
CHECKED_SUFFIXES = (".ps1", ".psm1", ".psd1")
IGNORED_PREFIXES = (
    ".git",
    "node_modules",
    ".local",
)


def _should_check(path: Path) -> bool:
    relative = path.relative_to(REPO_ROOT).as_posix()
    if relative.startswith(".") and not relative.startswith("./"):
        relative = relative[1:] if relative != "." else ""
    for prefix in IGNORED_PREFIXES:
        if relative.startswith(prefix):
            return False
    if not path.is_file():
        return False
    return path.name.endswith(CHECKED_SUFFIXES)


def _files_to_check() -> list[Path]:
    files: list[Path] = []
    for root, dirs, filenames in os.walk(REPO_ROOT):
        root_path = Path(root)
        # Prune ignored directories early
        dirs[:] = [d for d in dirs if d not in IGNORED_PREFIXES]
        for filename in filenames:
            candidate = root_path / filename
            if _should_check(candidate):
                files.append(candidate)
    return sorted(files)


def main() -> int:
    files = _files_to_check()
    passes: list[str] = []
    failures: list[str] = []

    for path in files:
        raw = path.read_bytes()
        relative = path.relative_to(REPO_ROOT).as_posix()
        if raw.startswith(UTF8_BOM):
            passes.append(relative)
        else:
            failures.append(relative)

    print("POWERShell UTF-8 BOM CONTRACT")
    for name in passes:
        print(f"[PASS] {name}")
    for name in failures:
        print(f"[FAIL] {name}: missing UTF-8 BOM")
    print(f"\nResult: {len(passes)} passed / {len(failures)} failed")

    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
