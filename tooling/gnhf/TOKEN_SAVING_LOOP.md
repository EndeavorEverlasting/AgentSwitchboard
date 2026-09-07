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

## Emergency free mode

When premium token headroom is low, use the dedicated emergency launcher instead of ordinary `Auto` routing:

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

& "$root\Start-AgentSwitchboardEmergencyFree.cmd" `
  -RepoPath "C:\path\to\target-repo" `
  -ObjectivePath "C:\path\to\bounded-objective.md" `
  -ValidationCommand 'pwsh -NoLogo -NoProfile -File .\tooling\validate.ps1'
```

The emergency launcher:

- uses only the canonical free thinker chain;
- probes OpenCode's current model catalog and selects the first exact model in that free chain that is actually listed;
- pins that verified free model for the OpenCode builder instead of trusting the operator's default model;
- allows at most 2 initial builder iterations, 1 repair cycle, 50,000 tokens per builder run, and a 3,000-character failure excerpt;
- fails closed when no verified free OpenCode model is available rather than silently spending paid-provider tokens;
- restores the previous `AGENT_SWITCHBOARD_FREE_MODE` and `OPENCODE_CONFIG_CONTENT` process environment after the run.

For an immediate process-level guard before launching any thinker, set:

```powershell
$env:AGENT_SWITCHBOARD_FREE_MODE = "1"
```

That setting affects automatic thinker routing only. Use `Start-AgentSwitchboardEmergencyFree.cmd` when the builder must also be pinned to a verified free OpenCode model.

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

## Normal bounded mode

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

Use `-ThinkerMode Free` to force only the thinker onto the free chain already defined by the thinker policy. Use an explicit builder only when the target sprint requires it; otherwise deterministic readiness chooses the first eligible route. For low-quota operation, prefer the emergency launcher because it also pins the builder model and lowers the hard bounds.
