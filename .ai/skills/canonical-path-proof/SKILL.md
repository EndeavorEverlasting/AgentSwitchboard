---
id: canonical-path-proof
status: canonical
---

# Canonical path proof

## Trigger

Use this procedure before almost every **local repository-backed action**: mutation, validation, build/generation, launcher/updater invocation, deployment helper, or operator handoff that depends on local repository state. It also owns explicit canonical-path, checkout, worktree, production/use-path, local-adoption, and newly-merged-command questions.

Provider-only remote reads and static source inspection may be exempt only when they make no local adoption/use-path claim; record that exemption instead of pretending the proof ran.

## Required inputs

- requested action and required proof level;
- `tooling/harness/operational/canonical-path.contract.json`;
- the selected machine/profile path owner;
- integration SHA/content floor when the action depends on a specific change;
- remote name (normally `origin`).

## Procedure

1. Load the canonical-path contract. Resolve the machine/profile path owner; do **not** select a directory because it is convenient, current, familiar, or model-preferred.
2. Resolve the four roles: `developmentCheckout`, `productionUsePath`, `temporaryWorktreeRoot`, and `realOperatorEntrypoint`. Record a role as N/A only when the canonical owner gives a reason.
3. Refresh with `git fetch --all --prune --tags`; resolve the actual remote default branch rather than assuming `main`.
4. Prove `remote-main-contains-sha` only with refreshed ancestry/provider evidence.
5. Inspect the **canonical development checkout**. Clean + default-branch + behind-only may use `git pull --ff-only`. Dirty/diverged/separately-owned work is preserved; use the approved isolated worktree root for bounded proof/action instead of cleaning or creating another mutable clone.
6. Prove `canonical-development-checkout-current` from the checkout actually inspected after refresh.
7. Resolve `productionUsePath` separately. If the owner declares `same-path`, reuse the observed checkout evidence and record the relation. Otherwise prove the production/use surface separately.
8. Resolve the real operator entrypoint from tracked authority; prove it is present/tracked at the use path before invocation.
9. Run the owning validator/build/generator/launcher only after its required path states are proven. Mark `real-entrypoint-observes-it` only after the real entrypoint actually executes or emits the bounded requested receipt.
10. Report each proof state independently and make the next command advance the first still-unproved required state.

## Expected outputs

- canonical role bindings or explicit N/A reasons;
- four independent path/proof-state dispositions;
- preserved dirty/diverged/noncanonical work;
- owning validator/entrypoint receipt when executed;
- one executable next action for the first unproved gate.

## Known traps

- **Remote `main` contains SHA is not local checkout proof.**
- A current development checkout is not automatically a separate installed/served production path.
- A tracked launcher existing is not proof that the real operator entrypoint observed the change.
- A second mutable clone is path sprawl, not a worktree strategy.
- Desktop/OneDrive/backup/current-working-directory paths do not become canonical merely because they contain the repository.
- `P92 Canonical Path Prompt` owns deep path repair/audit. This P01 seam must reuse the machine/profile owner rather than forking it.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-CanonicalPathHarness.ps1
python3 tests/test_canonical_path_harness.py
git diff --check
```

## Forbidden scope

No `AGENTS.md` mutation, no product/launcher rewrites, no secret collection, no reset/clean/force push, no silent stash, no deletion of preserved clones/worktrees, and no runtime/deployment claim from repository/path evidence alone.
