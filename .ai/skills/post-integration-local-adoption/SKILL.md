---
id: post-integration-local-adoption
status: canonical
---

# Post-integration local adoption

## Trigger

Use this skill after an integration/merge when the next useful action depends on a local checkout actually containing the merged file, validator, launcher, or artifact. It also applies when a user reports that a newly merged command is missing locally.

## Required inputs

- repository location or a safe repository resolver;
- integration SHA;
- remote name (normally `origin`);
- canonical validator/launcher path from tracked harness metadata.

## Procedure

1. Resolve the repository root and refresh with `git fetch --all --prune --tags`.
2. Resolve the remote default branch from `refs/remotes/origin/HEAD` or a symref/provider query; never assume `main`.
3. Verify `git merge-base --is-ancestor <integration-sha> <remote-default-head>` succeeds.
4. Inspect `git status --short`, current branch, tracking branch, and ahead/behind counts.
5. Clean + default-branch + behind-only: run `git pull --ff-only` and re-read HEAD.
6. Dirty, diverged, or separately owned checkout: leave it untouched and create/use an isolated worktree at the refreshed remote default head for the proof run.
7. Verify the chosen checkout contains the integration SHA and the required path is tracked with `git ls-files --error-unmatch -- <path>`.
8. Run the owning validator. Only after it passes should the newly merged launcher/artifact be executed or opened.
9. Report the exact checkout path, HEAD, integration containment, validator exit, launcher/artifact used, and remaining runtime proof ceiling.

## Expected outputs

- a local checkout proven to contain the integration;
- an owning validator result from that checkout;
- launcher/artifact execution evidence when requested;
- a next action that advances the first still-unproved gate.

## Known trap

A GitHub merge, green PR, or remote `main` containment **does not** prove the operator's workstation checkout has pulled that change. Do not issue a newly merged local command as the next command until local adoption is proven or the command itself performs the safe adoption first.

## Forbidden scope

No reset/clean/force, no silent stash, no deletion of unrelated worktrees, no guessed paths, and no claim of workstation/runtime success from remote evidence alone.
