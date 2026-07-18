# Agent Operating Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`

## Repository mission

`REPLACE_REPOSITORY_MISSION`

## Required reading

1. this `AGENTS.md`;
2. nearest nested `AGENTS.md`;
3. `README.md` and repository operating docs;
4. tool adapter such as `CLAUDE.md`;
5. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`;
6. selected `.ai/skills/*/SKILL.md`;
7. `docs/governance/harness-doctrine.md` and `.ai/harness/harness-doctrine.policy.json`;
8. current plans, tests, validators, PRs, and Git history.

The inherited harness doctrine requires the commit-backed execution loop, repository and branch or worktree, PR or sprint, lane, owned and forbidden scope, expected artifacts, and validation order. It also enforces 30-second test-only GNHF wall-clock and iteration limits and a fail-closed DeepSeek standard-or-discounted usage gate. Task-specific execution rules override generic closeout behavior while remaining subject to higher-priority safety and repository law.

## Entry points

- source: `REPLACE_SOURCE_ROOTS`
- launchers: `REPLACE_LAUNCHERS`
- tests and validators: `REPLACE_VALIDATION_COMMANDS`
- generated artifacts: `REPLACE_ARTIFACT_PATHS`

## Safety boundaries

- forbidden scope: `REPLACE_FORBIDDEN_SCOPE`
- runtime or deployment boundary: `REPLACE_RUNTIME_BOUNDARY`
- secret and personal-data policy: `REPLACE_DATA_POLICY`
- target mutation policy: `REPLACE_TARGET_MUTATION_POLICY`

## Delivery contract

Use isolated branches and worktrees for concurrent writers. Reuse healthy existing tools and directories. Make bounded tracked changes, run repository-native checks, commit, push when authorized, and report exact proof and gaps. A request that claims installation, setup, build, execution, repair, configuration, upgrade, deployment, merge, or release is invalid when it permits acknowledgment or plan substitution instead of the corresponding mutation and proof.
