# Agent Operating Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`

## Repository mission

`REPLACE_REPOSITORY_MISSION`

## Required reading

1. this `AGENTS.md` and nearest nested `AGENTS.md`;
2. `CODEBASE_MAP.md`, `README.md`, and repository operating docs;
3. tool adapter such as `CLAUDE.md`;
4. `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`;
5. selected `.ai/skills/*/SKILL.md`;
6. `plans/plan-registry.json` and the selected public plan;
7. `docs/governance/harness-doctrine.md` and `.ai/harness/harness-doctrine.policy.json`;
8. `docs/governance/runtime-event-contract.md` and `.ai/harness/runtime-event-contract.policy.json` when event composition is in scope;
9. current tests, validators, PRs, and Git history.

The inherited harness doctrine requires repository and branch or worktree, PR or sprint, lane, owned and forbidden scope, expected artifacts, and validation order. It also enforces action commitment, bounded test-only GNHF execution, fail-closed DeepSeek eligibility, and registered runtime event composition.

## Public plan coordination

Material multi-agent, multi-session, multi-wave, or cross-PR work belongs under `plans/` as public machine-readable coordination.

- A plan records mission, owner, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff.
- A branch or pull request transports and reviews implementation; it is not the only durable coordination record.
- Update the plan in the implementation branch when material state changes.
- Never put credentials, customer data, private hostnames, local paths, provider state, or raw runtime evidence in a public plan.
- A plan never grants merge, deployment, authentication, target-mutation, or destructive-Git authority.

Use `.ai/skills/public-plan-coordination/SKILL.md` and the repository's public-plan validator.

## Runtime event composition

Event-producing or event-observing features register:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

Every source, observer, handler, sink, event type, and edge belongs in the repository's machine-readable runtime topology. Root events begin correlation; successors inherit correlation, identify their parent as causation, and advance sequence. Emitted envelopes are immutable.

Static topology does not prove runtime delivery. A runtime claim requires correlated source, observer, handler, successor or terminal, and sink evidence from an authorized runtime lane.

Validate the runtime-event-contract with `scripts/Test-RuntimeEventContract.ps1`.

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

Use isolated branches and worktrees for concurrent writers. Reuse healthy existing tools and directories. Make bounded tracked changes, run repository-native checks, commit, push when authorized, and report exact proof and gaps. A request that claims installation, setup, build, execution, repair, configuration, upgrade, deployment, merge, release, event-listener construction, or event-cascade proof is invalid when it permits acknowledgment or plan substitution instead of corresponding mutation and proof.
