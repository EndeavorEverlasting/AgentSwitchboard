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
- Success requires the canonical Cursor runtime result, a commit ahead of base, every expected artifact observed, and at least one passed validation.
- Automatic push and merge are always false.

The queue does not authenticate providers, copy credentials, merge branches, deploy software, or treat process exit as delivery proof.

## Prepare a local queue

Copy `tooling/gnhf/prompt-queue.example.json` to an operator-owned local path and replace every placeholder.

Each lane supplies:

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

Planning writes one validated regular request, compiled prompt, and repository-intelligence packet per lane. It does not start an agent or mutate a target repository.

## Execute

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$repo\tooling\gnhf\Invoke-GnhfPromptQueue.ps1" `
  -PlanPath "$output\queue-plan.json"
```

Batches run in dependency order. Independent lanes inside one batch may run concurrently through distinct Cursor agent profiles. Runtime results are normalized beneath the queue output root:

```text
queue-plan.json
lanes/<lane-id>/regular-request.json
lanes/<lane-id>/compiled-gnhf-prompt.json
lanes/<lane-id>/repository-intelligence.json
results/<lane-id>.json
results/<lane-id>.stdout.txt
results/<lane-id>.stderr.txt
queue-summary.json
queue-summary.md
```

Generated queue state belongs outside Git. Review every target branch, worktree, commit, artifact, validation result, and blocker before any separate push or integration action.

## Validation

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Test-GnhfPromptQueueContracts.ps1 `
  -Stage All
```

The deterministic harness creates temporary Git repositories, verifies prompt compilation, distinct concurrent assignments, dependency batches, runtime-result consumption, downstream blocking, and zero target-repository mutation. It does not prove a hosted provider response or live GNHF quality.
