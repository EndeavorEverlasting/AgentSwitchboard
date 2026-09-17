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

Integration completion reports must separate prove results, flag status, and forge status as independent signals:

### Prove results

- Which validators re-ran after integration (command paths);
- Exit codes and result levels (PASS, SKIP, FAIL, FAIL_CLOSED, BLOCKED_HOST);
- Changed-file scope comparison: before vs after integration;
- Proof level achieved (contract proof, static test proof);
- Proof ceiling: integration validation does NOT prove runtime behavior or deployment readiness.

### Flag status

- Diff hygiene after conflict resolution: `git diff --check` result;
- Unique work preserved: commit comparison showing no silently dropped changes;
- Ledger coherence after convergence (when applicable);
- Unrelated dirty work state.

### Forge status

Report forge readiness for each integrated branch when merge authority is present:

- PR URLs and updated base/head relationships;
- Mergeability: conflicts resolved, remaining conflict files (if any);
- Required status checks: re-triggered, passing, or pending after push;
- Review state: preserved approvals, dismissed reviews, re-review requirements;
- Integration order and dependencies.

When merge authority is absent, product pass (prove + flags clean after integration) completes the convergence work.

### General outputs

- Integration order and merge-base evidence;
- Conflict resolutions with preserved unique work;
- Updated branches or retargeted PR bases;
- Commit SHAs for each integrated branch.

## Deterministic validation

Product pass after integration requires:

1. **Owning prove commands pass after convergence:**
   - Re-run relevant validators on the integrated state.
   - `pwsh -NoLogo -NoProfile -File scripts/Prove-AutomatedTestFloorLocal.ps1` when integration affects floor contracts.
   - Domain-specific validators for converged scope.

2. **Harness flags clean:**
   - `git diff --check` exits clean after conflict resolution.
   - Unique work preserved: commit comparison shows all unique commits are reachable.
   - No silent squashing or dropped changes without explicit authorization.

3. **Proof ceiling respected:**
   - Commit comparison, merge-base evidence, and changed-file scope provide integration proof.
   - Static validators after integration provide contract proof or static test proof only.
   - They do NOT prove runtime behavior, CI status from GitHub Actions, or deployment readiness.

Use merge-base comparison first, then conflict resolution, then targeted validators on the integrated result.

## Forbidden scope

No force-push, branch deletion, history rewrite, or silent squashing of unique work without explicit authorization.

## Stop and escalate

Stop when ancestry is ambiguous, a local-only commit is inaccessible, or integration would overwrite unpreserved work.
