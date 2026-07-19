# Agent Operating Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`

## Repository mission

`REPLACE_REPOSITORY_MISSION`

## Required reading

1. this `AGENTS.md`;
2. nearest nested `AGENTS.md`;
3. `CODEBASE_MAP.md`, `README.md`, and repository operating docs;
4. tool adapter such as `CLAUDE.md`;
5. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`;
6. selected `.ai/skills/*/SKILL.md`;
7. `plans/plan-registry.json` and the selected public plan;
8. `docs/governance/harness-doctrine.md` and `.ai/harness/harness-doctrine.policy.json`;
9. current tests, validators, PRs, and Git history.

The inherited harness doctrine requires repository and branch or worktree, PR or sprint, lane, owned and forbidden scope, expected artifacts, and validation order. It also enforces 30-second test-only GNHF wall-clock and iteration limits and a fail-closed DeepSeek standard-or-discounted usage gate.

## Public plan coordination

Material multi-agent, multi-session, multi-wave, or cross-PR work belongs under `plans/` as public machine-readable coordination.

- The plan records mission, owner, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff.
- A branch or pull request transports and reviews implementation; it is not the only durable coordination record.
- Update the plan in the implementation branch when task state, ownership, dependencies, proof, or handoff changes materially.
- Never put credentials, customer data, private hostnames, local paths, provider state, or raw runtime evidence in a public plan.
- A plan never grants merge, deployment, authentication, target-mutation, or destructive-Git authority.

Use `.ai/skills/public-plan-coordination/SKILL.md` and the repository's public-plan validator.

## Entry points

- source: `REPLACE_SOURCE_ROOTS`
- launchers: `REPLACE_LAUNCHERS`
- public plans: `plans/plan-registry.json`
- tests and validators: `REPLACE_VALIDATION_COMMANDS`
- generated artifacts: `REPLACE_ARTIFACT_PATHS`

## Safety boundaries

- forbidden scope: `REPLACE_FORBIDDEN_SCOPE`
- runtime or deployment boundary: `REPLACE_RUNTIME_BOUNDARY`
- secret and personal-data policy: `REPLACE_DATA_POLICY`
- target mutation policy: `REPLACE_TARGET_MUTATION_POLICY`

## Delivery contract

Use isolated branches and worktrees for concurrent writers. Reuse healthy existing tools and directories. Make bounded tracked changes, run repository-native checks, commit, push when authorized, and report exact proof and gaps. A request that claims installation, setup, build, execution, repair, configuration, upgrade, deployment, merge, or release is invalid when it permits acknowledgment or plan substitution instead of the corresponding mutation and proof.
