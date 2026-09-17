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

Sprint completion reports must separate prove results, flag status, and forge status as independent signals:

### Prove results

- Which validators ran (command paths, versions when relevant);
- Exit codes and result levels (PASS, SKIP, FAIL, FAIL_CLOSED, BLOCKED_HOST);
- Proof packet or artifact locations when applicable;
- Proof level achieved (contract proof, static test proof, build proof, runtime proof);
- Proof ceiling for this sprint (what the validators do NOT prove).

### Flag status

- Diff hygiene: `git diff --check` result and trailing whitespace violations;
- Ledger contracts: verb-first entries, required fields, WORK_QUEUE coherence;
- Zero-test guards: test discovery count, fail-closed conditions;
- Unrelated dirty work preservation: `git status --short` before/after.

### Forge status

Report forge readiness only when merge authority is present or when the task explicitly requires forge-pass evaluation:

- PR state and URL;
- Mergeability: conflicts with target branch, conflict file list;
- Required status checks: passing, pending, or failing (with check names and log URLs);
- Required reviews: approved, pending, or changes requested;
- Branch protection rules satisfied or blocked.

When merge authority is absent, product pass (prove + flags clean) completes the sprint. Do not idle-wait on GitHub Actions, external CI, or `mergeable_state` when product pass holds.

### General outputs

- Useful tracked implementation and commit SHA;
- Deterministic tests, validators, schemas, or operational docs added or updated;
- Honest validation and gap report.

## Deterministic validation

Product pass requires:

1. **Owning prove commands pass:**
   - `pwsh -NoLogo -NoProfile -File scripts/Prove-AutomatedTestFloorLocal.ps1` for always-on floor contracts.
   - `pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1` when changed paths activate merge-relevant gates.
   - Domain-specific `Test-*.ps1` validators for owned subsystems.

2. **Harness flags clean:**
   - `git diff --check origin/main...HEAD` exits clean (no trailing whitespace).
   - Ledger contracts satisfied (verb-first entries, required fields).
   - Zero-test guards satisfied (test discovery returned expected non-zero count when tests were required).

3. **Proof ceiling respected:**
   - Static validators provide contract proof or static test proof only.
   - They do NOT prove runtime behavior, live-target success, merge authority, release readiness, or deployment outcomes.

Run targeted tests first, then broader checks when practical. Preserve failing evidence and repair the first deterministic boundary.

## Forbidden scope

No unrelated rewrites, hidden stubs, secret persistence, automatic merge/deploy, force-push, or target mutation outside explicit scope.

## Stop and escalate

Stop with an exact blocker when safe edits cannot continue, or escalate when the work crosses forbidden scope or requires unavailable authority.
