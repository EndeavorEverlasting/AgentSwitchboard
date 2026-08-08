from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = Path("tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json")
SCHEMA_PATH = Path("tooling/harness/operational/contributions/cross-repository-contribution.schema.json")
PUBLIC_PLAN_SCHEMA = Path("plans/schemas/public-plan.schema.json")
TEMPLATE_PUBLIC_PLAN_SCHEMA = Path("templates/repository-agent-contract/plans/schemas/public-plan.schema.json")
SKILL_PATH = Path(".ai/skills/public-plan-coordination/SKILL.md")
TEMPLATE_SKILL_PATH = Path("templates/repository-agent-contract/.ai/skills/public-plan-coordination/SKILL.md")


def load_json(path: Path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def main() -> None:
    manifest = load_json(MANIFEST_PATH)
    contribution_schema = load_json(SCHEMA_PATH)
    public_plan_schema = load_json(PUBLIC_PLAN_SCHEMA)
    template_plan_schema = load_json(TEMPLATE_PUBLIC_PLAN_SCHEMA)

    assert manifest["schema"] == "agentswitchboard.cross-repository-contribution.v1"
    assert contribution_schema["additionalProperties"] is False
    assert manifest["status"] == "adopted"

    donor = manifest["donor"]
    assert donor["repository"] == "mattpocock/skills"
    assert donor["commit"] == "84fdeffd12f2ee307994d1eb6feb48173b6e0502"
    assert re.fullmatch(r"[0-9a-f]{40}", donor["commit"])
    assert donor["license"] == {"spdx": "MIT", "path": "LICENSE"}

    authoritative = {item["path"]: item["blobSha"] for item in donor["authoritativePaths"]}
    assert authoritative == {
        "skills/engineering/wayfinder/SKILL.md": "e4984ed327e12ba65303f4b5de2eb75c01e99c16",
        "skills/engineering/wayfinder/agents/openai.yaml": "b37544751e0570f9df8de6c02aef238de8c3e1e0",
        "LICENSE": "f1dd2c09108dde1a5f56097cee8461b3ea834499",
    }

    consumer = manifest["consumer"]
    assert consumer["repository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert consumer["canonicalOwner"] == ".ai/skills/public-plan-coordination/SKILL.md"
    for path in consumer["files"]:
        assert (ROOT / path).is_file(), path

    classifications = {item["classification"] for item in manifest["classifications"]}
    for expected in {
        "portable-harness",
        "reusable-skill",
        "adapter",
        "reference-only-doctrine",
        "domain-specific-rejected",
    }:
        assert expected in classifications, expected

    rejected = [item for item in manifest["classifications"] if item["classification"] == "domain-specific-rejected"]
    assert rejected and all(item["disposition"] == "reject" for item in rejected)

    compatibility = manifest["compatibility"]
    assert compatibility == {
        "consumerContract": "agentswitchboard.public-plan.v1+decision-frontier-1",
        "minimumSkillVersion": "1.1.0",
        "changeKind": "additive",
        "staleReferencePolicy": "pin-until-reviewed",
        "autoAdvanceDonor": False,
    }

    mode = public_plan_schema["properties"]["coordinationMode"]
    assert mode["additionalProperties"] is False
    assert mode["properties"]["kind"]["const"] == "decision-frontier"
    assert mode["properties"]["executionAllowed"]["const"] is False
    assert mode["properties"]["sourceContribution"]["const"] == MANIFEST_PATH.as_posix()
    assert {"kind", "destination", "notYetSpecified", "outOfScope", "executionAllowed", "sourceContribution"} <= set(mode["required"])

    template_mode = template_plan_schema["properties"]["coordinationMode"]
    assert template_mode["properties"]["kind"]["const"] == "decision-frontier"
    assert template_mode["properties"]["executionAllowed"]["const"] is False

    registry = load_json(Path("plans/plan-registry.json"))
    for entry in registry["plans"]:
        plan = load_json(Path(entry["path"]))
        # Backward compatibility: all pre-extension plans remain valid without coordinationMode.
        assert "coordinationMode" not in plan or plan["coordinationMode"]["kind"] == "decision-frontier"

    skill = (ROOT / SKILL_PATH).read_text(encoding="utf-8")
    for token in (
        "version: 1.1.0",
        "## Decision-frontier mode",
        "Destination first",
        "Decision tasks, not build slices",
        "Frontier is derived, not stored twice",
        "Fog remains coarse",
        "executionAllowed",
        "pin-until-reviewed",
    ):
        assert token in skill, token

    template_skill = (ROOT / TEMPLATE_SKILL_PATH).read_text(encoding="utf-8")
    for token in ("decision-frontier", "derive the frontier", "executionAllowed"):
        assert token in template_skill, token

    plans_readme = (ROOT / "plans/README.md").read_text(encoding="utf-8")
    assert "decision-frontier" in plans_readme
    assert "additive extension" in plans_readme
    assert "not a runtime dependency" in plans_readme

    assert manifest["proofCeiling"]
    assert manifest["mustNotCopyOrReimplement"]
    assert any("Do not copy the donor Wayfinder skill wholesale" in item for item in manifest["mustNotCopyOrReimplement"])

    print("PASS: Wayfinder insight is pinned and adapted into the existing public-plan authority without duplicate runtime ownership")


if __name__ == "__main__":
    main()
