# Repository Family Governance

## Canonical root

`EndeavorEverlasting/AgentSwitchboard` is the canonical policy source for the shared agent operating contract.

It owns:

- baseline meanings for `AGENTS.md`, `CLAUDE.md`, `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`;
- canonical skill definitions;
- capability and proof terminology;
- repository-adoption templates;
- validators for the documentation contract;
- orchestration patterns that can distribute reviewed work across agents and repositories.

It does **not** silently control another repository at runtime. Each repository must adopt a pinned contract through tracked files and remains authoritative for its product behavior, deployment boundaries, customer data, and local validation.

## Registered repository family

| Repository | Relationship | Adoption responsibility |
|---|---|---|
| `EndeavorEverlasting/AgentSwitchboard` | canonical root | publish and validate the baseline |
| `EndeavorEverlasting/Continuum` | child | declare local mission, entry points, validators, and safety boundaries |
| `EndeavorEverlasting/foundry` | child | declare local mission, entry points, validators, and safety boundaries |
| `EndeavorEverlasting/BlacksmithGuild` | child | declare local mission, entry points, validators, and runtime/game boundaries |
| `EndeavorEverlasting/SysAdminSuite` | child | declare local mission, entry points, validators, and target-mutation boundaries |
| `EndeavorEverlasting/web-excel-repair-triage` | child | declare local mission, entry points, validators, and artifact/output boundaries |

The machine-readable registry is `.ai/agent-contract.json`.

## Inheritance model

The family uses **pinned-copy with repository specialization**:

1. copy the files under `templates/repository-agent-contract/` into the child repository;
2. record the canonical repository and contract version in the child `.ai/agent-contract.json`;
3. replace placeholders with the child repository's real mission, source roots, validation commands, artifact policy, and forbidden scope;
4. add nested `AGENTS.md` files only where a subtree needs stronger or more specific rules;
5. run the local documentation-contract validator;
6. commit adoption through a dedicated PR.

This avoids invisible remote behavior and prevents a root policy update from unexpectedly changing active repositories.

## Conflict rules

- Platform and security policy always win.
- Child rules may strengthen safety.
- Product-specific constraints may specialize the baseline.
- Child rules may not silently weaken the canonical requirements for evidence, isolation, scope, proof honesty, secret handling, and tracked delivery.
- A justified exception must be explicit, reviewed, and machine-visible where practical.

## Propagation workflow

A canonical contract change follows this sequence:

1. update AgentSwitchboard entrypoints, skills, registry, templates, and validator;
2. increment `contractVersion`;
3. validate and merge the root change;
4. open one bounded adoption PR per child repository;
5. preserve repository-specific additions;
6. record skipped children and blockers;
7. never bulk overwrite child `AGENTS.md` files without reviewing and merging their local law.

## Minimum child-repository contract

Every registered child should eventually contain:

```text
AGENTS.md
CLAUDE.md
SKILLS.md
CAPABILITIES.md
TRIGGERS.md
.ai/agent-contract.json
.ai/skills/
```

Each child must additionally name:

- mission and product boundaries;
- source and launcher entry points;
- build, test, validator, and smoke commands;
- generated-artifact and cleanup policy;
- secret and personal-data boundaries;
- runtime and deployment seams;
- target-mutation rules;
- repository-specific proof levels;
- branch, worktree, commit, and PR expectations.
