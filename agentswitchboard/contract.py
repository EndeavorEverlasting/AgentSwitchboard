"""Multi-domain AgentSwitchboard request, resolution, and result contracts."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any, Mapping

KNOWN_AGENTS = ("opencode", "agy", "goose")
SUPPORTED_PLATFORMS = frozenset({"windows", "linux"})
SUPPORTED_DOMAINS = frozenset({"windows-native", "windows-wsl", "linux-native"})
SUPPORTED_OPERATIONS = frozenset({"inventory", "install-missing", "repair-check", "smoke"})
DOMAIN_PLATFORM = {"windows-native": "windows", "windows-wsl": "windows", "linux-native": "linux"}
FIXTURE_SCENARIOS = frozenset({"native", "bridge", "missing", "authentication-required", "malformed"})

EXIT_SUCCESS = 0
EXIT_ACTION_REQUIRED = 1
EXIT_INVALID_REQUEST = 2
EXIT_UNSUPPORTED_PROFILE = 3
EXIT_INTERNAL_FAILURE = 4

SECRET_PATTERNS = re.compile(r"token|secret|password|api[_-]?key|credential|bearer", re.I)
KNOWN_FIELDS = {
    "schema_version", "platform", "execution_domain", "distro", "requested_agents", "operation",
    "install_missing_only", "native_preference", "bridge_permission", "posture", "fixture_scenario",
    "evidence_output_dir",
}


def validate_request(raw: Any) -> list[str]:
    """Return validation errors without raising for malformed top-level JSON values."""
    if not isinstance(raw, Mapping):
        return ["request must be a JSON object"]
    errors: list[str] = []
    if raw.get("schema_version") != "agentswitchboard-invocation/v2":
        errors.append(f"unsupported schema_version: {raw.get('schema_version')!r}")
    platform = raw.get("platform")
    domain = raw.get("execution_domain")
    if platform == "macos":
        if domain != "unsupported": errors.append("macos requires execution_domain 'unsupported'")
    elif platform not in SUPPORTED_PLATFORMS:
        errors.append(f"unsupported platform: {platform!r}")
    elif domain not in SUPPORTED_DOMAINS:
        errors.append(f"unsupported execution_domain: {domain!r}")
    elif DOMAIN_PLATFORM[domain] != platform:
        errors.append(f"execution_domain {domain!r} is not compatible with platform {platform!r}")

    distro = raw.get("distro")
    if domain == "windows-wsl":
        if not isinstance(distro, str) or not distro.strip(): errors.append("windows-wsl requires a distro")
        elif distro.lower() in {"docker-desktop", "docker-desktop-data"}: errors.append("Docker Desktop is not a development distro")
    elif distro is not None:
        errors.append("distro is valid only for windows-wsl")

    agents = raw.get("requested_agents")
    if not isinstance(agents, list) or not agents:
        errors.append("requested_agents must be a non-empty list")
    else:
        if len(agents) != len(set(item for item in agents if isinstance(item, str))): errors.append("requested_agents contains duplicates")
        for agent in agents:
            if agent not in KNOWN_AGENTS: errors.append(f"unsupported agent: {agent!r}")
    if raw.get("operation") not in SUPPORTED_OPERATIONS: errors.append(f"unsupported operation: {raw.get('operation')!r}")
    if raw.get("install_missing_only") is not True: errors.append("install_missing_only must be true")
    if not isinstance(raw.get("native_preference"), bool): errors.append("native_preference must be boolean")
    if not isinstance(raw.get("bridge_permission"), bool): errors.append("bridge_permission must be boolean")
    if raw.get("posture") not in {"fixture", "live"}: errors.append("posture must be fixture or live")
    scenario = raw.get("fixture_scenario")
    if raw.get("posture") == "fixture" and scenario not in FIXTURE_SCENARIOS: errors.append("fixture posture requires a known fixture_scenario")
    if raw.get("posture") == "live" and scenario is not None: errors.append("fixture_scenario is not valid for live posture")
    evidence = raw.get("evidence_output_dir")
    if evidence is not None:
        if not isinstance(evidence, str) or not evidence: errors.append("evidence_output_dir must be a non-empty string")
        elif re.match(r"^[A-Za-z]:[\\/]", evidence) or evidence.startswith(("/", "\\", "~")): errors.append("evidence_output_dir must be portable and relative")
    unknown = set(raw) - KNOWN_FIELDS
    if unknown: errors.append(f"unknown field(s): {', '.join(sorted(unknown))}")
    if SECRET_PATTERNS.search(json.dumps(raw)): errors.append("request contains secret-like material")
    return errors


def _agent_result(agent: str, domain: str, backend: str, scenario: str = "native") -> dict[str, Any]:
    wrapper = "canonical" if backend in {"native", "bridge"} else "missing"
    path_class = "managed-wrapper" if backend in {"native", "bridge"} else "missing"
    auth = "required" if scenario == "authentication-required" else "unknown"
    smoke = "not-attempted"
    action_required = backend == "missing" or auth == "required"
    return {
        "installation_domain": domain,
        "selected_backend": backend,
        "wrapper_type": wrapper,
        "command_path_class": path_class,
        "version": "fixture" if backend != "missing" else None,
        "authentication_readiness": auth,
        "smoke_status": smoke,
        "action_required": action_required,
        "reason_code": "authentication-required" if auth == "required" else ("agent-missing" if backend == "missing" else "fixture-resolution"),
        "commands": {"canonical": agent, "native": f"{agent}_native", "bridge": f"{agent}_win"},
    }


def build_result(request: Mapping[str, Any], agents: dict[str, dict[str, Any]], status: str, exit_code: int) -> dict[str, Any]:
    return {
        "schema_version": "agentswitchboard-result/v2",
        "request": {
            key: request.get(key) for key in (
                "schema_version", "platform", "execution_domain", "distro", "requested_agents", "operation",
                "install_missing_only", "native_preference", "bridge_permission", "posture"
            )
        },
        "overall_status": status,
        "agents": agents,
        "exit_code": exit_code,
        "proof": {
            "fixture": request.get("posture") == "fixture",
            "installation_observed": False,
            "authentication_observed": False,
            "provider_response_observed": False,
            "interactive_behavior_observed": False,
        },
    }


def run_fixture(request: Mapping[str, Any]) -> dict[str, Any]:
    scenario = str(request.get("fixture_scenario", "native"))
    if scenario == "malformed":
        return {"schema_version": "agentswitchboard-result/malformed-fixture"}
    agents: dict[str, dict[str, Any]] = {}
    for agent in request.get("requested_agents", []):
        if scenario in {"missing", "authentication-required"}: backend = "missing" if scenario == "missing" else "native"
        elif scenario == "bridge": backend = "bridge" if request.get("bridge_permission") else "missing"
        else: backend = "native"
        agents[agent] = _agent_result(agent, str(request.get("execution_domain")), backend, scenario)
    action = any(item["action_required"] for item in agents.values())
    status = "action-required" if action else "pass"
    return build_result(request, agents, status, EXIT_ACTION_REQUIRED if action else EXIT_SUCCESS)


def _find_managed_command(agent: str) -> Path | None:
    candidate = Path.home() / ".local" / "agent-switchboard" / "bin" / agent
    return candidate if candidate.is_file() and os.access(candidate, os.X_OK) else None


def _probe(command: Path) -> tuple[bool, str | None]:
    try:
        result = subprocess.run([str(command), "--agent-switchboard-probe"], capture_output=True, text=True, timeout=10, check=False)
        version = (result.stdout or result.stderr).strip().splitlines()
        return result.returncode == 0, version[0] if version else None
    except (OSError, subprocess.TimeoutExpired):
        return False, None


def _completed_probe(result: subprocess.CompletedProcess[str]) -> tuple[bool, str | None]:
    lines = (result.stdout or result.stderr or "").strip().splitlines()
    return result.returncode == 0, lines[0] if lines else None


def _run_wsl(distro: str, arguments: list[str], timeout: int = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["wsl.exe", "-d", distro, "--exec", *arguments],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def _windows_path_to_wsl(distro: str, path: Path) -> str:
    resolved = str(path.resolve())
    matched = re.match(r"^([A-Za-z]):[\\/](.*)$", resolved)
    if not matched:
        raise RuntimeError(f"could not convert host path for WSL distro {distro}")
    drive, remainder = matched.groups()
    return f"/mnt/{drive.lower()}/{remainder.replace(chr(92), '/')}"


def _probe_wsl_wrapper(distro: str, wrapper: str, allow_bridge: bool = False) -> tuple[bool, str | None]:
    bridge = "export AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=1; " if allow_bridge else ""
    command = (
        'export PATH="$HOME/.local/agent-switchboard/bin:$PATH"; '
        f'{bridge}exec "$HOME/.local/agent-switchboard/bin/{wrapper}" --agent-switchboard-probe'
    )
    return _completed_probe(_run_wsl(distro, ["bash", "-lc", command]))


def _run_live_windows_wsl(request: Mapping[str, Any], repo_root: Path) -> dict[str, Any]:
    distro = str(request["distro"])
    installed = False
    if request.get("operation") == "install-missing":
        installer = repo_root / "tooling" / "wsl" / "scripts" / "install-agent-wrappers.sh"
        installer_wsl = _windows_path_to_wsl(distro, installer)
        install_command = 'exec "$1" --destination "$HOME/.local/agent-switchboard/bin" --execution-domain windows-wsl'
        if request.get("bridge_permission"):
            install_command += " --allow-windows-bridge"
        completed = _run_wsl(
            distro,
            ["bash", "-lc", install_command, "_", installer_wsl],
            timeout=30,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr.strip() or "WSL wrapper installation failed")
        installed = True

    agents: dict[str, dict[str, Any]] = {}
    for agent in request.get("requested_agents", []):
        native_ok, _ = _probe_wsl_wrapper(distro, f"{agent}_native")
        bridge_ok = False
        if not native_ok and request.get("bridge_permission"):
            bridge_ok, _ = _probe_wsl_wrapper(distro, f"{agent}_win")
        backend = "native" if native_ok else "bridge" if bridge_ok else "missing"
        canonical_ok, version = (False, None)
        if backend != "missing":
            canonical_ok, version = _probe_wsl_wrapper(distro, agent, allow_bridge=backend == "bridge")
        result = _agent_result(agent, "windows-wsl", backend if canonical_ok else "missing")
        result.update(
            version=version,
            smoke_status="command-probe-passed" if canonical_ok else "command-probe-failed",
            action_required=not canonical_ok,
            reason_code="command-probe-passed" if canonical_ok else "command-probe-failed",
        )
        agents[agent] = result
    action = any(item["action_required"] for item in agents.values())
    result = build_result(request, agents, "action-required" if action else "pass", EXIT_ACTION_REQUIRED if action else EXIT_SUCCESS)
    result["proof"]["installation_observed"] = installed
    return result


def run_live(request: Mapping[str, Any], repo_root: Path) -> dict[str, Any]:
    if request.get("execution_domain") == "windows-wsl":
        return _run_live_windows_wsl(request, repo_root)
    destination = Path.home() / ".local" / "agent-switchboard" / "bin"
    if request.get("operation") == "install-missing":
        installer = repo_root / "tooling" / "wsl" / "scripts" / "install-agent-wrappers.sh"
        subprocess.run(["bash", str(installer), "--destination", str(destination)], check=True, timeout=30)
    agents: dict[str, dict[str, Any]] = {}
    for agent in request.get("requested_agents", []):
        managed = _find_managed_command(agent)
        if managed:
            ok, version = _probe(managed)
            backend = "native" if ok else ("bridge" if request.get("bridge_permission") and shutil.which(f"{agent}_win") else "missing")
            result = _agent_result(agent, str(request.get("execution_domain")), backend)
            result.update(version=version, smoke_status="command-probe-passed" if ok else "command-probe-failed", action_required=not ok, reason_code="command-probe-passed" if ok else "command-probe-failed")
        else:
            result = _agent_result(agent, str(request.get("execution_domain")), "missing")
        agents[agent] = result
    action = any(item["action_required"] for item in agents.values())
    return build_result(request, agents, "action-required" if action else "pass", EXIT_ACTION_REQUIRED if action else EXIT_SUCCESS)
