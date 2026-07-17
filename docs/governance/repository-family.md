# Repository Family Governance

## Canonical root

`EndeavorEverlasting/AgentSwitchboard` is the canonical policy source for the shared agent operating contract.

It owns:

- baseline meanings for `AGENTS.md`, `CLAUDE.md`, `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`;
- canonical skill definitions;
- capability and proof terminology;
- repository-adoption templates;
- validators for the documentation contract;
- repository-family profiles and read-only intake;
- orchestration patterns that can distribute reviewed work across agents and repositories.

It does **not** silently control another repository at runtime. Each repository must adopt a pinned contract through tracked files and remains authoritative for its product behavior, deployment boundaries, local data, artifacts, validation, and proof promotion.

## Registered repository family

The broad policy family remains declared in `.ai/agent-contract.json`.

| Repository | Relationship | Adoption responsibility |
|---|---|---|
| `EndeavorEverlasting/AgentSwitchboard` | canonical root | publish and validate the baseline |
| `EndeavorEverlasting/Continuum` | child | declare local mission, entry points, validators, and safety boundaries |
| `EndeavorEverlasting/foundry` | child | declare local mission, entry points, validators, and safety boundaries |
| `EndeavorEverlasting/BlacksmithGuild` | child | declare local mission, entry points, validators, and runtime/game boundaries |
| `EndeavorEverlasting/SysAdminSuite` | child | declare local mission, entry points, validators, and target-mutation boundaries |
| `EndeavorEverlasting/web-excel-repair-triage` | child | declare local mission, entry points, validators, and artifact/output boundaries |

## Operational harness targets

AgentSwitchboard must readily inspect and coordinate these exact repositories now:

1. `EndeavorEverlasting/AgentSwitchboard`
2. `EndeavorEverlasting/BlacksmithGuild`
3. `EndeavorEverlasting/web-excel-repair-triage`
4. `EndeavorEverlasting/SysAdminSuite`

Their executable profile contract is `.ai/harness/repository-family.registry.json`. The registry names local rules, codebase maps, skills, workflows, run-context authorities, artifact registries, validators, reports, handoff contracts, generated-output policy, and proof ceilings.

Continuum and foundry remain members of the broad policy family but are not represented as operationally ready by this four-repository harness. Adding them later requires a reviewed registry version change, local profile evidence, and validation.

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
- Child rules may not silently weaken requirements for evidence, isolation, scope, proof honesty, secret handling, and tracked delivery.
- A justified exception must be explicit, reviewed, and machine-visible where practical.
- A family profile may route and inspect; it may not override child product or runtime authority.

## Propagation workflow

A canonical contract change follows this sequence:

1. update AgentSwitchboard entrypoints, skills, registries, templates, and validators;
2. increment the relevant contract or registry version;
3. validate and merge the root change;
4. open one bounded adoption PR per child repository;
5. preserve repository-specific additions;
6. record skipped children and blockers;
7. never bulk overwrite child `AGENTS.md` files without reviewing their local law.

Open pull requests are evidence only. Default-branch tracked files remain authority.

## Minimum child-repository harness

Every operational child should eventually expose:

```text
AGENTS.md
CODEBASE_MAP.md
scoped skills or capabilities
machine-readable workflow specifications
run-context authority
artifact registry authority
repository-owned validators
English/operator report contract
schema-backed final handoff
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

## Read-only readiness

The family status probe checks local clone identity, branch attachment, dirty state, and required path presence without cloning, fetching, validating children, or mutating anything:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1
```

A `ready` observation is intake evidence only. The receiving agent must still read the child repository's current rules and run its own validators before making or accepting changes.
