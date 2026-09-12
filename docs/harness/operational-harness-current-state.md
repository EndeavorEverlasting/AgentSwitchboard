# Operational Harness — Human State Report

This is a tracked human-readable snapshot of the repository harness infrastructure. It is a navigation/report artifact, not remote truth; refresh Git/provider evidence before acting on branch or runtime claims.

## Working

- Root governance and 50k orientation exist: `AGENTS.md` and `HARNESS.md`.
- Canonical operational codebase map, workflow registry, artifact registry, validator registry, lifecycle workflow specs, opt-in pre-commit/pre-push helpers, routing skill, status reporter, operator guide, PowerShell validator, Python contract, and hosted Windows/Linux workflow exist.
- `tooling/harness/operational/harness-components.registry.json` is the tracked inventory across those component classes and requires every registered component to be present and Git-tracked.
- `scripts/Test-HarnessInfrastructureCompleteness.ps1` and `tests/test_harness_infrastructure_completeness.py` are the repository-level completeness gates for that inventory.
- Canonical path proof is now a default action precondition for local repository-backed work. The seam reuses the machine/profile path owner instead of inventing a second resolver.
- Four path proof states remain independent: remote default branch containment, canonical development checkout current, production/use path current, and real operator entrypoint observation.
- Post-integration local adoption delegates to the canonical path seam instead of maintaining a separate path doctrine.

## Broken / blocked

- No repository-level harness defect is intentionally accepted in this sprint.
- Draft PR #149 owns deeper Windows path-role/candidate/launcher enforcement. This P01 seam must not duplicate that P92-style repair.
- Hosted/static harness proof cannot update or inspect a physical operator workstation checkout by itself.
- A dirty/diverged local checkout may block safe fast-forward adoption; preserve it and use the approved isolated worktree/proof path rather than destructive cleanup.

## Missing / unproven

- Whether any particular workstation has fetched/pulled a newly merged integration remains unproved until the canonical path workflow runs there (or equivalent direct evidence is supplied).
- A current canonical development checkout does not prove a separate production/use path or real operator entrypoint unless those states are observed.
- Runtime behavior, provider/model behavior, deployment, GUI/TUI effects, and live-target success remain owned by their domain/runtime validators.

## Operator path

1. Read `AGENTS.md`, then `HARNESS.md`.
2. For harness work, read `tooling/harness/operational/harness-components.registry.json` and `.ai/skills/operational-harness-routing/SKILL.md`.
3. Before almost every local repository-backed action, apply `tooling/harness/operational/canonical-path.contract.json` through `.ai/skills/canonical-path-proof/SKILL.md`.
4. Resolve machine/profile paths from the registered owner, refresh remote truth, and prove the local checkout/use-path state before invoking the requested validator/build/launcher.
5. Run the completeness gate before committing harness infrastructure.
6. After a merge, use the post-integration local-adoption workflow; it specializes the same canonical path seam rather than skipping directly to the new command.

## Proof ceiling

This report and its completeness validators prove tracked repository harness composition, canonical path contracts, and static/hosted rules. They do not prove that a physical workstation adopted the latest remote commit, that a production/use path is current, or that any real operator entrypoint/application/runtime behavior succeeded.
