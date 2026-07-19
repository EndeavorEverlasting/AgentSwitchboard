#!/usr/bin/env python3
"""Static regression for Windows-to-WSL OpenCode configurator transport."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "tooling" / "wsl" / "Set-OpenCodeFreeDefaults.ps1"
MANIFEST = ROOT / "tooling" / "wsl" / "tmux-gnhf-workstation.example.json"
ATTRIBUTES = ROOT / ".gitattributes"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    installer = INSTALLER.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    attributes = ATTRIBUTES.read_text(encoding="utf-8")

    lf_tokens = (
        "function ConvertTo-LfText",
        "$configuratorText = ConvertTo-LfText",
        "$command = ConvertTo-LfText -Text $command",
        "$inspectCommand = ConvertTo-LfText -Text $inspectCommand",
        "$configurator64",
    )
    for token in lf_tokens:
        require(token in installer, f"missing LF-normalization token: {token}")

    dependency_tokens = (
        "command -v jq",
        "autoInstallDependencies",
        "apt-get update",
        "apt-get install",
        "Installing WSL dependency through apt: jq",
        "Missing WSL dependency: jq",
    )
    for token in dependency_tokens:
        require(token in installer, f"missing jq dependency token: {token}")

    require(
        manifest["opencode"]["autoInstallDependencies"] is True,
        "example manifest must authorize dependency installation",
    )
    require(
        "Convert-WindowsPathToWsl -WindowsPath $configurator" not in installer,
        "installer must not execute the Windows-mounted shell script directly",
    )
    require(
        "configuratorWsl" not in installer,
        "installer must stage the normalized script inside WSL",
    )
    require(
        "*.sh text eol=lf" in attributes,
        "repository must force LF for shell scripts in Windows worktrees",
    )

    print("PASS: OpenCode free-default transport and jq dependency bootstrap")


if __name__ == "__main__":
    main()
