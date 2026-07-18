from __future__ import annotations

import base64
import gzip
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KIT_ROOT = ROOT / ".ai" / "prompt-kits" / "v38"
REGISTRY = KIT_ROOT / "prompt-registry.v1.json.gz.b64"
SOURCE = KIT_ROOT / "source.json"
SELECTOR = ROOT / "tooling" / "prompts" / "Select-AgentSwitchboardPrompt.ps1"
CMD = ROOT / "Select-AgentSwitchboardPrompt.cmd"
SKILL = ROOT / ".ai" / "skills" / "prompt-kit-selection" / "SKILL.md"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load() -> tuple[dict, dict]:
    payload = gzip.decompress(base64.b64decode(REGISTRY.read_text(encoding="ascii"))).decode("utf-8")
    return json.loads(payload), json.loads(SOURCE.read_text(encoding="utf-8"))


def test_snapshot_provenance_and_integrity() -> None:
    registry, source = load()
    assert source["sourceRepository"] == "EndeavorEverlasting/web-excel-repair-triage"
    assert source["sourceCommit"] == "98bf5c6580bcf167f030324dca45c367f80d0a7b"
    assert source["sourcePullRequest"].endswith("/pull/87")
    assert source["sourceWorkbookSha256"] == "a9fc45b05669afc94e154f53759a723a5bf5827862fb1e38194926cc8ab3ef5a"
    assert source["snapshotSha256"] == sha256_bytes(REGISTRY.read_bytes())
    assert registry["schemaVersion"] == "ai-harness-prompt-registry/v1"
    assert registry["kitVersion"] == "v38"


def test_prompt_ids_hashes_variables_and_surfaces() -> None:
    registry, _ = load()
    prompts = registry["prompts"]
    assert len(prompts) == 45
    assert [prompt["id"] for prompt in prompts] == [f"P{number:02d}" for number in range(45)]
    variables = {record["name"] for record in registry["variables"]}
    by_id = {prompt["id"]: prompt for prompt in prompts}
    for index, prompt in enumerate(prompts):
        assert prompt["sequence"] == index
        assert prompt["textSha256"] == sha256_bytes(prompt["text"].encode("utf-8"))
        assert set(prompt["requiredVariables"]) <= variables
        assert sorted(set(re.findall(r"\bxyz_[a-z0-9_]+\b", prompt["text"]))) == prompt["requiredVariables"]
    assert by_id["P02"]["executionSurface"] == "regular_ai_prompt"
    assert by_id["P07"]["executionSurface"] == "regular_ai_prompt"
    assert by_id["P26"]["executionSurface"] == "gnhf_launch_artifact"
    assert by_id["P37"]["executionSurface"] == "gnhf_launch_artifact"
    assert by_id["P44"]["executionSurface"] == "gnhf_launch_artifact"


def test_consumer_surface_is_offline_and_fail_closed() -> None:
    selector = SELECTOR.read_text(encoding="utf-8")
    cmd = CMD.read_text(encoding="ascii")
    skill = SKILL.read_text(encoding="utf-8")
    for token in (
        "List",
        "Search",
        "Show",
        "Render",
        "regular_ai_prompt",
        "gnhf_launch_artifact",
        "snapshot hash mismatch",
        "requiredVariables",
    ):
        assert token in selector
    assert "Refusing to cross the regular-AI/GNHF artifact boundary" in selector
    assert "Get-FileHash" in selector and "SHA256" in selector
    assert "pwsh -NoLogo -NoProfile" in cmd
    assert "id: prompt-kit-selection" in skill
    assert "No network dependency" in skill
    assert "Selection does not authorize execution" in skill
    combined = selector + cmd + skill
    assert "drive.google.com" not in combined.lower()
    assert "Invoke-WebRequest" not in selector
    assert "git clone" not in selector.lower()


if __name__ == "__main__":
    test_snapshot_provenance_and_integrity()
    test_prompt_ids_hashes_variables_and_surfaces()
    test_consumer_surface_is_offline_and_fail_closed()
    print("PASS: AgentSwitchboard V38 prompt registry snapshot")
