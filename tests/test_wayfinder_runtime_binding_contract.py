from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def main() -> None:
    resolver = read("tooling/harness/wayfinder/Resolve-WayfinderPython.ps1")
    harness = read("scripts/Test-WayfinderHarness.ps1")
    contribution = read("scripts/Test-WayfinderPublicPlanContribution.ps1")
    binding_test = read("scripts/Test-WayfinderPythonBinding.ps1")
    workflow = read(".github/workflows/wayfinder-public-plan-contribution.yml")
    manifest = read("tooling/harness/wayfinder/manifest.json")

    for token in (
        "explicit-parameter",
        "ASB_WAYFINDER_PYTHON",
        "VIRTUAL_ENV",
        "repository-.venv",
        "Unable to resolve a usable Python 3 interpreter",
    ):
        assert token in resolver, token

    for script_name, script in (
        ("Test-WayfinderHarness.ps1", harness),
        ("Test-WayfinderPublicPlanContribution.ps1", contribution),
    ):
        assert "[string]$PythonPath" in script, script_name
        assert "Resolve-WayfinderPython" in script, script_name
        assert "Get-Command python -ErrorAction SilentlyContinue" not in script, script_name

    assert "invalid explicit PythonPath silently fell back" in binding_test
    assert "Test-WayfinderPythonBinding.ps1" in workflow
    assert "-PythonPath $py" in workflow
    assert "runtimeBinding" in manifest
    assert "Resolve-WayfinderPython.ps1" in manifest

    print("PASS: Wayfinder runtime-binding static contract")


if __name__ == "__main__":
    main()
