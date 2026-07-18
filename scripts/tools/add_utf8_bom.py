#!/usr/bin/env python3
"""Add a UTF-8 BOM to tracked PowerShell files that are missing it.

Usage from repository root:
    python3 scripts/tools/add_utf8_bom.py --fix

Without --fix the script only reports files that would change.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
UTF8_BOM = b"\xef\xbb\xbf"
CHECKED_SUFFIXES = (".ps1", ".psm1", ".psd1")
IGNORED_PREFIXES = (
    ".git",
    "node_modules",
    ".local",
)


def _should_check(path: Path) -> bool:
    relative = path.relative_to(REPO_ROOT).as_posix()
    for prefix in IGNORED_PREFIXES:
        if relative.startswith(prefix):
            return False
    if not path.is_file():
        return False
    return path.name.endswith(CHECKED_SUFFIXES)


def _files_to_check() -> list[Path]:
    files: list[Path] = []
    for root, dirs, filenames in sorted(REPO_ROOT.walk()):
        dirs[:] = [d for d in dirs if d not in IGNORED_PREFIXES]
        for filename in filenames:
            candidate = root / filename
            if _should_check(candidate):
                files.append(candidate)
    return sorted(files)


def main() -> int:
    parser = argparse.ArgumentParser(description="Add UTF-8 BOM to tracked PowerShell files.")
    parser.add_argument("--fix", action="store_true", help="apply BOM where missing")
    args = parser.parse_args()

    changed = 0
    for path in _files_to_check():
        raw = path.read_bytes()
        if raw.startswith(UTF8_BOM):
            continue
        changed += 1
        relative = path.relative_to(REPO_ROOT).as_posix()
        print(f"{'FIX' if args.fix else 'WOULD_FIX'}: {relative}")
        if args.fix:
            path.write_bytes(UTF8_BOM + raw)

    if changed:
        print(f"\n{changed} file(s) missing BOM")
        return 0 if args.fix else 1
    print("All checked PowerShell files already have a UTF-8 BOM.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
