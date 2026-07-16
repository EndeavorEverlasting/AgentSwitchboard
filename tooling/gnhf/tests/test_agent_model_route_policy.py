#!/usr/bin/env python3
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
POLICY = ROOT / "tooling" / "gnhf" / "model-route-policy.example.json"
ROUTER = ROOT / "tooling" / "gnhf" / "Start-AutoRoutedGnhfSprint.ps1"
INSTALLER = ROOT / "tooling" / "gnhf" / "Install-AgentModelRouter.ps1"
BRIDGE = ROOT / "tooling" / "gnhf" / "Invoke-AgyPiBridge.ps1"
DOC = ROOT / "docs" / "workstation" / "cost-aware-agent-model-routing.md"


def main() -> None:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    assert policy["schemaVersion"] == 2
    assert policy["selectionMode"] == "quota-preserving"
    assert policy["costOrder"] == ["natural-free", "limited-free", "free", "paid"]
    assert policy["allowPaidFallback"] is True
    assert policy["fallbackPolicy"]["allowedClassifications"] == ["quota-exhausted"]
    assert policy["fallbackPolicy"]["requireNoMutation"] is True

    routes = policy["routes"]
    ids = [route["id"] for route in routes]
    assert ids[0] == "agy-natural-free"
    assert routes[0]["costClass"] == "natural-free"
    assert routes[0]["integration"] == "agy-pi-shim"
    assert routes[0]["agentSpec"] == "pi"
    assert routes[0]["modelMode"] == "agy-default"
    assert "model" not in routes[0]
    assert routes[0]["fallbackOn"] == ["quota-exhausted"]

    assert ids[1] == "opencode-zen-deepseek-v4-flash-free"
    assert routes[1]["costClass"] == "limited-free"
    assert routes[1]["model"] == "opencode/deepseek-v4-flash-free"
    assert routes[1]["gnhfCompatibility"] == "runtime-proof-required"

    required = {
        "gemini-cli-free",
        "goose-free-provider",
        "deepseek-v4-flash-paid",
        "codex-chatgpt-or-openai",
        "claude-code",
        "github-copilot-cli",
        "augment-code",
    }
    assert required.issubset(ids)

    pricing = policy["pricingPolicies"]["deepseek-api"]
    assert pricing["mode"] == "flat"
    assert pricing["windowsUtc"] == []
    assert pricing["source"] == "https://api-docs.deepseek.com/quick_start/pricing/"

    router_text = ROUTER.read_text(encoding="utf-8")
    installer_text = INSTALLER.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")
    doc_text = DOC.read_text(encoding="utf-8")

    assert "AGY quota is exhausted and no mutation was observed" in router_text
    assert "Test-NoMutationAfterFailure" in router_text
    assert "AGENTSWITCHBOARD_AGY_STATUS_PATH" in router_text
    assert "OPENCODE_CONFIG_CONTENT" in router_text
    assert "route-compatibility.json" in router_text
    assert "time-windows" in router_text
    assert "agent-switchboard-auto.cmd" in installer_text
    assert "agy-pi-bridge" in installer_text
    assert "Preserved customized model route policy" in installer_text
    assert "quota-exhausted" in bridge_text
    assert "individual\\s+quota" in bridge_text
    assert "quota\\s*(is\\s*)?(reached|exhausted|exceeded)" in bridge_text
    assert "--print" in bridge_text and "accept-edits" in bridge_text
    assert "AGY" in doc_text and "Pi-compatible" in doc_text
    assert "acp:agy acp" not in doc_text
    assert "permanently" in doc_text.lower() and "model" in doc_text.lower()
    assert "flat" in doc_text.lower() and "pricing" in doc_text.lower()

    combined = "\n".join(
        (
            router_text,
            installer_text,
            bridge_text,
            doc_text,
            POLICY.read_text(encoding="utf-8"),
        )
    )
    forbidden = [
        r"sk-[A-Za-z0-9]",
        r"api[_-]?key\s*[:=]\s*['\"][^'\"]+",
        r"git\s+push",
        r"--push\b",
        r"acp:agy\s+acp",
    ]
    for pattern in forbidden:
        assert re.search(pattern, combined, flags=re.IGNORECASE) is None, pattern

    print("PASS: AgentSwitchboard quota-preserving agent model route contracts")


if __name__ == "__main__":
    main()
