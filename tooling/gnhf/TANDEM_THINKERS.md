# Parallel tandem thinkers

`Start-AgentSwitchboardTandemThinkers.ps1` is the first executable AgentSwitchboard lane for running multiple agents concurrently without creating competing writers.

It deliberately implements the safest useful parallel boundary:

```text
                         +-> Standard read-only thinker --+
bounded objective -------|                                |--> deterministic TANDEM_PLAN.md --> exactly one downstream writer
                         +-> Free read-only thinker -------+
```

Both thinker processes are started before the coordinator waits on either process. A successful receipt must prove their process lifetimes overlapped and that they resolved to distinct thinker routes. If both lanes fall back to the same route, the run fails with `TANDEM_ROUTE_COLLISION` rather than calling duplicated output independent evidence.

## Why this is the parallel boundary

The existing token-saving loop intentionally owns a single writer worktree plus deterministic validation/repair. Parallel writers would create branch/worktree collision and ambiguous mutation ownership. Tandem thinkers use the existing `Start-AgentSwitchboardThinker.ps1` read-only contract instead: Claude plan mode, Codex read-only ephemeral execution, or OpenCode with mutation permissions denied.

The rejoin is deterministic. AgentSwitchboard does not ask a third model to vote or synthesize consensus. It concatenates the separately attributed advisories in a fixed Standard-then-Free order, pins each plan by SHA-256, and appends a builder contract requiring repository evidence to resolve conflicts. Agreement is not promoted to truth.

## Repository-local usage

From a verified AgentSwitchboard checkout:

```powershell
pwsh -NoLogo -NoProfile -File tooling/gnhf/Start-AgentSwitchboardTandemThinkers.ps1 `
  -RepoPath "C:\path\to\target-repo" `
  -PromptPath "C:\path\to\bounded-objective.md"
```

Or on Windows:

```cmd
tooling\gnhf\Start-AgentSwitchboardTandemThinkers.cmd -RepoPath "C:\path\to\target-repo" -PromptPath "C:\path\to\bounded-objective.md"
```

The command writes local evidence under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\tandem-thinkers\<run-id>\
  standard-advisory.md
  free-advisory.md
  TANDEM_PLAN.md
  tandem-receipt.json
```

The default caps are 12,000 characters per lane, 28,000 characters after deterministic rejoin, and 300 seconds per thinker. The parent adds only a bounded 30-second termination margin.

## Receipt contract

`agentswitchboard.tandem-thinkers.v1` records:

- frozen objective SHA-256;
- `start-all-before-wait` launch strategy;
- exactly two advisory lanes;
- observed process-lifetime overlap;
- requested mode and selected thinker route for each lane;
- start/end timestamps, exit/timeout/drain state, plan path/size/SHA-256;
- final rejoined artifact path/SHA-256;
- `mutationAuthority=none-read-only-advisories`;
- `downstreamWriterContract=exactly-one-writer-after-deterministic-rejoin`.

Raw stderr is not copied into the receipt. Each plan remains an attributed local artifact because it is the intended advisory output.

## Failure boundaries

- `TANDEM_LANE_FAILED` — a lane exited nonzero, timed out, failed output drain, lacked route attribution, or produced no plan.
- `TANDEM_PARALLELISM_NOT_OBSERVED` — both lanes completed but their recorded lifetimes did not overlap; the run is not allowed to claim parallel proof.
- `TANDEM_ROUTE_COLLISION` — Standard and Free fell back to the same thinker route. Independent route attribution is required.
- `TANDEM_REJOIN_TOO_LARGE` — combined advisories exceed the configured handoff cap.
- `TANDEM_INTERNAL_FAILURE` — another coordinator failure occurred.

## Writer / validator handoff

`TANDEM_PLAN.md` is a bounded builder input, not a mutation authorization or validation result. The next lane should use the existing single-writer GNHF/token-saving owner so only one branch/worktree mutates. Deterministic repository validators remain authoritative for acceptance; adviser agreement never overrides them.

## Proof ceiling

Hosted tests use two synthetic PowerShell thinker processes that intentionally overlap and emit distinct attributed plans. That proves real process concurrency, receipt/rejoin mechanics, distinct-route enforcement, and the no-writer boundary without spending provider tokens. It does not prove two real provider CLIs are simultaneously authenticated/available on an operator workstation, that their advice is correct, or that a downstream builder/validator successfully delivers a repository change from the tandem packet. Those remain live runtime gates.
