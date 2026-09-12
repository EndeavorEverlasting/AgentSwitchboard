# Operational Harness — Human State Report

This is a tracked human-readable snapshot of the repository harness infrastructure. It is a navigation/report artifact, not remote truth; refresh Git/provider evidence before acting on branch or runtime claims.

## Working

- Root governance and 50k orientation exist: `AGENTS.md` and `HARNESS.md`.
- Canonical operational codebase map, workflow registry, artifact registry, validator registry, lifecycle workflow specs, opt-in pre-commit/pre-push helpers, routing skill, status reporter, operator guide, PowerShell validator, Python contract, and hosted Windows/Linux workflow already exist.
- `tooling/harness/operational/harness-components.registry.json` now gives a single tracked inventory across those component classes and requires every registered component to be both present and Git-tracked.
- `scripts/Test-HarnessInfrastructureCompleteness.ps1` and `tests/test_harness_infrastructure_completeness.py` are the repository-level completeness gates for that inventory.
- Post-integration local adoption is now an explicit workflow/skill rather than an implicit assumption.

## Broken / blocked

- No repository-level harness defect is intentionally accepted in this sprint.
- Hosted/static harness proof cannot update or inspect a physical operator workstation checkout by itself.
- A dirty/diverged local checkout may block safe fast-forward adoption; the prescribed response is preservation plus an isolated worktree/proof checkout, not destructive cleanup.

## Missing / unproven

- Whether any particular workstation has fetched/pulled a newly merged integration remains unproved until the post-integration local-adoption workflow runs there (or equivalent direct evidence is supplied).
- Runtime behavior, provider/model behavior, deployment, GUI/TUI effects, and live-target success remain owned by their domain/runtime validators.

## Operator path

1. Read `AGENTS.md`, then `HARNESS.md`.
2. For harness work, read `tooling/harness/operational/harness-components.registry.json` and `.ai/skills/operational-harness-routing/SKILL.md`.
3. Run the completeness gate before committing harness infrastructure.
4. After a merge, use `tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json` before invoking a newly merged local command.

## Proof ceiling

This report and its completeness validators prove tracked repository harness composition and static/hosted contracts. They do not prove that a physical workstation adopted the latest remote commit or that any application/runtime behavior succeeded.
