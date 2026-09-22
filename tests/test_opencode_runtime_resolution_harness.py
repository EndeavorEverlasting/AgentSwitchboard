from __future__ import annotations

import json
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "opencode-runtime-resolution"
REPORTER = ROOT / "tooling" / "profiles" / "windows" / "Get-OpenCodeRuntimeResolutionStatus.ps1"
CLASSIFIER = HARNESS / "classifier.py"
CLASSIFIER_NS = runpy.run_path(str(CLASSIFIER))
family = CLASSIFIER_NS["family"]
classify = CLASSIFIER_NS["classify"]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_required_files() -> None:
    required = [
        HARNESS / "classifier.py",
        HARNESS / "codebase-map.json",
        HARNESS / "runtime-resolution.registry.json",
        HARNESS / "artifact-registry.json",
        HARNESS / "composition.graph.json",
        HARNESS / "workflows" / "runtime-resolution-intake.workflow.json",
        HARNESS / "workflows" / "path-collision-diagnosis.workflow.json",
        HARNESS / "schemas" / "opencode-runtime-resolution.schema.json",
        HARNESS / "operator-report.template.md",
        REPORTER,
        ROOT / "scripts" / "Test-OpenCodeRuntimeResolutionHarness.ps1",
        ROOT / "docs" / "harness" / "opencode-runtime-resolution-harness.md",
        ROOT / ".github" / "workflows" / "opencode-runtime-resolution-harness.yml",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    assert not missing, f"missing harness files: {missing}"


def test_registry_semantics() -> None:
    registry = load(HARNESS / "runtime-resolution.registry.json")
    rules = registry["evidenceRules"]
    assert registry["canonicalOwner"] == "EndeavorEverlasting/AgentSwitchboard"
    assert rules["resolvedConfigProvesExecutableIdentity"] is False
    assert rules["parentGetCommandProvesChildIdentity"] is False
    assert rules["exactOperatorOrAgentLaunchChainRequiredForRuntimeProof"] is True
    assert rules["parentResolutionRequired"] is True
    assert rules["processPathSnapshotRequired"] is True
    assert rules["wrapperTargetRequiredWhenWrapperSelected"] is True
    assert rules["recognizedResolverPathRequiredForPassingClassification"] is True
    assert rules["recognizedStateCommandRequiredWhenStatePresent"] is True
    assert registry["repairBoundary"]["harnessMayMutatePath"] is False
    assert registry["repairBoundary"]["harnessMayInstallPackages"] is False


def test_fixture_classification() -> None:
    fixtures = sorted((HARNESS / "fixtures").glob("*.fixture.json"))
    assert len(fixtures) >= 10
    for path in fixtures:
        case = load(path)
        classification, passed = classify(case)
        assert classification == case["expectedClassification"], (path.name, classification, case["expectedClassification"])
        assert passed is case["expectedPass"], (path.name, passed, case["expectedPass"])


def test_registered_family_matching_is_boundary_safe() -> None:
    assert family(r"C:\\Users\\Example\\AppData\\Local\\AgentSwitchboard\\bin\\opencode.cmd") == "agentswitchboard-wsl-shim"
    assert family(r"C:\\Users\\Example\\AppData\\Local\\AgentSwitchboard\\binary\\opencode.cmd") == "unknown"
    assert family(r"C:\\Users\\Example\\AppData\\Roaming\\npm\\opencode.cmd") == "native-windows-npm"
    assert family(r"C:\\Users\\Example\\AppData\\Roaming\\npm-old\\opencode.cmd") == "unknown"
    assert family("/home/example/.opencode/bin/opencode") == "wsl-ubuntu-opencode"
    assert family("/usr/local/bin/opencode") == "unknown"


def test_reporter_contract_registration() -> None:
    source = REPORTER.read_text(encoding="utf-8")
    for token in ("agentswitchboard.opencode-runtime-resolution-snapshot.v1","requestedSurface = $RequestedSurface","parentResolution = $parentResolution","effectiveLaunchResolution = $null","processPathCaptured = $processPathCaptured","processPath = @($processPathSnapshot)","Test-PathWithinRoot","git -C $RootPath ls-files --error-unmatch"):
        assert token in source, f"reporter contract token missing: {token}"


def test_graph_and_salvage_boundary() -> None:
    graph = load(HARNESS / "composition.graph.json")
    edges = {(edge["from"], edge["to"]) for edge in graph["edges"]}
    route = ["entrypoint.opencode-runtime-status","workflow.opencode-runtime-intake","workflow.opencode-path-collision","classifier.opencode-runtime-resolution","artifact.opencode-runtime-classification","report.opencode-runtime-operator","handoff.opencode-runtime"]
    assert set(route) <= {node["id"] for node in graph["nodes"]}
    for left, right in zip(route, route[1:]):
        assert (left, right) in edges
    codebase = load(HARNESS / "codebase-map.json")
    salvage = codebase["salvage"]
    assert salvage["sourcePullRequest"] == 113
    assert salvage["sourceHead"] == "2ff3d81ab806b54dceccf593cd0f39b2c17e8bc9"
    retired = "\n".join(salvage["disposition"]["retireOrDefer"])
    assert "SKILLS.md" in retired and "TRIGGERS.md" in retired and "pre-commit hook" in retired
    assert "skill" not in codebase["entrypoints"]
    assert "hook" not in codebase["entrypoints"]


def main() -> None:
    tests = [test_required_files,test_registry_semantics,test_fixture_classification,test_registered_family_matching_is_boundary_safe,test_reporter_contract_registration,test_graph_and_salvage_boundary]
    for fn in tests:
        fn()
        print(f"[PASS] {fn.__name__}")
    print(f"Result: {len(tests)} passed / 0 failed")


if __name__ == "__main__":
    main()
