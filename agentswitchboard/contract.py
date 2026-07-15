"""Request validation, rejection logic, and result building for the AgentSwitchboard invocation contract."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

KNOWN_AGENTS = frozenset({"opencode", "agy", "goose"})
SUPPORTED_PLATFORMS = frozenset({"windows", "linux"})
SUPPORTED_OPERATIONS = frozenset({"inventory", "install-missing", "repair-check", "smoke"})
SUPPORTED_PROFILES = frozenset({"windows-native", "linux-native", "wsl-tmux"})
PLATFORM_PROFILES: dict[str, frozenset[str]] = {
    "windows": frozenset({"windows-native", "wsl-tmux"}),
    "linux": frozenset({"linux-native"}),
}

SECRET_PATTERNS = re.compile(
    r"(token|secret|password|api_key|credential|auth|bearer)",
    re.IGNORECASE,
)

EXIT_SUCCESS = 0
EXIT_ACTION_REQUIRED = 1
EXIT_INVALID_REQUEST = 2
EXIT_UNSUPPORTED_PROFILE = 3
EXIT_INTERNAL_FAILURE = 4


def validate_request(raw: dict[str, Any]) -> list[str]:
    """Validate an invocation request. Returns a list of error messages (empty = valid)."""
    errors: list[str] = []

    # Schema version
    if raw.get("schema_version") != "agentswitchboard-invocation/v1":
        errors.append(f"unsupported schema_version: {raw.get('schema_version')!r}")

    # Execution profile
    profile = raw.get("execution_profile_id", "")
    if not isinstance(profile, str) or profile not in SUPPORTED_PROFILES:
        errors.append(f"unsupported execution_profile_id: {profile!r}")

    # Platform
    platform = raw.get("platform", "")
    if platform not in SUPPORTED_PLATFORMS:
        errors.append(f"unsupported platform: {platform!r}")

    # Profile/platform compatibility
    if isinstance(profile, str) and isinstance(platform, str):
        valid_profiles = PLATFORM_PROFILES.get(platform, frozenset())
        if profile not in valid_profiles:
            errors.append(
                f"execution_profile_id {profile!r} is not compatible with platform {platform!r}"
            )

    # Requested agents
    agents = raw.get("requested_agents", [])
    if not isinstance(agents, list) or len(agents) == 0:
        errors.append("requested_agents must be a non-empty list")
    else:
        seen = set()
        for agent in agents:
            if not isinstance(agent, str):
                errors.append(f"requested_agents item is not a string: {agent!r}")
            elif agent not in KNOWN_AGENTS:
                errors.append(f"unsupported agent: {agent!r}")
            elif agent in seen:
                errors.append(f"duplicate agent in requested_agents: {agent!r}")
            else:
                seen.add(agent)

    # Operation
    operation = raw.get("operation", "")
    if operation not in SUPPORTED_OPERATIONS:
        errors.append(f"unsupported operation: {operation!r}")

    # Fixture mode
    fixture = raw.get("fixture_mode")
    if not isinstance(fixture, bool):
        errors.append("fixture_mode must be a boolean")

    # Evidence output dir - check for machine-local paths
    evd = raw.get("evidence_output_dir")
    if evd is not None:
        if not isinstance(evd, str) or len(evd) == 0:
            errors.append("evidence_output_dir must be a non-empty string if provided")
        else:
            if re.match(r"^[A-Za-z]:[\\/]", evd):
                errors.append(f"evidence_output_dir must not be a Windows absolute path: {evd!r}")
            if evd.startswith("/") or evd.startswith("\\"):
                errors.append(f"evidence_output_dir must not be an absolute path: {evd!r}")

    # Reject unknown fields
    known_fields = {
        "schema_version",
        "execution_profile_id",
        "platform",
        "requested_agents",
        "operation",
        "fixture_mode",
        "evidence_output_dir",
    }
    received = set(raw.keys())
    unknown = received - known_fields
    if unknown:
        errors.append(f"unknown field(s): {', '.join(sorted(unknown))}")

    # Reject secret-like field values anywhere in the request
    raw_str = json.dumps(raw)
    if SECRET_PATTERNS.search(raw_str):
        errors.append("request contains secret-like field values")

    return errors


def build_result(
    request: dict[str, Any],
    agents_data: dict[str, dict[str, Any]],
    overall_status: str,
    exit_code: int,
    fixture_mode: bool,
) -> dict[str, Any]:
    """Build a normalized result dictionary."""
    return {
        "schema_version": "agentswitchboard-result/v1",
        "invocation_request": {
            "schema_version": "agentswitchboard-invocation/v1",
            "execution_profile_id": request.get("execution_profile_id", ""),
            "platform": request.get("platform", ""),
            "requested_agents": request.get("requested_agents", []),
            "operation": request.get("operation", ""),
            "fixture_mode": request.get("fixture_mode", False),
        },
        "overall_status": overall_status,
        "agents": agents_data,
        "exit_code": exit_code,
        "proof_ceiling": {
            "fixture_mode": fixture_mode,
            "real_agent_installation_proven": False,
            "authentication_proven": False,
            "hosted_model_response_proven": False,
            "sysadminsuite_integration_proven": False,
        },
    }


def run_fixture(request: dict[str, Any]) -> dict[str, Any]:
    """Execute fixture-mode detection for requested agents. No network, no real installers."""
    agents = request.get("requested_agents", [])
    operation = request.get("operation", "inventory")
    fixture_mode = request.get("fixture_mode", False)

    agents_data: dict[str, dict[str, Any]] = {}

    for agent in agents:
        if agent == "opencode":
            agents_data[agent] = {
                "installation_state": "present",
                "detected_version": "0.1.0",
                "authentication_readiness": "not_applicable",
                "smoke_status": "passed",
                "action_taken": f"fixture: {operation} completed for opencode",
                "reason_code": "fixture_mode",
            }
        elif agent == "agy":
            agents_data[agent] = {
                "installation_state": "present",
                "detected_version": "1.0.0",
                "authentication_readiness": "not_applicable",
                "smoke_status": "passed",
                "action_taken": f"fixture: {operation} completed for agy",
                "reason_code": "fixture_mode",
            }
        elif agent == "goose":
            agents_data[agent] = {
                "installation_state": "present",
                "detected_version": "0.5.0",
                "authentication_readiness": "not_applicable",
                "smoke_status": "passed",
                "action_taken": f"fixture: {operation} completed for goose",
                "reason_code": "fixture_mode",
            }

    overall = "PASS"
    code = EXIT_SUCCESS

    return build_result(
        request=request,
        agents_data=agents_data,
        overall_status=overall,
        exit_code=code,
        fixture_mode=fixture_mode,
    )
