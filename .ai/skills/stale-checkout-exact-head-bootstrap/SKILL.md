---
id: stale-checkout-exact-head-bootstrap
version: 1.1.0
status: canonical
---

# Stale-Checkout Exact-Head Bootstrap

## Deterministic trigger

Trigger ID: `technician.stale-checkout-exact-head`

Select this skill when a verified AgentSwitchboard checkout exists but predates a required exact-head harness entrypoint, especially `Validate-Technician-ExactHead.cmd`.

## Required inputs

- verified local AgentSwitchboard repository path;
- explicit remote branch ref in `refs/heads/<branch>` form;
- exact expected 40-character commit SHA;
- requested mode: `validate` or `ready`;
- target Windows machine role and proof ceiling.

## Preconditions

- The source checkout is a canonical AgentSwitchboard repository.
- The source checkout is preserved as read-only evidence.
- Git and PowerShell 7 are available.
- The expected remote ref and SHA are explicit.

## Required composition

- `operator-command-envelope` owns the operator-facing executable envelope.
- `powershell-interactive-execution` owns the interactive PowerShell submission boundary.
- The exact-head validator owns detached worktree creation, cross-shell validation, P00/readiness execution, and proof artifacts.

The operator handoff must pass both `scripts/Test-OperatorCommandEnvelope.ps1` and `scripts/Test-SkillFactoringContracts.ps1`. A missing local launcher is never invoked directly.

## Procedure

1. Treat the existing checkout as read-only evidence. Do not switch branches, reset, clean, stash, overwrite, or pull over local work.
2. Verify the origin is canonical AgentSwitchboard.
3. Fetch only the explicit remote ref without force or tags.
4. Require `FETCH_HEAD` to equal the expected SHA.
5. Extract `scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1` from that exact commit.
6. Execute the extracted engine as one atomic PowerShell submission or a saved temporary script—not as separated `if`/`elseif`/`else` blocks.
7. Require a fresh exact-head JSON artifact whose `verifiedHead` equals the expected SHA.
8. Publish the bootstrap and delegated exact-head report paths.
9. Remove only a temporary runner created by the current run; preserve anything not proved safe to remove.

## Produced outputs

- local bootstrap JSON and Markdown reports;
- delegated exact-head JSON and Markdown reports;
- actual verified SHA;
- source-checkout preservation statement;
- exact blocker or next command.

## Guardrails

- No force fetch, reset, clean, stash, branch switch, or destructive worktree removal.
- No missing-launcher assumption.
- No multiline interactive compound statement unless enclosed in one outer script block.
- No proof promotion from fetch success or process acknowledgement.
- Generated evidence remains local and untracked.

## Owning files

- `.ai/skills/stale-checkout-exact-head-bootstrap/SKILL.md`
- `Bootstrap-Technician-ExactHead.cmd`
- `scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1`
- `tooling/profiles/windows/harness/stale-checkout-exact-head/manifest.json`

## Deterministic validation

```powershell
python -m unittest tests.test_stale_checkout_exact_head_bootstrap
python -m unittest tests.test_skill_factoring_contracts
pwsh -NoLogo -NoProfile -File scripts/Test-StaleCheckoutExactHeadBootstrap.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1
```

## Forbidden conditions

- Guessing repository path, branch, or SHA.
- Running a launcher absent from the source checkout.
- Splitting an interactive compound statement across submissions.
- Claiming exact-head proof without fresh artifact readback.

## Proof ceiling

This skill proves safe delegation from a stale checkout to the exact commit's repository-owned validator and fresh artifact readback. It does not exceed the delegated exact-head artifact's proof ceiling.
