---
id: pr-integration
version: 1.0.0
status: canonical
---

# PR and Branch Integration

## Trigger

Use for stacked PRs, parallel worktrees, consumed commits, merge readiness, conflict repair, or branch convergence.

## Inputs

- PR base/head relationships;
- commit SHAs and merge bases;
- owned files for each lane;
- validation evidence and unresolved reviews.

## Procedure

1. Map branch ancestry and active worktrees.
2. Identify collisions, superseded branches, and unique commits.
3. Integrate shared contracts before downstream consumers.
4. Resolve conflicts without discarding unique work.
5. Re-run relevant validation after convergence.
6. Retarget or update PRs in dependency order.
7. Merge only with explicit authority.

## Outputs

- integration order;
- conflict resolutions;
- updated branches or PR bases;
- merge-readiness evidence.

## Deterministic validation

Use commit comparison, merge-base evidence, changed-file scope, validators, CI status, and resolved review state.

## Forbidden scope

No force-push, branch deletion, history rewrite, or silent squashing of unique work without explicit authorization.

## Stop and escalate

Stop when ancestry is ambiguous, a local-only commit is inaccessible, or integration would overwrite unpreserved work.
