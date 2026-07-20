from __future__ import annotations

import base64
import gzip
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

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
    assert "Richard" not in rendered
    assert "rperez@example.com" not in rendered
    assert "sk-live-super-secret" not in rendered
    assert "192.168.1.44" not in rendered
    assert len(json.dumps(packet, separators=(",", ":"))) <= 6000


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
        report = report_path.read_text(encoding="utf-8")
        assert "# APP OUTPUT CONTEXT" in report
        assert "Proof ceiling:" in report


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
    test_json_input_and_execution_surface_boundary()
    test_plain_and_bundled_registry_load_identically()
    test_no_match_is_honest()
    test_cli_writes_json_and_english_report()
    test_required_harness_files_and_registration()
    print("PASS: AgentSwitchboard app-output context engine")
