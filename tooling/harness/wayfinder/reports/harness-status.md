# Wayfinder Harness Status

Status baseline: build commit `128c63241393e0884c42a81055e89f9677c0faf8` on `feat/public-plan-decision-frontier-wayfinder-20260808` / PR #94.

## Working

- Scoped Wayfinder codebase map, workflow spec, artifact registry, validator registry, optional pre-commit helper, runtime-binding skill, operator-report template, and completeness validator are tracked.
- Cross-shell Python binding is deterministic: explicit `-PythonPath` wins; `ASB_WAYFINDER_PYTHON`, active venv, repository `.venv`, and PATH are ordered fallbacks; invalid explicit bindings fail closed.
- The Windows failure where `jsonschema` was installed into an isolated venv but nested PowerShell selected a different global `python` is covered by dedicated regression tests.
- Windows path short-name/junction/redirect normalization is treated as informational after a successful interpreter probe and canonical `sys.executable` resolution.
- Donor prototype `LOGIC.md` / `UI.md` and domain-modeling `CONTEXT-FORMAT.md` / `ADR-FORMAT.md` are pinned and checked by committed Git object identity.
- The public-plan contribution validator normalizes Markdown presentation before asserting `tasks[]` semantics, removing the hosted Windows false failure caused by backticks.
- Wayfinder contribution/harness workflow passed on both Windows and Ubuntu at the build commit, including runtime binding, completeness, companion-source integrity, Wayfinder Python/PowerShell, contribution Python/PowerShell, existing public-plan contracts, agent-documentation contract, operational-harness contract, and diff hygiene.
- The separate aggregate Operational harness workflow passed both Linux and Windows at the build commit.
- Public plan/startup readiness and Agent documentation hosted workflows passed at the build commit.

## Broken

- No known harness-contract failure remains at the recorded build commit.

## Missing / higher proof gates

- The user's physical Windows workstation has not yet rerun the repaired exact-head harness after this commit; hosted Windows proves the contract but does not substitute for that field reproof.
- Live GitHub Wayfinder sub-issue/dependency/assignee permissions, actual tracker mutation, human HITL participation, research quality, prototype usefulness, destination implementation, merge/deployment, and operator acceptance remain outside this harness proof ceiling.

## Canonical next proof

Run an isolated exact-head Windows worktree from PR #94, create a sibling venv, install the pinned validator dependency into that exact interpreter, and pass the same `-PythonPath` through runtime-binding, completeness, Wayfinder, contribution, public-plan, agent-documentation, operational-harness, and diff-hygiene checks. Resolve and print the canonical tracked status/report artifacts from `tooling/harness/wayfinder/artifact-registry.json`.

## Proof ceiling

This report records repository/hosted harness proof only. It does not elevate static or hosted validation into physical-workstation, live tracker, HITL, provider, deployment, or destination-runtime proof.
