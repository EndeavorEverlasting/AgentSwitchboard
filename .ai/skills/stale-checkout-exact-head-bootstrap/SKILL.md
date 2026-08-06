---
id: stale-checkout-exact-head-bootstrap
version: 1.0.0
status: canonical
---

# Stale-Checkout Exact-Head Bootstrap

## Trigger

Use this skill when an operator has a verified AgentSwitchboard checkout, but that checkout predates `Validate-Technician-ExactHead.cmd` or another required exact-head harness entrypoint.

## Required inputs

- verified local AgentSwitchboard repository path;
- explicit remote branch ref in `refs/heads/<branch>` form;
- exact expected 40-character commit SHA;
- requested mode: `validate` or `ready`;
- target Windows machine role and proof ceiling.

## Read first

1. `tooling/profiles/windows/harness/stale-checkout-exact-head/manifest.json`
2. `tooling/profiles/windows/harness/stale-checkout-exact-head/workflows/bootstrap.workflow.json`
3. `tooling/profiles/windows/harness/stale-checkout-exact-head/artifact-registry.json`
4. `tooling/profiles/windows/harness/technician-live-cert/artifact-registry.json`
5. `.ai/skills/operator-command-envelope/SKILL.md`

## Procedure

1. Treat the existing checkout as read-only evidence. Do not switch branches, reset, clean, stash, overwrite, or pull over local work.
2. Verify the origin is canonical AgentSwitchboard.
3. Fetch only the explicit remote ref without force or tags.
4. Require `FETCH_HEAD` to equal the expected SHA.
5. Extract or run `scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1` from that exact commit.
6. Let the bootstrap create a detached temporary validator and invoke `Validate-Technician-ExactHead.cmd` from the exact fetched head.
7. Require a fresh exact-head JSON artifact whose `verifiedHead` equals the expected SHA.
8. Publish the bootstrap report and delegated exact-head report paths.
9. Remove only a clean temporary validator created by the current run. Preserve any unproved or dirty path.

## Outputs

- local bootstrap JSON and Markdown reports;
- delegated exact-head JSON and Markdown reports;
- actual verified SHA;
- source-checkout preservation statement;
- exact blocker or next command.

## Forbidden

- guessing a repository path or branch;
- running a missing local launcher as though it existed;
- force fetch, reset, clean, stash, branch switching, or destructive worktree removal;
- executing copied prompts, transcripts, or error output;
- claiming exact-head proof from fetch success, launcher acknowledgement, or stale artifacts;
- committing generated local evidence.

## Deterministic validation

```powershell
python -m unittest tests.test_stale_checkout_exact_head_bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-StaleCheckoutExactHeadBootstrap.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-StaleCheckoutExactHeadBootstrap.ps1
```

## Proof ceiling

This skill proves safe delegation from a stale checkout to the exact commit's repository-owned validator and fresh artifact readback. It does not exceed the delegated exact-head artifact's proof ceiling.
