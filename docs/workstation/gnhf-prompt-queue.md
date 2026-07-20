# Multi-prompt GNHF queue orchestration

AgentSwitchboard can compile several prompt artifacts into one dependency-aware local queue and launch each lane through the existing Cursor runtime.

## Boundaries

The queue owns orchestration, not repository policy.

- One clean, attached repository path per lane.
- No two lanes in one queue may share a repository path.
- Concurrent lanes receive distinct enabled agent profiles.
- A canonical `gnhf` command keeps its explicit `--agent`; the queue must contain a matching unused profile for that batch.
- Sectioned prompts and `regular-sprint-request` JSON receive the assigned profile's GNHF agent.
- Dependencies are converted into ordered batches. A failed or blocked lane prevents its dependents from starting.
- Every enabled application must be assigned to a lane and must register at least one enabled trigger.
- Application triggers are evaluated during planning, before any Cursor process starts.
- Success requires the canonical Cursor runtime result, a commit ahead of base, every expected artifact observed, and at least one passed validation.
- Automatic push and merge are always false.

The queue does not authenticate providers, copy credentials, merge branches, deploy software, or treat process exit as delivery proof. App-owned trigger doctrine remains authoritative; the queue registry is an orchestration-time adapter that makes those conditions visible before analysis completes.

## Application trigger registry

Each local queue declares `applications`. A lane references exactly one application with `applicationId`.

Supported deterministic trigger kinds are:

- `always` — register an unconditional awareness item;
- `repository-path-exists` — flag when one exact repository-relative path exists;
- `repository-text-contains` — perform a bounded literal-text check against one exact repository-relative file;
- `prompt-text-contains` — perform a literal-text check against the source prompt.

Triggers also declare `info`, `warning`, or `critical` severity. Paths cannot be rooted, contain traversal, or use wildcards. Repository text reads are capped at 1 MiB. Trigger checks never use regular expressions supplied by the manifest and never mutate the target repository.

During planning AgentSwitchboard writes, hashes, and binds this file for every lane:

```text
lanes/<lane-id>/trigger-flags.json
```

The compiled prompt receives the exact snapshot path and SHA-256, adds the snapshot to `readFirst`, and requires the agent to reconcile every active flag before completing repository analysis or producing an awareness assessment. The executor verifies the snapshot, hash, application identity, counts, and compiled instruction before `PlanOnly` succeeds or a Cursor process starts.

## Prepare a local queue

Copy `tooling/gnhf/prompt-queue.example.json` to an operator-owned local path and replace every placeholder.

Each lane supplies:

- one application registry ID;
- one prompt path;
- one repository path;
- exact expected artifact paths;
- dependency lane IDs;
- execution intent and proof level;
- a bounded timeout.

`repositoryName`, `repositoryRemote`, `baseBranch`, and `pullRequestNumber` may be null. Normal planning derives them from Git and uses `gh pr list` when available. A declared PR number is verified rather than trusted.

## Compile and inspect

```powershell
$repo = "C:\path\to\AgentSwitchboard"
$queue = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfQueue\queue.json"
$output = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfQueue\runs\queue-001"

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$repo\tooling\gnhf\New-GnhfPromptQueuePlan.ps1" `
  -QueuePath $queue `
  -OutputRoot $output

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$repo\tooling\gnhf\Invoke-GnhfPromptQueue.ps1" `
  -PlanPath "$output\queue-plan.json" `
  -PlanOnly
```

Planning writes one trigger snapshot, validated regular request, compiled prompt, and repository-intelligence packet per lane. It does not start an agent or mutate a target repository.

## Execute

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$repo\tooling\gnhf\Invoke-GnhfPromptQueue.ps1" `
  -PlanPath "$output\queue-plan.json"
```

Batches run in dependency order. Independent lanes inside one batch may run concurrently through distinct Cursor agent profiles. Runtime results are normalized beneath the queue output root:

```text
queue-plan.json
lanes/<lane-id>/trigger-flags.json
lanes/<lane-id>/regular-request.json
lanes/<lane-id>/compiled-gnhf-prompt.json
lanes/<lane-id>/repository-intelligence.json
results/<lane-id>.json
results/<lane-id>.stdout.txt
results/<lane-id>.stderr.txt
queue-summary.json
queue-summary.md
```

Lane results retain application identity, trigger counts, snapshot path and hash, and whether the awareness gate was satisfied. Generated queue state belongs outside Git. Review every target branch, worktree, commit, artifact, validation result, trigger flag, and blocker before any separate push or integration action.

## Validation

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Test-GnhfPromptContracts.ps1
```

The canonical validator runs the queue suite and focused awareness-trigger suite. The deterministic harness creates temporary Git repositories and proves prompt compilation, distinct concurrent assignments, dependency batches, trigger evaluation, snapshot hashing, prompt injection, runtime handoff, modified-evidence rejection, downstream blocking, and zero target-repository mutation. It does not prove a hosted provider response or live GNHF quality.
