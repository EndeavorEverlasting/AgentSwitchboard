---
id: post-integration-local-adoption
status: canonical
---

# Post-integration local adoption

## Trigger

Use this skill after an integration/merge when the next useful action depends on a local workstation actually containing and using the merged file, validator, launcher, or artifact. It also applies when a user reports that a newly merged command is missing locally.

## Required inputs

- repository identity;
- integration SHA;
- remote name (normally `origin`);
- canonical machine/profile path owner;
- canonical validator/launcher identity from tracked harness metadata.

## Procedure

1. Load `tooling/harness/operational/canonical-path.contract.json`, `tooling/harness/operational/workflows/canonical-path-proof.workflow.json`, and `.ai/skills/canonical-path-proof/SKILL.md`. This skill specializes that seam; it does not define a second path authority.
2. Resolve development checkout, production/use path, temporary worktree root, and real operator entrypoint through the registered owner.
3. Refresh with `git fetch --all --prune --tags`; resolve the remote default branch rather than assuming `main`.
4. Prove the integration SHA is contained in the refreshed remote default branch.
5. Inspect the canonical development checkout. Clean + default-branch + behind-only may use `git pull --ff-only`; otherwise preserve the checkout and use the approved isolated worktree root.
6. Prove the canonical development checkout and production/use path independently, honoring an explicit `same-path` relation when the owner supplies one.
7. Prove the real entrypoint is tracked/present at the use path, run the owning validator, then invoke the entrypoint only if that proof is requested.
8. Record all four proof states independently and advance the first still-unproved gate.

## Expected outputs

- canonical role bindings;
- remote/check-out/use-path/entrypoint proof states;
- validator and entrypoint receipt where actually executed;
- a next action that advances the first unproved state.

## Known trap

A GitHub merge, green PR, or remote `main` containment **does not** prove the canonical development checkout has pulled the change. A current checkout does not automatically prove a separate production/use path, and file presence does not prove the real operator entrypoint observed it. Refresh and promote each required state before issuing the dependent command.

## Forbidden scope

No reset/clean/force, no silent stash, no deletion of unrelated/noncanonical work, no guessed paths, no second mutable canonical clone, and no claim of workstation/runtime success from remote evidence alone.
