---
id: bounded-sprint
version: 1.0.0
status: canonical
---

# Bounded Sprint Execution

## Trigger

Use after repository intake identifies a safe implementation, validation, cleanup, documentation, or integration slice.

## Inputs

- repository and branch;
- mission, owned scope, and forbidden scope;
- expected artifacts;
- validation commands;
- proof ceiling and delivery expectation.

## Procedure

1. Confirm the worktree is safe or create an isolated worktree.
2. Inspect existing helpers, contracts, and patterns in owned scope.
3. Make the smallest useful tracked change.
4. Add or update deterministic enforcement.
5. Checkpoint coherent progress before broad validation.
6. Run targeted checks, then broader checks when practical.
7. Review the final diff.
8. Commit, push, and open or update the PR when authorized.

## Outputs

- useful tracked implementation;
- deterministic tests, validators, schemas, or operational docs;
- commit SHA and PR state;
- honest validation and gap report.

## Deterministic validation

Run targeted tests, relevant validators/static checks, build checks, `git diff --check`, `git status --short`, and final diff review.

## Forbidden scope

No unrelated rewrites, hidden stubs, secret persistence, automatic merge/deploy, force-push, or target mutation outside explicit scope.

## Stop and escalate

Stop with an exact blocker when safe edits cannot continue, or escalate when the work crosses forbidden scope or requires unavailable authority.
