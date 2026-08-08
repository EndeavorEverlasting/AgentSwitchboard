from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = [
    "tooling/profiles/android/harness/termux/manifest.json",
    "tooling/profiles/android/harness/termux/codebase-map.json",
    "tooling/profiles/android/harness/termux/artifact-registry.json",
    "tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json",
    "tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json",
    "tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json",
    "tooling/profiles/android/harness/termux/fixtures/bracketed-paste-corruption.fixture.txt",
    "tooling/profiles/android/harness/termux/operator-report.template.md",
    "tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh",
    ".ai/skills/android-termux-repo-bootstrap/SKILL.md",
    "docs/harness/android-termux-operational-harness.md",
    "scripts/Test-AndroidTermuxHarnessCompleteness.ps1",
    ".github/workflows/android-termux-harness.yml",
]

JSON_FILES = [p for p in REQUIRED if p.endswith(".json")]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    for relative in REQUIRED:
        require((ROOT / relative).is_file(), f"required file missing: {relative}")

    parsed = {}
    for relative in JSON_FILES:
        parsed[relative] = json.loads((ROOT / relative).read_text(encoding="utf-8"))

    manifest = parsed["tooling/profiles/android/harness/termux/manifest.json"]
    require(manifest["schema"] == "agentswitchboard.android-termux-harness.v1", "unexpected manifest schema")
    require(manifest["profile"] == "android", "manifest profile must be android")
    require(manifest["environment"] == "termux", "manifest environment must be termux")
    require(manifest["status"] == "contract-only", "harness must not overclaim Android runtime")
    require("does not claim an Android profile launcher exists" in manifest["proofCeiling"], "manifest proof ceiling must block launcher overclaim")

    component_paths = []
    for value in manifest["components"].values():
        component_paths.extend(value if isinstance(value, list) else [value])
    for relative in component_paths:
        require((ROOT / relative).is_file(), f"manifest component missing: {relative}")

    artifacts = parsed["tooling/profiles/android/harness/termux/artifact-registry.json"]
    require(artifacts["tracked"] is False, "generated Android evidence must remain untracked")
    ids = {a["artifactId"] for a in artifacts["artifacts"]}
    for expected in {"termux-bootstrap-log", "tmux-persistence-proof", "terminal-input-boundary-report", "github-auth-status", "repo-clone-proof", "android-termux-harness-validation", "android-termux-operator-report"}:
        require(expected in ids, f"artifact not registered: {expected}")
    forbidden = " ".join(artifacts["forbiddenContent"]).lower()
    for token in ("oauth device codes", "access tokens", "private ssh keys", "recovery codes"):
        require(token in forbidden, f"artifact redaction contract missing: {token}")

    expected_workflows = {
        "tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json": "android-termux-task-intake",
        "tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json": "android-termux-validate-terminal-boundary",
        "tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json": "android-termux-handle-input-boundary-failure",
    }
    for relative, workflow_id in expected_workflows.items():
        workflow = parsed[relative]
        require(workflow["schema"] == "agentswitchboard.android-termux-workflow.v1", f"unexpected workflow schema: {relative}")
        require(workflow["workflowId"] == workflow_id, f"unexpected workflow id: {relative}")
        require(len(workflow["steps"]) >= 5, f"workflow is incomplete: {relative}")
        require(bool(workflow.get("proofCeiling")), f"workflow proof ceiling missing: {relative}")

    fixture = (ROOT / "tooling/profiles/android/harness/termux/fixtures/bracketed-paste-corruption.fixture.txt").read_text(encoding="utf-8")
    require("[200~gh auth login" in fixture, "bracketed-paste failure fixture missing exact signature")
    require("[200~gh: command not found" in fixture, "command-not-found fixture missing exact signature")

    skill = (ROOT / ".ai/skills/android-termux-repo-bootstrap/SKILL.md").read_text(encoding="utf-8")
    for heading in ("id: android-termux-repo-bootstrap", "status: experimental", "## Trigger", "## Inputs", "## Procedure", "## Outputs", "## Deterministic validation", "## Forbidden scope", "## Stop and escalate"):
        require(heading in skill, f"skill contract token missing: {heading}")

    deployable_text = "\n".join((ROOT / p).read_text(encoding="utf-8") for p in REQUIRED if (ROOT / p).suffix in {".md", ".json", ".sh", ".txt"})
    for forbidden_literal in ("BEGIN OPENSSH PRIVATE KEY", "gh auth token", "--force", "git clean -fdx"):
        require(forbidden_literal not in deployable_text, f"unsafe literal embedded in harness: {forbidden_literal}")

    print(f"ANDROID TERMUX HARNESS: PASS ({len(REQUIRED)} required files, {len(JSON_FILES)} JSON contracts)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
