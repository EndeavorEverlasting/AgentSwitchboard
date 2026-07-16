#!/usr/bin/env python3
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
POLICY = ROOT / "tooling" / "gnhf" / "model-route-policy.example.json"
ROUTER = ROOT / "tooling" / "gnhf" / "Start-AutoRoutedGnhfSprint.ps1"
INSTALLER = ROOT / "tooling" / "gnhf" / "Install-AgentModelRouter.ps1"
DOC = ROOT / "docs" / "workstation" / "cost-aware-agent-model-routing.md"


def main() -> None:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    assert policy["schemaVersion"] == 1
    assert policy["costOrder"] == ["limited-free", "free", "paid"]
    assert policy["allowPaidFallback"] is True

    routes = policy["routes"]
    ids = [route["id"] for route in routes]
    assert ids[0] == "opencode-zen-deepseek-v4-flash-free"
    assert routes[0]["costClass"] == "limited-free"
    assert routes[0]["model"] == "opencode/deepseek-v4-flash-free"
    assert routes[0]["gnhfCompatibility"] == "runtime-proof-required"

    required = {
        "agy-deepseek-free",
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
    doc_text = DOC.read_text(encoding="utf-8")

    assert "Automatic post-mutation fallback is intentionally disabled" in router_text
    assert "OPENCODE_CONFIG_CONTENT" in router_text
    assert "route-compatibility.json" in router_text
    assert "time-windows" in router_text
    assert "agent-switchboard-auto.cmd" in installer_text
    assert "Preserved customized model route policy" in installer_text
    assert "AGY" in doc_text and "acp:agy acp" in doc_text
    assert "flat" in doc_text.lower() and "pricing" in doc_text.lower()

    combined = "\n".join((router_text, installer_text, doc_text, POLICY.read_text(encoding="utf-8")))
    forbidden = [r"sk-[A-Za-z0-9]", r"api[_-]?key\s*[:=]\s*['\"][^'\"]+", r"git\s+push", r"--push\b"]
    for pattern in forbidden:
        assert re.search(pattern, combined, flags=re.IGNORECASE) is None, pattern

    print("PASS: AgentSwitchboard cost-aware model route policy contracts")


if __name__ == "__main__":
    main()
