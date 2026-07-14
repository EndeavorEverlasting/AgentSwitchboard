# Agent Operating Contract

This file is the universal repository entry point for coding agents, review agents, and orchestration tools working in AgentSwitchboard.

AgentSwitchboard is the **canonical policy source** for the EndeavorEverlasting repository family. It publishes the baseline contract and adoption templates. Every child repository remains the source of truth for its own product behavior, safety boundaries, and validation commands.

## Required reading order

Before proposing or changing work, read in this order:

1. `AGENTS.md`
2. the nearest nested `AGENTS.md` governing the files in scope
3. `README.md`, `CONTRIBUTING.md`, and repository-specific operating docs
4. the tool adapter when applicable, such as `CLAUDE.md`
5. `SKILLS.md`
6. `CAPABILITIES.md`
7. `TRIGGERS.md`
8. the specific skill under `.ai/skills/` selected by the trigger
9. current plans, handoffs, tests, validators, open PRs, and recent Git history relevant to the task

Do not treat filenames, timestamps, stale handoffs, or remembered chat context as operational truth when repository evidence is available.

## Instruction precedence

1. Platform, security, legal, and repository-owner instructions always win.
2. A nested `AGENTS.md` may add or strengthen rules for its subtree.
3. A tool adapter such as `CLAUDE.md` may explain tool-specific behavior but may not weaken this contract.
4. A task prompt selects work; it does not silently grant capabilities forbidden by repository policy.
5. When instructions conflict, stop the conflicting action, preserve evidence, and name the conflict.

## Mandatory operating discipline

- **Evidence before action.** Inspect the repository, current Git state, relevant contracts, and existing patterns before inventing.
- **Floor before furniture.** Repair unsafe repository state before feature work.
- **Bound the sprint.** State owned scope, forbidden scope, expected artifacts, validation, and proof ceiling.
- **Isolate writers.** One branch and worktree per active writing lane. Never share uncommitted state between agents.
- **Reuse before replacing.** Existing healthy tools, directories, helpers, contracts, and artifacts should be used. Missing items may be created or installed only when authorized.
- **Separate skills from code.** Skills describe procedures and judgment. Deterministic behavior belongs in scripts, modules, validators, schemas, and workflows.
- **Checkpoint before expansion.** Commit coherent progress before broad validation, expensive runtime proof, or scope growth.
- **Route failures with evidence.** Return exact command output, structured errors, and artifact paths to the responsible agent.
- **Do not inflate proof.** Static checks do not prove runtime behavior; synthetic proof does not prove live-target behavior.
- **Protect sensitive data.** Never commit secrets, credentials, personal data, private hostnames, raw customer evidence, huge logs, crash dumps, or machine-local junk.
- **Deliver tracked progress.** When safe and authorized, modify tracked files, validate, commit, push, and open or update a PR.

## Required sprint declaration

Every writing sprint must establish:

- repository and branch;
- lane and mission;
- owned scope;
- forbidden scope;
- dependencies and collision risks;
- expected tracked artifacts;
- validation commands;
- proof ceiling;
- commit and PR expectation.

If the worktree is dirty and the lane does not own the dirt, preserve it and use an isolated worktree. Do not reset or discard another lane's work.

## Capability and authority rule

A tool may perform an action only when all four are true:

1. the environment exposes the capability;
2. the capability has been verified in the current environment;
3. the task authorizes the action;
4. repository policy does not forbid it.

Capability presence is not authority. See `CAPABILITIES.md`.

## Trigger rule

Triggers select a reviewed workflow or skill. They never grant destructive authority, live-target access, secret access, merge rights, or deployment rights. See `TRIGGERS.md`.

## Skills rule

Use the smallest applicable skill. Follow its inputs, procedure, outputs, and stop conditions. A skill may coordinate deterministic code but must not duplicate executable logic in prose. See `SKILLS.md`.

## Repository-family inheritance

The canonical contract version and registered repositories are declared in `.ai/agent-contract.json`.

Child repositories adopt this baseline through tracked files, record the pinned canonical version, and add product-specific rules. Local rules may strengthen safety or specialize behavior. They may not silently weaken the canonical baseline.

Canonical policy changes are propagated by reviewable pull requests, never by invisible remote mutation.

## Completion standard

A task is complete only when the final response and repository state agree about:

- files changed;
- validation actually run;
- skipped checks and exact follow-up commands;
- commit SHA;
- push and PR state;
- remaining blockers and risks;
- final Git status.
