from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tooling" / "profiles" / "windows" / "harness" / "opencode-runtime-resolution"
REPORTER = ROOT / "tooling" / "profiles" / "windows" / "Get-OpenCodeRuntimeResolutionStatus.ps1"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def family(path: str) -> str:
    p = path.replace("/", "\\").lower()
    if "\\agentswitchboard\\bin\\opencode.cmd" in p:
        return "agentswitchboard-wsl-shim"
    if "\\appdata\\roaming\\npm\\opencode." in p:
        return "native-windows-npm"
    if ".opencode\\bin\\opencode" in p or "/.opencode/bin/opencode" in path.lower():
        return "wsl-ubuntu-opencode"
    return "unknown"


def classify(case: dict) -> tuple[str, bool]:
    requested = case.get("requestedSurface", "unknown")
    parent = case.get("parentResolution") or {}
    launch = case.get("effectiveLaunchResolution") or {}
    state = case.get("stateResolution") or {}
    if requested == "unknown" or not case.get("processPathCaptured") or not launch.get("resolvedPath"):
        return "unresolved-runtime-identity", False
    wrapper = launch.get("wrapperKind")
    target_platform = launch.get("targetPlatform", launch.get("runtimePlatform", "unknown"))
    if requested == "native-windows" and (wrapper == "agentswitchboard-wsl-shim" or target_platform == "wsl-ubuntu"):
        return "shim-shadowing-native", False
    if wrapper == "agentswitchboard-wsl-shim" and not launch.get("targetPath"):
        return "unresolved-runtime-identity", False
    parent_platform = parent.get("runtimePlatform", "unknown")
    launch_platform = launch.get("runtimePlatform", "unknown")
    if requested != "wsl-ubuntu" and parent_platform != "unknown" and launch_platform != "unknown" and parent_platform != launch_platform:
        return "parent-child-divergence", False
    state_path = state.get("commandPath")
    if state_path:
        state_family = family(state_path)
        launch_family = family(launch.get("resolvedPath", ""))
        if state_family != "unknown" and launch_family != "unknown" and state_family != launch_family:
            return "state-command-drift", False
    if requested == "native-windows" and target_platform == "windows" and wrapper == "native-package-shim":
        return "native-consistent", True
    if requested == "wsl-ubuntu" and target_platform == "wsl-ubuntu":
        return "declared-wsl-consistent", True
    return "unresolved-runtime-identity", False


def test_required_files() -> None:
    required = [
        HARNESS / "codebase-map.json",
        HARNESS / "runtime-resolution.registry.json",
        HARNESS / "artifact-registry.json",
        HARNESS / "composition.graph.json",
        HARNESS / "workflows" / "runtime-resolution-intake.workflow.json",
        HARNESS / "workflows" / "path-collision-diagnosis.workflow.json",
        HARNESS / "schemas" / "opencode-runtime-resolution.schema.json",
        HARNESS / "fixtures" / "valid-native-windows.fixture.json",
        HARNESS / "fixtures" / "valid-declared-wsl.fixture.json",
        HARNESS / "fixtures" / "invalid-shim-shadowing.fixture.json",
        HARNESS / "fixtures" / "invalid-wsl-missing-target.fixture.json",
        HARNESS / "fixtures" / "invalid-wsl-state-drift.fixture.json",
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
    assert registry["canonicalOwner"] == "EndeavorEverlasting/AgentSwitchboard"
    assert registry["evidenceRules"]["resolvedConfigProvesExecutableIdentity"] is False
    assert registry["evidenceRules"]["parentGetCommandProvesChildIdentity"] is False
    assert registry["evidenceRules"]["exactOperatorOrAgentLaunchChainRequiredForRuntimeProof"] is True
    assert registry["evidenceRules"]["wrapperTargetRequiredWhenWrapperSelected"] is True
    assert registry["repairBoundary"]["harnessMayMutatePath"] is False
    assert registry["repairBoundary"]["harnessMayInstallPackages"] is False
    ids = {item["classificationId"] for item in registry["classifications"]}
    assert ids == {"native-consistent","declared-wsl-consistent","shim-shadowing-native","parent-child-divergence","state-command-drift","unresolved-runtime-identity"}


def test_fixture_classification() -> None:
    fixtures = sorted((HARNESS / "fixtures").glob("*.fixture.json"))
    assert len(fixtures) >= 5
    for path in fixtures:
        case = load(path)
        classification, passed = classify(case)
        assert classification == case["expectedClassification"], (path.name, classification, case["expectedClassification"])
        assert passed is case["expectedPass"], (path.name, passed, case["expectedPass"])


def test_reporter_contract_registration() -> None:
    source = REPORTER.read_text(encoding="utf-8")
    for token in ("agentswitchboard.opencode-runtime-resolution-snapshot.v1","requestedSurface = $RequestedSurface","parentResolution = $parentResolution","effectiveLaunchResolution = $null","processPathCaptured = $processPathCaptured","tracked = $false","git -C $RootPath ls-files --error-unmatch","invalid-wsl-missing-target.fixture.json","invalid-wsl-state-drift.fixture.json"):
        assert token in source, f"reporter contract token missing: {token}"


def test_graph_and_salvage_boundary() -> None:
    graph = load(HARNESS / "composition.graph.json")
    edges = {(edge["from"], edge["to"]) for edge in graph["edges"]}
    route = ["entrypoint.opencode-runtime-status","workflow.opencode-runtime-intake","workflow.opencode-path-collision","artifact.opencode-runtime-classification","report.opencode-runtime-operator","handoff.opencode-runtime"]
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
    tests = [test_required_files,test_registry_semantics,test_fixture_classification,test_reporter_contract_registration,test_graph_and_salvage_boundary]
    for test in tests:
        test()
        print(f"[PASS] {test.__name__}")
    print(f"Result: {len(tests)} passed / 0 failed")


if __name__ == "__main__":
    main()
