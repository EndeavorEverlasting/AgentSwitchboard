#!/usr/bin/env python3
"""Normalize supported GitHub origin transports to owner/repository."""
from __future__ import annotations

import re
import sys


def normalize_origin(raw: str) -> str:
    value = raw.strip().rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    value = value.rstrip("/")

    patterns = (
        r"^https?://(?:[^/@]+@)?github\.com/(.+)$",
        r"^git://github\.com/(.+)$",
        r"^ssh://git@github\.com/(.+)$",
        r"^git@github\.com:(.+)$",
    )
    for pattern in patterns:
        match = re.match(pattern, value, flags=re.IGNORECASE)
        if match:
            value = match.group(1)
            break

    value = value.rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    return value.rstrip("/")


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in {"-h", "--help"}:
        stream = sys.stdout if len(argv) == 2 else sys.stderr
        print("Usage: Normalize-FirstMateOrigin.py <git-origin-url>", file=stream)
        return 0 if len(argv) == 2 else 64

    result = normalize_origin(argv[1])
    if not result:
        print("[FAIL] origin normalized to an empty value", file=sys.stderr)
        return 2
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
