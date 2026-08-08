---
id: stale-checkout-exact-head-bootstrap
version: 1.2.0
status: canonical
---

# Stale-Checkout Exact-Head Bootstrap

## Trigger

Trigger ID: `technician.stale-checkout-exact-head`

Use this skill when a verified AgentSwitchboard checkout exists but is stale relative to the exact commit that must own technician readiness or live-cert validation. This includes a checkout that predates `Validate-Technician-ExactHead.cmd` or whose local branch must not be switched, reset, cleaned, stashed, or overwritten.

## Inputs

- verified local AgentSwitchboard repository path;
- explicit remote branch ref in `refs/heads/<branch>` form;
- exact expected 40-character commit SHA;
- requested mode: `validate` or `ready`;
- target Windows machine role and proof ceiling.

## Required composition

- `operator-command-delivery` owns executable/operator command boundaries and concrete child-executable proof.
- `powershell-interactive-execution` owns interactive PowerShell parse boundaries and immediate native exit-code capture.
- The exact-head validator owns isolated candidate worktree creation, validation/readiness execution, and exact-head artifacts.

Do not revive the superseded `operator-command-envelope` stack. For changes to this bootstrap, run the current command-delivery harness in addition to the focused bootstrap validators.

## Procedure

1. Treat the source checkout as read-only evidence. Do not switch branches, reset, clean, stash, overwrite, or pull over local work.
2. Verify the origin is canonical AgentSwitchboard.
3. Fetch only the explicit remote ref without force or tags.
4. Require `FETCH_HEAD` to equal the expected SHA.
5. If the checkout contains `Bootstrap-Technician-ExactHead.cmd`, prefer that tracked click/command entrypoint; it delegates to `scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1`.
6. The bootstrap engine extracts `scripts/Invoke-TechnicianExactHeadValidation.ps1` from the exact fetched commit rather than trusting the stale checkout's validator copy.
7. Execute PowerShell as one complete script invocation or one atomic interactive submission. Never split compound control flow across prompt submissions.
8. Require a fresh exact-head JSON artifact whose `verifiedHead` equals the expected SHA and whose worktree is clean.
9. In `ready` mode, require the delegated artifact to prove readiness was actually requested.
10. Publish bootstrap and delegated exact-head report paths. Delete only the temporary runner created by this invocation.

## Outputs

- local `stale-checkout-bootstrap.json` and Markdown report;
- delegated `exact-head-validation.json` and Markdown report;
- actual verified SHA;
- source-checkout preservation statement;
- exact blocker when validation cannot advance.

## Deterministic validation

```powershell
python -m unittest tests.test_stale_checkout_exact_head_bootstrap
pwsh -NoLogo -NoProfile -File scripts/Test-StaleCheckoutExactHeadBootstrap.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1 -CandidatePath scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1
git --no-pager diff --check
```

On Windows, also run the focused PowerShell validator under Windows PowerShell 5.1 when available.

## Forbidden scope

- guessing repository path, branch, or SHA;
- force fetch, reset, clean, stash, branch switching, or destructive worktree removal;
- invoking a launcher that is absent from the source checkout;
- using the superseded operator-command-envelope harness as authority;
- splitting an interactive compound statement across submissions;
- claiming exact-head or runtime proof without fresh artifact readback;
- tracking generated workstation evidence.

## Stop and escalate

Stop when origin identity, expected ref/SHA, Git/PowerShell availability, delegated validator output, or artifact freshness cannot be proven. Preserve the first failure and report the exact blocker; do not mutate the source checkout to manufacture a pass.

## Proof ceiling

This skill proves safe delegation from a preserved stale checkout to the exact commit's repository-owned validator and fresh artifact readback. It does not exceed the delegated exact-head artifact's proof ceiling.
