from __future__ import annotations

import copy
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = Path("tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json")
SCHEMA_PATH = Path("tooling/harness/operational/contributions/cross-repository-contribution.schema.json")
PUBLIC_PLAN_SCHEMA = Path("plans/schemas/public-plan.schema.json")
TEMPLATE_PUBLIC_PLAN_SCHEMA = Path("templates/repository-agent-contract/plans/schemas/public-plan.schema.json")
SKILL_PATH = Path(".ai/skills/public-plan-coordination/SKILL.md")
WAYFINDER_SKILL_PATH = Path(".ai/skills/wayfinder/SKILL.md")
TEMPLATE_SKILL_PATH = Path("templates/repository-agent-contract/.ai/skills/public-plan-coordination/SKILL.md")

EXPECTED_DONOR_BLOBS = {
    "skills/engineering/wayfinder/SKILL.md": "e4984ed327e12ba65303f4b5de2eb75c01e99c16",
    "skills/engineering/research/SKILL.md": "0ba594a07f306479baa67104381f48e209ab6aae",
    "skills/engineering/prototype/SKILL.md": "094571156140f5993cce8557dc31383c82817f3e",
    "skills/productivity/grilling/SKILL.md": "95bd01ee9049a7e08120d54af9cd6ceeef282335",
    "skills/engineering/domain-modeling/SKILL.md": "d0f7e1a5ccb06a7184056ff9af02b67bc77f9dda",
    "skills/engineering/to-spec/SKILL.md": "3fd64959895b7eb095a13d797e1c7544f1f08c8f",
    "skills/engineering/to-tickets/SKILL.md": "96deac51d4391a3f691478d48f85f43261516c08",
    "skills/engineering/setup-matt-pocock-skills/issue-tracker-github.md": "bf595e2470597fcd316d8b316ad861f05ed630be",
    "skills/engineering/setup-matt-pocock-skills/issue-tracker-local.md": "fbda5e04217fcdb73b513720f513abbe0b3014ed",
    "LICENSE": "f1dd2c09108dde1a5f56097cee8461b3ea834499",
}


def load_json(path: Path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def validator_for(schema: dict):
    from jsonschema import Draft202012Validator, FormatChecker

    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def assert_rejected(validator, instance: dict) -> None:
    from jsonschema import ValidationError

    try:
        validator.validate(instance)
    except ValidationError:
        return
    raise AssertionError("expected Draft 2020-12 schema rejection")


def main() -> None:
    manifest = load_json(MANIFEST_PATH)
    contribution_schema = load_json(SCHEMA_PATH)
    public_plan_schema = load_json(PUBLIC_PLAN_SCHEMA)
    template_plan_schema = load_json(TEMPLATE_PUBLIC_PLAN_SCHEMA)

    contribution_validator = validator_for(contribution_schema)
    public_plan_validator = validator_for(public_plan_schema)
    validator_for(template_plan_schema)

    contribution_validator.validate(manifest)
    malformed_manifest = copy.deepcopy(manifest)
    malformed_manifest["unexpectedAuthority"] = True
    assert_rejected(contribution_validator, malformed_manifest)
    malformed_manifest = copy.deepcopy(manifest)
    del malformed_manifest["donor"]["commit"]
    assert_rejected(contribution_validator, malformed_manifest)

    assert manifest["schema"] == "agentswitchboard.cross-repository-contribution.v1"
    assert manifest["contributionId"] == "mattpocock.wayfinder.asb-adaptation.v2"
    assert manifest["status"] == "adopted"

    donor = manifest["donor"]
    assert donor["repository"] == "mattpocock/skills"
    assert donor["commit"] == "84fdeffd12f2ee307994d1eb6feb48173b6e0502"
    assert re.fullmatch(r"[0-9a-f]{40}", donor["commit"])
    assert donor["license"] == {"spdx": "MIT", "path": "LICENSE"}
    authoritative = {item["path"]: item["blobSha"] for item in donor["authoritativePaths"]}
    assert authoritative == EXPECTED_DONOR_BLOBS

    consumer = manifest["consumer"]
    assert consumer["repository"] == "EndeavorEverlasting/AgentSwitchboard"
    assert consumer["canonicalOwner"] == ".ai/skills/wayfinder/SKILL.md"
    for path in consumer["files"]:
        assert (ROOT / path).is_file(), path

    classifications = {item["classification"] for item in manifest["classifications"]}
    assert {
        "portable-harness",
        "reusable-skill",
        "shared-schema-or-evidence-packet",
        "adapter",
        "reference-only-doctrine",
        "domain-specific-rejected",
    } <= classifications
    rejected = [item for item in manifest["classifications"] if item["classification"] == "domain-specific-rejected"]
    assert rejected and all(item["disposition"] == "reject" for item in rejected)

    compatibility = manifest["compatibility"]
    assert compatibility == {
        "consumerContract": "agentswitchboard.wayfinder.v1+public-plan-mirror-1",
        "minimumSkillVersion": "1.2.0",
        "changeKind": "additive",
        "staleReferencePolicy": "pin-until-reviewed",
        "autoAdvanceDonor": False,
    }

    mode = public_plan_schema["properties"]["coordinationMode"]
    assert mode["additionalProperties"] is False
    assert mode["properties"]["kind"]["const"] == "decision-frontier"
    assert mode["properties"]["executionAllowed"]["const"] is False
    assert mode["properties"]["sourceContribution"]["const"] == MANIFEST_PATH.as_posix()
    tracker = mode["properties"]["tracker"]
    assert tracker["properties"]["decisionAuthority"]["const"] == "tracker-child-tickets"
    spec = mode["properties"]["spec"]
    assert "temporary-until-implementation" in json.dumps(spec)
    assert {
        "kind", "destination", "tracker", "notYetSpecified", "outOfScope",
        "spec", "executionAllowed", "sourceContribution"
    } <= set(mode["required"])

    # The repository-family template does not silently adopt Wayfinder. It remains
    # the generic public-plan contract until a child repository explicitly accepts
    # the contribution and installs its own Wayfinder skills/validators.
    assert "coordinationMode" not in template_plan_schema["properties"]
    template_skill = (ROOT / TEMPLATE_SKILL_PATH).read_text(encoding="utf-8")
    assert "decision-frontier" not in template_skill
    assert "wayfinder" not in template_skill.lower()

    registry = load_json(Path("plans/plan-registry.json"))
    registered_plans = []
    for entry in registry["plans"]:
        plan = load_json(Path(entry["path"]))
        public_plan_validator.validate(plan)
        registered_plans.append(plan)

    mirror = copy.deepcopy(registered_plans[0])
    mirror["coordinationMode"] = {
        "kind": "decision-frontier",
        "destination": "Reach a specification whose required decisions are resolved in tracker child tickets.",
        "tracker": {
            "provider": "github",
            "mapRef": "#200",
            "mapUrl": "https://github.com/EndeavorEverlasting/AgentSwitchboard/issues/200",
            "decisionAuthority": "tracker-child-tickets",
        },
        "notYetSpecified": ["A future decision whose exact question depends on the current frontier."],
        "outOfScope": ["Destination implementation before the route is clear."],
        "spec": {"status": "not-ready", "lifecycle": "temporary-until-implementation", "ref": None},
        "executionAllowed": False,
        "sourceContribution": MANIFEST_PATH.as_posix(),
    }
    public_plan_validator.validate(mirror)

    unsafe = copy.deepcopy(mirror)
    unsafe["coordinationMode"]["executionAllowed"] = True
    assert_rejected(public_plan_validator, unsafe)
    duplicate_authority = copy.deepcopy(mirror)
    duplicate_authority["coordinationMode"]["frontier"] = []
    assert_rejected(public_plan_validator, duplicate_authority)
    wrong_authority = copy.deepcopy(mirror)
    wrong_authority["coordinationMode"]["tracker"]["decisionAuthority"] = "public-plan-tasks"
    assert_rejected(public_plan_validator, wrong_authority)
    permanent_spec = copy.deepcopy(mirror)
    permanent_spec["coordinationMode"]["spec"]["lifecycle"] = "permanent"
    assert_rejected(public_plan_validator, permanent_spec)

    public_plan_skill = (ROOT / SKILL_PATH).read_text(encoding="utf-8")
    for token in (
        "version: 1.2.0",
        "repository coordination mirror",
        "tracker-child-tickets",
        "tasks[] remain repository coordination tasks",
        "pin-until-reviewed",
    ):
        assert token in public_plan_skill, token

    wayfinder_skill = (ROOT / WAYFINDER_SKILL_PATH).read_text(encoding="utf-8")
    for token in ("Ticket gates", "Chart mode", "Work mode", "to-spec", "to-tickets"):
        assert token in wayfinder_skill, token

    plans_readme = (ROOT / "plans/README.md").read_text(encoding="utf-8")
    assert "tracker map is the canonical" in plans_readme
    assert "tasks[] remain repository coordination tasks" in plans_readme
    assert "temporary-until-implementation" in plans_readme

    assert manifest["proofCeiling"]
    assert any("Do not allow an agent to satisfy prototype or grilling HITL gates" in item for item in manifest["mustNotCopyOrReimplement"])
    assert any("Do not treat public-plan tasks as a second copy" in item for item in manifest["mustNotCopyOrReimplement"])

    print("PASS: Wayfinder contribution keeps tracker decisions, public-plan coordination, temporary specs, and implementation tickets in distinct authorities")


if __name__ == "__main__":
    main()
