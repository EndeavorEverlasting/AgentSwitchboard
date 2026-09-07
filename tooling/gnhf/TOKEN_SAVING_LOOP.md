# Deterministic token-saving loop

This workflow turns the video-derived planner/builder/test pattern into an AgentSwitchboard control-plane contract. Its goal is **context isolation**, not parallelism:

```text
bounded objective
  -> one read-only thinker
  -> SYSTEM_PLAN.md
  -> one bounded builder in an isolated gnhf/* worktree
  -> deterministic validator
       PASS -> stop
       FAIL -> bounded failure envelope -> same builder worktree -> validator again
```

The thinker never sees ordinary build/test chatter after it emits the plan. Failed validation never causes a new planning conversation. The builder receives only the current repository state plus a bounded failure excerpt and evidence digest.

## Deterministic ownership

- Thinker selection is owned by `thinker-route.policy.json`.
- Builder `Auto` priority is fixed in `TokenSaving.Route.ps1`: AGY, then OpenCode, then Hermes.
- Validation authority is external and opaque to AgentSwitchboard. Supply the repository's canonical AxTask/validator command through `-ValidationCommand`; AgentSwitchboard runs it but does not redefine its semantics.
- The initial builder always uses the existing isolated GNHF worktree path.
- Repairs may use GNHF current-branch mode only inside an existing clean `gnhf/*` worktree.
- Push, merge, deployment, and default-branch mutation are outside this loop.

## Token controls

- The thinker consumes the bounded objective once and produces the bounded `SYSTEM_PLAN.md` once.
- The original conversation is never forwarded to the builder.
- Full validator output is written to a local evidence log, not sent back to a model.
- The repair model receives at most `MaxFailureChars` from the tail of validator output plus exit/timing/head/digest metadata.
- Every model run has GNHF iteration and token caps.
- Repair cycles are explicitly capped.

## Failure behavior

The loop fails closed when it cannot identify exactly one newly created GNHF worktree. It also stops after the configured repair cap rather than entering an open-ended probabilistic retry loop.

Each run records a compact receipt beneath:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\token-saving-loop\<run-id>\
```

The receipt stores plan and validator identities by SHA-256, builder routing evidence, worktree identity, validation results, repair prompt paths, and the final status. The validation command itself is not copied into the receipt.

## Example

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

& "$root\Start-AgentSwitchboardTokenSavingLoop.cmd" `
  -RepoPath "C:\path\to\target-repo" `
  -ObjectivePath "C:\path\to\bounded-objective.md" `
  -ThinkerMode Auto `
  -BuilderAgent Auto `
  -ValidationCommand 'pwsh -NoLogo -NoProfile -File .\tooling\validate.ps1' `
  -MaxRepairCycles 2
```

Use `-ThinkerMode Free` to force the thinker onto the free chain already defined by the thinker policy. Use an explicit builder only when the target sprint requires it; otherwise deterministic readiness chooses the first eligible route.
