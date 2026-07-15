#!/usr/bin/env python3
"""Contract tests for the AgentSwitchboard invocation and result schemas."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
EXPECTED = FIXTURES / "results"
REQUESTS = FIXTURES / "requests"
SCHEMA_DIR = ROOT / "schemas"

sys.path.insert(0, str(ROOT))


def read(path: Path) -> str:
    assert path.is_file(), f"missing file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def load(path: Path) -> dict:
    return json.loads(read(path))


def load_contract():
    """Load the contract module."""
    import agentswitchboard.contract as c
    return c


def test_schemas_are_valid_json():
    for schema in SCHEMA_DIR.rglob("*.json"):
        load(schema)


def test_valid_request_accepted():
    c = load_contract()
    req = load(REQUESTS / "valid-inventory-windows-fixture.json")
    errors = c.validate_request(req)
    assert errors == [], f"expected no errors, got: {errors}"


def test_valid_install_missing_accepted():
    c = load_contract()
    req = load(REQUESTS / "valid-install-missing-linux-fixture.json")
    errors = c.validate_request(req)
    assert errors == [], f"expected no errors, got: {errors}"


def test_valid_smoke_wsl_accepted():
    c = load_contract()
    req = load(REQUESTS / "valid-smoke-wsl-fixture.json")
    errors = c.validate_request(req)
    assert errors == [], f"expected no errors, got: {errors}"


def test_reject_unknown_field():
    c = load_contract()
    req = load(REQUESTS / "reject-unknown-field.json")
    errors = c.validate_request(req)
    assert any("unknown" in e.lower() for e in errors), f"expected unknown field error, got: {errors}"


def test_reject_macos_platform():
    c = load_contract()
    req = load(REQUESTS / "reject-macos-platform.json")
    errors = c.validate_request(req)
    assert any("unsupported platform" in e.lower() for e in errors), f"expected unsupported platform error, got: {errors}"


def test_reject_unsupported_agent():
    c = load_contract()
    req = load(REQUESTS / "reject-unsupported-agent.json")
    errors = c.validate_request(req)
    assert any("unsupported agent" in e.lower() for e in errors), f"expected unsupported agent error, got: {errors}"


def test_reject_secret_values():
    c = load_contract()
    req = load(REQUESTS / "reject-secret-token-value.json")
    errors = c.validate_request(req)
    assert any("secret" in e.lower() for e in errors), f"expected secret-like values error, got: {errors}"


def test_reject_duplicate_agent():
    c = load_contract()
    req = load(REQUESTS / "reject-duplicate-agent.json")
    errors = c.validate_request(req)
    assert any("duplicate" in e.lower() for e in errors), f"expected duplicate agent error, got: {errors}"


def test_reject_wrong_profile_platform():
    c = load_contract()
    req = load(REQUESTS / "reject-wrong-profile-platform.json")
    errors = c.validate_request(req)
    assert any("not compatible" in e.lower() for e in errors), f"expected compatibility error, got: {errors}"


def test_reject_absolute_evidence_path():
    c = load_contract()
    req = load(REQUESTS / "reject-absolute-evidence-path.json")
    errors = c.validate_request(req)
    assert any("absolute path" in e.lower() for e in errors), f"expected absolute path error, got: {errors}"


def test_reject_empty_agents():
    c = load_contract()
    req = load(REQUESTS / "reject-empty-agents.json")
    errors = c.validate_request(req)
    assert len(errors) > 0, "expected errors for empty agents list"


def test_reject_bad_schema_version():
    c = load_contract()
    req = load(REQUESTS / "reject-bad-schema-version.json")
    errors = c.validate_request(req)
    assert any("schema_version" in e.lower() for e in errors), f"expected schema_version error, got: {errors}"


def test_result_round_trip():
    """Verify fixture execution produces the expected result structure."""
    c = load_contract()
    req = load(REQUESTS / "valid-inventory-windows-fixture.json")
    result = c.run_fixture(req)
    assert result["schema_version"] == "agentswitchboard-result/v1"
    assert result["overall_status"] == "PASS"
    assert result["exit_code"] == 0
    assert result["proof_ceiling"]["fixture_mode"] is True
    assert result["proof_ceiling"]["real_agent_installation_proven"] is False
    assert len(result["agents"]) == 3


def test_result_matches_expected_fixture():
    c = load_contract()
    req = load(REQUESTS / "valid-inventory-windows-fixture.json")
    expected = load(EXPECTED / "expected-inventory-windows.json")
    actual = c.run_fixture(req)
    assert actual == expected, f"result mismatch\n expected: {json.dumps(expected, indent=2)}\n actual: {json.dumps(actual, indent=2)}"


def test_no_network_in_fixture_mode():
    """Verify fixture results always have fixture_mode: true and no live claims."""
    c = load_contract()
    for req_file in REQUESTS.rglob("*.json"):
        req = load(req_file)
        if req.get("fixture_mode", False):
            result = c.run_fixture(req)
            assert result["proof_ceiling"]["fixture_mode"] is True
            assert result["proof_ceiling"]["real_agent_installation_proven"] is False
            assert result["proof_ceiling"]["authentication_proven"] is False
            assert result["proof_ceiling"]["hosted_model_response_proven"] is False
            assert result["proof_ceiling"]["sysadminsuite_integration_proven"] is False


def test_supported_profiles_cli():
    """Verify the --supported-profiles CLI flag."""
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--supported-profiles"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "windows-native" in result.stdout
    assert "linux-native" in result.stdout
    assert "wsl-tmux" in result.stdout


def test_supported_operations_cli():
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--supported-operations"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    for op in ("inventory", "install-missing", "repair-check", "smoke"):
        assert op in result.stdout


def test_supported_agents_cli():
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--supported-agents"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    for agent in ("opencode", "agy", "goose"):
        assert agent in result.stdout


def test_version_cli():
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--version"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "agentswitchboard" in result.stdout


def test_validate_cli():
    valid = REQUESTS / "valid-inventory-windows-fixture.json"
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--validate"],
        input=valid.read_text(encoding="utf-8"),
        capture_output=True, text=True,
    )
    assert "PASSED" in result.stdout


def test_validate_rejects_macos():
    bad = REQUESTS / "reject-macos-platform.json"
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", "--validate"],
        input=bad.read_text(encoding="utf-8"),
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "FAILED" in result.stdout or result.returncode == 2


def test_cli_execute_fixture():
    req_file = REQUESTS / "valid-inventory-windows-fixture.json"
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", str(req_file)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    parsed = json.loads(result.stdout)
    assert parsed["schema_version"] == "agentswitchboard-result/v1"
    assert parsed["overall_status"] == "PASS"


def test_cli_execute_rejects_invalid():
    req_file = REQUESTS / "reject-unknown-field.json"
    result = subprocess.run(
        [sys.executable, "-m", "agentswitchboard", str(req_file)],
        capture_output=True, text=True,
    )
    assert result.returncode == 2


def test_proof_ceiling_always_false():
    c = load_contract()
    for req_file in REQUESTS.rglob("*.json"):
        req = load(req_file)
        if not req.get("fixture_mode", False):
            continue
        result = c.run_fixture(req)
        p = result["proof_ceiling"]
        assert p["real_agent_installation_proven"] is False
        assert p["authentication_proven"] is False
        assert p["hosted_model_response_proven"] is False
        assert p["sysadminsuite_integration_proven"] is False


def main():
    test_names = [n for n in dir() if n.startswith("test_")]
    passed = 0
    failed = 0
    for name in sorted(test_names):
        fn = globals()[name]
        try:
            fn()
            print(f"  PASS  {name}")
            passed += 1
        except Exception as e:
            print(f"  FAIL  {name}: {e}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
