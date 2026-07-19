#!/usr/bin/env python3
"""Static regression for Windows-to-WSL OpenCode configurator transport."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "tooling" / "wsl" / "Set-OpenCodeFreeDefaults.ps1"
ATTRIBUTES = ROOT / ".gitattributes"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    installer = INSTALLER.read_text(encoding="utf-8")
    attributes = ATTRIBUTES.read_text(encoding="utf-8")

    for token in (
        "function ConvertTo-LfText",
        "$configuratorText = ConvertTo-LfText",
        "$command = ConvertTo-LfText -Text $command",
        "$inspectCommand = ConvertTo-LfText -Text $inspectCommand",
        "$configurator64",
    ):
        require(token in installer, f"missing LF-normalization token: {token}")

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

    print("PASS: OpenCode free-default configurator uses LF-normalized WSL transport")


if __name__ == "__main__":
    main()
