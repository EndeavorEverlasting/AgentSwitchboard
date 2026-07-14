---
id: repo-intake
version: 1.0.0
status: canonical
---

# Repository Intake

## Trigger

Use for an unfamiliar repository, stale or placeholder context, uncertain Git state, or when repository truth must be recovered before selecting work.

## Inputs

- repository path or repository identifier;
- current branch and worktree state when available;
- task request and known constraints;
- accessible PR, issue, plan, test, validator, and artifact evidence.

## Procedure

1. Run compact Git and PR preflight.
2. Read repository law and architecture entry points.
3. Inspect recent commits, active branches, plans, tests, validators, artifacts, and unresolved signals.
4. Distinguish fact, inference, and unknown.
5. Rank bounded sprint candidates.
6. Select the smallest safe sprint that unblocks the most later work.
7. Hand off to `bounded-sprint` when a safe tracked change exists.

## Outputs

- compact evidence ledger;
- ranked sprint queue;
- selected owned and forbidden scope;
- exact blocker when no safe write is possible.

## Deterministic validation

Use repository-native validators plus Git status, diff, branch, and PR evidence. Do not persist a census document unless downstream workflows require it.

## Forbidden scope

Do not crawl vendored/generated dependencies without cause. Do not mutate live targets, rewrite history, or create speculative architecture as a substitute for evidence.

## Stop and escalate

Stop when repository state is unsafe to modify, required evidence is inaccessible, or the next action requires unauthorized destructive or live-target behavior.
