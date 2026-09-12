# Deterministic thinker routing

AgentSwitchboard uses a **one-thinker / one-plan / many-downstream-steps** pattern to reduce repeated model context while preserving deterministic routing. The thinker never owns implementation. It inspects the repository read-only and emits a bounded `SYSTEM_PLAN.md`; builders and validators consume that artifact rather than receiving the full source conversation again.

## Priority

Standard mode is fixed in `thinker-route.policy.json`:

1. Claude Code when installed and runnable;
2. Codex CLI;
3. DeepSeek V4 Pro through OpenCode;
4. OpenCode Muse Spark contributor-free;
5. OpenCode Nemotron 3 Ultra free;
6. OpenCode Big Pickle free fallback.

Free mode never walks the paid/subscription portion of the chain. It starts at Muse, then Nemotron, then Big Pickle. Free-model availability is intentionally re-probed from OpenCode before a run because those catalog entries can be temporary.

Route order is data, not model judgment. A route falls through only on deterministic evidence: missing command, exact-model preflight failure, ineligible DeepSeek rate state, timeout, nonzero exit, empty result, or violation of a transport/plan-size contract. The launcher never asks one model whether another model is smart enough.

## Token-saving contract

- The source objective is read once and capped by `MaxObjectiveChars`.
- The thinker is one-shot. Failed routes get at most one attempt each; there is no self-retry conversation.
- The thinker returns conclusions and exact evidence paths, not hidden reasoning or pasted source/logs.
- The resulting plan is capped by `MaxPlanChars` and identified by SHA-256.
- Runtime evidence stores route/status/digests, not the full prompt or plan body.
- Builders receive `SYSTEM_PLAN.md`, not the original chat transcript.
- Test failures should be reduced to decision-relevant failure envelopes before routing them back to the owning builder; do not replay verbose test logs into the thinker.
- Claude/OpenCode routes use an explicit safe Windows argv ceiling. If a compiled thinker prompt is too large for that transport, those routes are skipped deterministically; Codex remains eligible because its prompt is streamed through stdin.
- Every run uses timestamp plus GUID identity so concurrent launches cannot reuse the same plan/evidence path.

## Read-only enforcement

- Claude runs in noninteractive print mode with `--permission-mode plan` and session persistence disabled.
- Codex runs with `codex exec --sandbox read-only --ephemeral` and writes only its final message to a temporary launcher-owned file.
- OpenCode receives an inline config whose default permission is `deny`; only `read`, `glob`, `grep`, and `lsp` are allowed. Sharing is disabled.
- CLI subprocess creation reuses `Gnhf.Process.ps1`, including its PowerShell/CMD shim dispatch instead of assuming every discovered Windows command is a native executable.

The launcher itself writes the final plan and a compact evidence receipt under the AgentSwitchboard fleet directory. Model processes are not granted a write lane.

## DeepSeek rate-window gate

DeepSeek is not selected merely because OpenCode lists the model. Before any DeepSeek model probe or thinker call, the launcher requires:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\deepseek-usage-windows.json
```

The runtime document uses schema `agentswitchboard.deepseek-usage-window.v1` and must contain current verified evidence. Eligibility is fail-closed:

- `verified` must be `true`;
- `rateClass` must be `standard` or `discounted`;
- `effectiveMultiplier` must be between `0` and `1.0` inclusive;
- `verifiedAt` and `validUntil` must be valid timestamps;
- `validUntil` must still be in the future.

Missing, malformed, unverified, expired, `double-usage`, premium, or multiplier-above-1 states block only the DeepSeek lane and let the deterministic thinker chain continue. Setup installs `deepseek-usage-windows.example.json` as a deliberately **unverified** template; it never invents or silently authorizes a current rate window.

## Install on P-Top

The normal AgentSwitchboard setup now installs the thinker resolver, process helper, policy, DeepSeek schedule template, documentation, and CMD/PowerShell launchers under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet` and runs the thinker contract validator before setup can report success.

From the canonical AgentSwitchboard checkout:

```powershell
.\tooling\gnhf\Setup-AgentSwitchboard.cmd
```

After setup, the installed entrypoint is:

```powershell
$thinker = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\Start-AgentSwitchboardThinker.cmd"
```

Setup does not authenticate providers for you and does not fabricate DeepSeek rate evidence. Each selected thinker still has to be usable through its own CLI/provider session, and OpenCode model routes are re-probed at launch.

## Use

From the AgentSwitchboard checkout on P-Top:

```powershell
$repo = "C:\path\to\target-repo"
$objective = "C:\path\to\bounded-objective.md"

pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Start-AgentSwitchboardThinker.ps1 `
  -RepoPath $repo `
  -PromptPath $objective `
  -Mode Auto
```

Or use the installed control-plane launcher after setup:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\Start-AgentSwitchboardThinker.cmd" `
  -RepoPath $repo `
  -PromptPath $objective `
  -Mode Auto
```

Set free mode explicitly:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\Start-AgentSwitchboardThinker.cmd" `
  -RepoPath $repo `
  -PromptPath $objective `
  -Mode Free
```

Or make automatic routing start from the free chain for the current PowerShell process:

```powershell
$env:AGENT_SWITCHBOARD_FREE_MODE = "1"
```

The launcher prints the selected thinker, plan path, and evidence path. By default plans are stored under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\plans`; route receipts live under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\thinker-routes`.

## Downstream contract

The next builder receives the generated plan path plus its own bounded execution controls. Do not pass the thinker transcript. Keep implementation, validation, and failure-repair contexts separate. AxTask remains the deterministic validation authority and AgentSwitchboard remains the router; neither should ask the thinker to re-read ordinary build/test chatter.

## Proof ceiling

Repository contracts prove deterministic ordering, free-mode exclusion, DeepSeek rate eligibility rules, read-only launcher flags/configuration, Windows shim-safe dispatch, collision-resistant artifact identity, setup/install wiring, context/output caps, and compact evidence behavior. They do not prove that P-Top currently has authenticated Claude, Codex, DeepSeek, or OpenCode sessions, nor that a temporary free model remains available after the last model preflight, nor that a current verified DeepSeek usage schedule has been installed.
