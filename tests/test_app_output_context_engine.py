from __future__ import annotations

import base64
import gzip
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "tooling" / "context" / "Contextualize-AppOutput.py"
FIXTURE_ROOT = ROOT / ".ai" / "harness" / "fixtures" / "app-output-context"
REGISTRY = FIXTURE_ROOT / "prompt-registry.fixture.json"
FAILURE_LOG = FIXTURE_ROOT / "failing-app.log"


def load_engine():
    spec = importlib.util.spec_from_file_location("app_output_context", ENGINE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_registry() -> dict:
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def test_redacts_and_ranks_failure_without_raw_output() -> None:
    engine = load_engine()
    raw = FAILURE_LOG.read_text(encoding="utf-8")
    packet = engine.contextualize(
        raw,
        load_registry(),
        source_app="fixture-app",
        surface="regular_ai_prompt",
        top=3,
        max_packet_chars=6000,
    )
    rendered = json.dumps(packet)
    assert packet["schema"] == "agentswitchboard.app-output-context/v1"
    assert packet["source"]["rawOutputStored"] is False
    assert packet["context"]["highestSeverity"] in {"error", "blocked"}
    assert packet["promptKit"]["candidates"][0]["promptId"] == "P01"
    assert "FixtureUser" not in rendered
    assert "fixture.user@example.invalid" not in rendered
    assert "10.20.30.40" not in rendered
    assert engine.redact("token=fixture-value") == "token=<redacted>"
    compact = engine.compact_packet(packet)
    assert len(compact) <= 6000
    assert packet["packetBounds"]["finalChars"] == len(compact)
    assert packet["packetBounds"]["maxPacketChars"] == 6000


def test_source_app_requires_a_public_non_sensitive_slug() -> None:
    engine = load_engine()
    assert engine.normalize_source_app("fixture-app") == "fixture-app"
    for unsafe in (
        "LPW003ASI173",
        "fixture.user@example.invalid",
        "10.20.30.40",
        r"C:\Users\FixtureUser",
        "token=fixture-value",
        "private_host",
    ):
        try:
            engine.normalize_source_app(unsafe)
        except ValueError:
            pass
        else:
            raise AssertionError(f"unsafe source label was accepted: {unsafe}")


def test_packet_limit_is_enforced_or_rejected() -> None:
    engine = load_engine()
    raw = "\n".join(
        f"failed validation timeout exception record {index} with additional repeated diagnostic text"
        for index in range(200)
    )
    packet = engine.contextualize(
        raw,
        load_registry(),
        source_app="fixture-app",
        surface="regular_ai_prompt",
        top=5,
        max_packet_chars=1800,
    )
    compact = engine.compact_packet(packet)
    assert len(compact) <= 1800
    assert packet["packetBounds"]["truncated"] is True
    assert packet["packetBounds"]["initialChars"] > packet["packetBounds"]["finalChars"]
    assert packet["packetBounds"]["finalChars"] == len(compact)

    try:
        engine.contextualize(
            raw,
            load_registry(),
            source_app="fixture-app",
            surface="regular_ai_prompt",
            max_packet_chars=100,
        )
    except ValueError as exc:
        assert "at least 512" in str(exc)
    else:
        raise AssertionError("an impossible packet-size request was accepted")


def test_json_input_and_execution_surface_boundary() -> None:
    engine = load_engine()
    raw = json.dumps({"status": "failed", "error": "schema validation mismatch"})
    regular = engine.contextualize(
        raw, load_registry(), source_app="json-app", surface="regular_ai_prompt"
    )
    gnhf = engine.contextualize(
        raw, load_registry(), source_app="json-app", surface="gnhf_launch_artifact"
    )
    assert regular["source"]["format"] == "json"
    assert all(item["executionSurface"] == "regular_ai_prompt" for item in regular["promptKit"]["candidates"])
    assert all(item["executionSurface"] == "gnhf_launch_artifact" for item in gnhf["promptKit"]["candidates"])
    assert regular["promptKit"]["crossSurfaceFallbackAllowed"] is False


def test_plain_and_bundled_registry_load_identically() -> None:
    engine = load_engine()
    with tempfile.TemporaryDirectory() as temp:
        bundle = Path(temp) / "prompt-registry.fixture.json.gz.b64"
        payload = gzip.compress(REGISTRY.read_bytes())
        bundle.write_text(base64.b64encode(payload).decode("ascii"), encoding="ascii")
        assert engine.load_registry(REGISTRY) == engine.load_registry(bundle)


def test_no_match_is_honest() -> None:
    engine = load_engine()
    packet = engine.contextualize(
        "heartbeat=12345 nominal", load_registry(), source_app="quiet-app", surface="regular_ai_prompt"
    )
    assert packet["promptKit"]["candidates"] == []
    assert packet["instructionPacket"]["suggestedPromptIds"] == []
    assert "No prompt-kit match" in packet["instructionPacket"]["routing"]


def test_cli_writes_json_and_english_report() -> None:
    with tempfile.TemporaryDirectory() as temp:
        output_root = Path(temp) / "out"
        result = subprocess.run(
            [
                sys.executable,
                str(ENGINE),
                "--input", str(FAILURE_LOG),
                "--prompt-registry", str(REGISTRY),
                "--source-app", "fixture-app",
                "--execution-surface", "regular_ai_prompt",
                "--output-root", str(output_root),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr
        json_path = output_root / "app-output-context.json"
        report_path = output_root / "app-output-context.md"
        assert json_path.is_file()
        assert report_path.is_file()
        packet = json.loads(json_path.read_text(encoding="utf-8"))
        assert packet["promptKit"]["candidates"][0]["promptId"] == "P01"
        assert len(json_path.read_text(encoding="utf-8").rstrip("\n")) <= packet["packetBounds"]["maxPacketChars"]
        report = report_path.read_text(encoding="utf-8")
        assert "# APP OUTPUT CONTEXT" in report
        assert "Packet characters:" in report
        assert "Packet truncated:" in report
        assert "Proof ceiling:" in report


def test_cli_rejects_output_root_inside_repository_before_writing() -> None:
    forbidden_output = ROOT / "__app_output_context_forbidden__"
    assert not forbidden_output.exists()
    result = subprocess.run(
        [
            sys.executable,
            str(ENGINE),
            "--input", str(FAILURE_LOG),
            "--prompt-registry", str(REGISTRY),
            "--source-app", "fixture-app",
            "--execution-surface", "regular_ai_prompt",
            "--output-root", str(forbidden_output),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 2
    assert "outside the repository checkout" in result.stderr
    assert not forbidden_output.exists()


def test_required_harness_files_and_registration() -> None:
    required = [
        "Contextualize-AppOutput.cmd",
        "tooling/context/Contextualize-AppOutput.py",
        "scripts/Test-AppOutputContextEngine.ps1",
        ".ai/harness/schemas/app-output-context.schema.json",
        ".ai/harness/workflows/app-output-contextualization.workflow.json",
        ".ai/skills/app-output-contextualization/SKILL.md",
        "docs/harness/app-output-context-engine.md",
    ]
    for relative in required:
        assert (ROOT / relative).is_file(), relative
    assert "app-output-contextualization" in (ROOT / "SKILLS.md").read_text(encoding="utf-8")
    assert "app.output-context-request" in (ROOT / "TRIGGERS.md").read_text(encoding="utf-8")
    assert "app.output.contextualize" in (ROOT / "CAPABILITIES.md").read_text(encoding="utf-8")
    graph = json.loads((ROOT / ".ai/harness/app-composition.graph.json").read_text(encoding="utf-8"))
    node_ids = {node["id"] for node in graph["nodes"]}
    assert "validator.app-output-context" in node_ids
    assert "workflow.app-output-context" in node_ids


if __name__ == "__main__":
    test_redacts_and_ranks_failure_without_raw_output()
    test_source_app_requires_a_public_non_sensitive_slug()
    test_packet_limit_is_enforced_or_rejected()
    test_json_input_and_execution_surface_boundary()
    test_plain_and_bundled_registry_load_identically()
    test_no_match_is_honest()
    test_cli_writes_json_and_english_report()
    test_cli_rejects_output_root_inside_repository_before_writing()
    test_required_harness_files_and_registration()
    print("PASS: AgentSwitchboard app-output context engine")
