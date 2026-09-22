#!/usr/bin/env python3
"""Deterministic OpenCode runtime-resolution evidence classifier."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


def _normalized(path: str) -> str:
    return re.sub(r"/+", "/", str(path).replace("\\", "/").strip()).lower()


def family(path: str) -> str:
    p = _normalized(path)
    if re.search(r"/appdata/local/agentswitchboard/bin/opencode\.cmd$", p):
        return "agentswitchboard-wsl-shim"
    if re.search(r"/appdata/roaming/npm/opencode\.(cmd|ps1)$", p):
        return "native-windows-npm"
    if re.search(r"/\.opencode/bin/opencode$", p):
        return "wsl-ubuntu-opencode"
    return "unknown"


def classify(case: dict[str, Any]) -> tuple[str, bool]:
    requested = str(case.get("requestedSurface", "unknown"))
    parent = case.get("parentResolution") or {}
    launch = case.get("effectiveLaunchResolution") or {}
    state = case.get("stateResolution") or {}
    process_path = case.get("processPath")

    if requested == "unknown":
        return "unresolved-runtime-identity", False
    if not parent.get("resolvedPath") or not launch.get("resolvedPath"):
        return "unresolved-runtime-identity", False
    if not case.get("processPathCaptured") or not isinstance(process_path, list) or not any(str(item).strip() for item in process_path):
        return "unresolved-runtime-identity", False

    parent_family = family(parent["resolvedPath"])
    launch_family = family(launch["resolvedPath"])
    if parent_family == "unknown" or launch_family == "unknown":
        return "unresolved-runtime-identity", False

    wrapper = launch.get("wrapperKind")
    target_platform = launch.get("targetPlatform", launch.get("runtimePlatform", "unknown"))
    target_path = launch.get("targetPath")
    target_family = family(target_path) if target_path else "unknown"

    if requested == "native-windows" and (launch_family == "agentswitchboard-wsl-shim" or wrapper == "agentswitchboard-wsl-shim" or target_platform == "wsl-ubuntu"):
        return "shim-shadowing-native", False

    if wrapper == "agentswitchboard-wsl-shim":
        if target_platform != "wsl-ubuntu" or target_family != "wsl-ubuntu-opencode":
            return "unresolved-runtime-identity", False

    if requested != "wsl-ubuntu" and parent_family != launch_family:
        return "parent-child-divergence", False

    state_path = state.get("commandPath")
    if state_path:
        state_family = family(state_path)
        if state_family == "unknown":
            return "unresolved-runtime-identity", False
        if state_family != launch_family:
            return "state-command-drift", False

    if requested == "native-windows":
        if parent_family == launch_family == "native-windows-npm" and wrapper == "native-package-shim" and target_platform == "windows":
            return "native-consistent", True
        return "unresolved-runtime-identity", False

    if requested == "wsl-ubuntu":
        direct_wsl = parent_family == launch_family == "wsl-ubuntu-opencode"
        delegated_wsl = parent_family == launch_family == "agentswitchboard-wsl-shim" and target_family == "wsl-ubuntu-opencode" and target_platform == "wsl-ubuntu"
        if direct_wsl or delegated_wsl:
            return "declared-wsl-consistent", True

    return "unresolved-runtime-identity", False


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify one OpenCode runtime-resolution evidence packet.")
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    case = json.loads(args.evidence.read_text(encoding="utf-8"))
    classification, passed = classify(case)
    print(json.dumps({"classificationId": classification, "pass": passed}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
