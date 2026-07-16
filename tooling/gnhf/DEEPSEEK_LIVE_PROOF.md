# DeepSeek + GNHF Controlled Live Proof

This lane performs a real, paid DeepSeek provider response through OpenCode and then launches one bounded GNHF segment against a disposable Git repository.

## Proof boundary

The script distinguishes these levels:

1. `preflight-only`
2. `live-provider-response-observed`
3. `live-gnhf-behavior-observed`

A successful OpenCode command or GNHF launcher exit is not enough. The highest level requires:

- an authenticated DeepSeek provider reported by OpenCode;
- the exact requested model present in `opencode models deepseek --refresh`;
- a controlled live response marker returned under explicit `--model` selection;
- a bounded GNHF worktree created from a disposable repository;
- `deepseek-live-proof.json` observed in that exact worktree;
- the artifact included in the worktree's `HEAD` commit;
- local evidence and launcher logs collected.

## Safety

- The DeepSeek key remains in OpenCode's own credential store.
- The script never reads, prints, copies, or commits the key.
- The target repository is generated under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\live-proofs`.
- No personal repository, save, account, or production data is modified.
- No branch is pushed or merged.
- OpenCode sharing is disabled for the proof.
- The direct provider probe is bounded to 180 seconds.
- The GNHF process tree is bounded and terminated after the configured timeout.
- Failure evidence is preserved for diagnosis.

## Authenticate once

Use OpenCode's own credential flow:

```powershell
opencode auth login --provider deepseek
```

Do not paste the key into a command line, chat, repository file, or environment file.

Confirm the model registry:

```powershell
opencode models deepseek --refresh
```

DeepSeek's current API model is `deepseek-v4-pro`; OpenCode addresses it as `deepseek/deepseek-v4-pro`.

## Run

From the AgentSwitchboard checkout containing this lane:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Start-DeepSeekGnhfLiveProof.ps1
```

Or double-click:

```text
tooling\gnhf\Start-DeepSeekGnhfLiveProof.cmd
```

Optional bounds:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Start-DeepSeekGnhfLiveProof.ps1 `
  -ModelId deepseek/deepseek-v4-pro `
  -MaxIterations 2 `
  -MaxTokens 60000 `
  -TimeoutMinutes 20
```

## Evidence

Each invocation writes a new directory under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\live-proofs\deepseek-<timestamp>\
```

The key artifacts are:

- `deepseek-live-proof-summary.json`
- `opencode-auth.txt`
- `opencode-models.txt`
- `opencode-smoke.jsonl`
- `opencode-smoke.stderr.txt`
- `model-activation-observed.json`
- `gnhf-console.txt`
- the exact GNHF execution worktree path recorded in the summary
- `deepseek-live-proof.json` in the execution worktree

The proof directory is local runtime evidence and must not be committed.
