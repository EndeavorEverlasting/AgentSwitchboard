# GNHF Bimodal Model and Token Scheduler

The scheduler runs one bounded sprint across a sequence of ready agent/model profiles while preserving one scheduler-owned integration branch.

It does not put multiple agents on the same files concurrently. One GNHF segment exits before another profile is selected.

## Modes

### `maximize-sprint-completion` — default

This is the normal overnight mode.

- Select the highest completion-priority eligible profile.
- Continue using that profile while it remains ready, authenticated, and has usable tokens.
- Switch only after quota or token exhaustion, authentication failure, a permanent provider/model error, a bounded timeout, or another explicit availability failure.
- Give each segment the largest configured bounded token allowance.
- Stop when the objective condition is observed, every profile is unavailable, the wall-time or segment cap is reached, or the no-progress threshold is reached.

This mode intentionally prioritizes finishing the sprint over preserving daytime quota.

### `maximize-token-efficiency` — secondary

This mode preserves usage for later interactive work.

- Require a known and fresh usage snapshot. Unknown or stale token availability is not treated as safe.
- Protect the larger of each profile's fixed reserve and configured reserve percentage.
- Exclude a profile when its usable amount above reserve is smaller than its minimum segment allowance.
- Rotate among eligible profiles instead of draining one profile continuously.
- Cap each segment to a configured share of the profile's usable, above-reserve amount.
- Stop before all profiles are drained, leaving the declared reserves untouched when the supplied usage information is accurate.

This mode cannot manufacture quota or infer exact provider balances. Its guarantee is only as current and accurate as the supplied usage snapshot.

## Default completion hierarchy

The example manifest codifies this completion-first order:

1. **DeepSeek** through the OpenCode adapter.
2. **OpenCode** using its separately configured fallback model.
3. **Anti-Gravity / AGY** when its readiness state contains a verified ACP adapter.
4. Other eligible profiles, currently Copilot followed by Goose.

The hierarchy is expressed through `completionPriority`; smaller numbers run first. It applies only to `maximize-sprint-completion`. The efficiency mode continues to use reserve eligibility and `efficiencyPriority` rather than blindly following this order.

The example uses placeholder model identifiers. Replace them with model IDs supported by the installed agent configuration. DeepSeek is a model/provider preference, not a new executable: the primary profile launches the existing OpenCode adapter with DeepSeek routing context.

AGY is disabled in the example by default. Its `agentSpec` is blank so, after the operator explicitly enables the profile, `Start-GnhfSprint.ps1` uses the exact ACP adapter already verified and stored by AgentSwitchboard readiness setup. The scheduler does not guess Anti-Gravity server arguments. If AGY is enabled before readiness succeeds, the launcher emits explicit not-ready evidence; the outcome classifier treats that as a permanent profile failure so the scheduler can block that profile and continue to the next eligible fallback.

## Ownership boundary

The scheduler owns:

- deterministic selection between declared profiles;
- bounded GNHF segment launch and termination;
- one scheduler-owned Git worktree and branch;
- log-informed handoff between sequential segments;
- routing-decision, segment, event, and run artifacts;
- stop and switch classification;
- fixed and percentage reserve enforcement;
- rejecting stale or implausibly future usage snapshots;
- preserving the distinction between a requested model and acknowledged activation evidence.

A provider-specific usage collector or concurrent token-management sprint owns:

- logging into providers;
- querying or estimating provider/model availability;
- interpreting provider reset windows;
- producing the usage snapshot;
- configuring the exact model inside an agent wrapper when the CLI lacks a universal GNHF model flag;
- writing model acknowledgement evidence only after the wrapper or provider actually acknowledges the requested model.

The scheduler consumes that evidence and never writes credentials or provider account state back to it.

## Usage snapshot

The input contract is:

```text
schemas/gnhf-usage-snapshot.schema.json
```

A minimal DeepSeek-first profile record looks like this **JSON FILE CONTENT**:

```json
{
  "profileId": "deepseek-primary",
  "agent": "opencode",
  "model": "deepseek/configured-primary-model",
  "ready": true,
  "authenticated": true,
  "tokensRemaining": 900000,
  "tokenCapacity": 1000000,
  "resetAt": "2026-07-16T00:00:00Z",
  "blockedReason": null,
  "evidence": "provider-specific collector output"
}
```

Do not put provider keys, bearer tokens, cookies, refresh tokens, or full account records in this file.

The scheduler hashes the snapshot used for each routing decision. It locally subtracts token totals that GNHF logs expose, but it reloads the external snapshot before every decision so a concurrent collector may refresh it atomically.

The example policy includes:

```json
{
  "maxUsageSnapshotAgeMinutes": 30,
  "maxUsageSnapshotFutureSkewMinutes": 5
}
```

A snapshot older than `maxUsageSnapshotAgeMinutes` is rejected with `usage-snapshot-stale`. A timestamp farther into the future than the allowed skew is rejected with `usage-snapshot-from-future`. In either case, every profile is made ineligible before routing. This prevents an old high balance from defeating reserve preservation.

Fixtures use historical timestamps by design. Contract and plan harnesses replace `capturedAt` with a current test timestamp before testing normal routing, then separately prove stale evidence is blocked.

## Model profiles

A profile combines:

- an AgentSwitchboard profile ID;
- a GNHF agent name;
- an exact GNHF agent specification, or a blank override that reuses the verified readiness-state adapter;
- a model identifier for evidence and wrapper context;
- completion and efficiency priorities;
- reserve and segment limits.

`Start-GnhfSprint.ps1` provides these environment variables to the selected agent process:

```text
AGENTSWITCHBOARD_MODEL_PROFILE
AGENTSWITCHBOARD_MODEL
AGENTSWITCHBOARD_ROUTING_DECISION
AGENTSWITCHBOARD_ROUTING_DECISION_HASH
AGENTSWITCHBOARD_MODEL_ACK_PATH
```

The first three identify the requested profile, requested model, and routing artifact. The hash binds acknowledgement evidence to the exact routing decision. `AGENTSWITCHBOARD_MODEL_ACK_PATH` is a unique local path where a compatible wrapper may atomically write:

```text
schemas/gnhf-model-activation.schema.json
```

A valid acknowledgement must match the expected profile, agent, requested model, and routing-decision hash. The launcher summary records one of these states:

- `not-requested` — no model was requested;
- `requested-only` — a model was requested, but no valid acknowledgement was written;
- `acknowledged` — the wrapper or CLI explicitly acknowledged the exact requested model;
- `observed-response` — provider response evidence identified the exact requested model;
- `rejected` — the wrapper explicitly rejected the requested model;
- `invalid-acknowledgement` — an acknowledgement file existed but did not match the request contract.

A routing decision or environment variable alone remains `requested-only`. The launcher never upgrades it to `acknowledged` merely because OpenCode was selected.

The acknowledgement file must contain bounded evidence text, not secrets, raw headers, bearer tokens, cookies, or full provider responses.

## Install or repair

### WINDOWS POWERSHELL 7

Run plan mode first:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Install-GnhfBimodalScheduler.ps1
```

Install the scheduler and create an active manifest by supplying local paths:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Install-GnhfBimodalScheduler.ps1 `
  -DefaultRepoPath "C:\path\to\clean\target-repository" `
  -ObjectivePath "C:\path\to\bounded-objective.md" `
  -UsageSnapshotPath "C:\path\to\gnhf-usage.json" `
  -Apply
```

An existing customized `gnhf-bimodal.json` is preserved. `-ResetManifest` is required to replace it and requires all three local paths.

Before enabling live execution, replace the placeholder model IDs and leave `agy-tertiary` disabled until AgentSwitchboard reports AGY ready with a verified ACP command.

## Plan a run

### WINDOWS POWERSHELL 7

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$root\Invoke-GnhfBimodalScheduler.ps1" `
  -ConfigPath "$root\gnhf-bimodal.json" `
  -PlanOnly
```

Override the configured mode without editing the file:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$root\Invoke-GnhfBimodalScheduler.ps1" `
  -ConfigPath "$root\gnhf-bimodal.json" `
  -Mode maximize-token-efficiency `
  -PlanOnly
```

Plan mode validates the repository and evidence, selects a profile, calculates its segment budget, and writes a routing-decision artifact. It does not create a target-repository worktree or launch GNHF. A stale usage snapshot produces a no-selection routing decision rather than silently using old quota evidence.

## Run

### WINDOWS POWERSHELL 7

Use the installed launcher:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\Start-GnhfBimodal.cmd"
```

Or invoke the scheduler directly:

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$root\Invoke-GnhfBimodalScheduler.ps1" `
  -ConfigPath "$root\gnhf-bimodal.json"
```

The target checkout must be clean and on a named non-GNHF branch. The scheduler creates one branch under:

```text
switchboard/gnhf-*
```

and one separate worktree. Every GNHF segment uses `--current-branch` inside that scheduler-owned worktree, so commits from different profiles converge sequentially on the same reviewable branch.

## Log-informed bounded tasks

The primary objective remains stable in `stable-objective.md`.

Before every segment, the scheduler rewrites `router-handoff.md` with:

- selected profile, agent, and model;
- current segment budget;
- routing reason;
- recent segment statuses;
- commit and estimated-token evidence;
- instructions to inspect current branch state and GNHF logs before choosing one bounded task.

The handoff does not replace the original objective. It prevents a new model from restarting completed work and lets the next segment react to prior logs and commits.

## Stop and switch conditions

The scheduler closes the bounded GNHF child process when the child exits normally or kills its process tree after the configured segment timeout.

It switches profiles after evidence of:

- token or quota exhaustion;
- authentication blockage;
- permanent provider/model failure;
- a fleet readiness failure such as AGY not ready;
- bounded timeout;
- profile unavailability;
- a generic failed segment when another eligible profile exists.

It stops the whole scheduler after:

- an observed satisfied stop condition;
- no eligible profiles;
- all profiles reaching efficiency reserves;
- stale or future-dated usage evidence;
- the maximum wall time;
- the maximum segment count;
- consecutive no-progress segments;
- an internal scheduler failure.

Printing the configured stop text is not completion proof. The classifier requires language indicating the condition was actually reached or satisfied and rejects negated evidence such as `not satisfied`.

## Evidence

Each run writes under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\bimodal-runs\<run-id>\
  stable-objective.md
  router-handoff.md
  events.jsonl
  bimodal-run.json
  decisions\routing-decision-*.json
  segments\segment-*.json
```

The routing decision records the usage snapshot SHA-256 hash, candidate eligibility, selected profile, requested model, reason, and token budget.

Each launcher run writes under the installed `logs` directory. Its `launcher-summary.json` records the routing-decision hash and a `modelActivation` object. Compatible wrappers write `model-activation.json` at the path supplied by `AGENTSWITCHBOARD_MODEL_ACK_PATH`. Custom ACP command details remain redacted from summaries.

## Safety and proof ceiling

- No automatic provider authentication.
- No secret collection.
- No automatic push, merge, deployment, or default-branch write.
- One isolated scheduler branch and worktree.
- Every wait, segment, token allowance, and overall run is bounded.
- A profile/model selection record proves only the router's request.
- `acknowledged` proves a matching wrapper or CLI acknowledgement, not necessarily a completed provider response.
- `observed-response` requires the wrapper to identify the requested model from provider response evidence.
- Invalid or mismatched acknowledgements are retained as `invalid-acknowledgement`, not promoted.
- Log classification proves only the matched evidence. It does not prove code correctness.
- Live cross-model switching, real quota preservation, and completed overnight sprint behavior still require controlled runtime proof with actual provider accounts.
