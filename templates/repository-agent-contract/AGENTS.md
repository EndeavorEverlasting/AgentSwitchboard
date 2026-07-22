# Agent Operating Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`

## Repository mission

`REPLACE_REPOSITORY_MISSION`

## Required reading

1. this `AGENTS.md` and nearest nested `AGENTS.md`;
2. `CODEBASE_MAP.md`, `README.md`, and repository operating docs;
3. tool adapter, skills, capabilities, and triggers;
4. selected skill and public plan;
5. `docs/governance/harness-doctrine.md` and its policy;
6. runtime-event doctrine when event composition is in scope;
7. `docs/governance/device-profile-launcher-contract.md` and `.ai/harness/device-profile-launcher.policy.json` when platform launch behavior is in scope;
8. current validators, PRs, and Git history.

Every writing sprint names repository, branch or worktree, PR or sprint, lane, owned and forbidden scope, expected artifacts, validation order, and proof ceiling. Task-specific execution rules override generic closeout inside higher-priority safety and repository law.

## Public coordination

Material cross-session work belongs under `plans/`. Plans record ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. They do not grant authentication, merge, deployment, target mutation, secret access, or destructive-Git authority.

## Runtime event composition

Register:

`event source -> typed event envelope -> observer or listener -> handler -> emitted successor event -> artifact or evidence sink`

Static topology does not prove runtime delivery. Runtime claims require correlated observed source, observer, handler, successor or terminal, and sink evidence. Validate with `scripts/Test-RuntimeEventContract.ps1`.

## Device profile launchers

AgentSwitchboard owns one canonical launcher per platform profile. The Windows Profile is WezTerm-backed and uses idempotent `open-or-activate`. Consumer repositories and desktop shortcuts delegate only; they do not own lifecycle, discovery, activation, duplicate prevention, or raw frontend fallback.

Linux and Android are separate implementations. Android configuration may differ. A missing or uncertified canonical launcher is blocked. Contract-only doctrine does not prove a launcher exists or a workspace opened or activated. Validate with `scripts/Test-DeviceProfileLauncherContract.ps1`.

## Entry points

- source: `REPLACE_SOURCE_ROOTS`
- launchers: `REPLACE_LAUNCHERS`
- public plans: `plans/plan-registry.json`
- validators: `REPLACE_VALIDATION_COMMANDS`
- generated artifacts: `REPLACE_ARTIFACT_PATHS`

## Safety boundaries

- forbidden scope: `REPLACE_FORBIDDEN_SCOPE`
- runtime or deployment boundary: `REPLACE_RUNTIME_BOUNDARY`
- data policy: `REPLACE_DATA_POLICY`
- target mutation policy: `REPLACE_TARGET_MUTATION_POLICY`

## Delivery contract

Preserve unrelated work, isolate writers, reuse healthy contracts, make bounded tracked changes, validate, commit, push when authorized, and report exact proof and gaps. An action request is invalid when it permits acknowledgment, architecture-only output, a plan, summary, or handoff instead of corresponding mutation and proof.
