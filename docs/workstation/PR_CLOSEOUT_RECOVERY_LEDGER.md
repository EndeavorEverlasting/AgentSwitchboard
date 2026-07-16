# PR closeout failed-run recovery ledger

This ledger records the failed AgentSwitchboard PR-closeout run `20260716-050644` without committing machine-local prompts, transcripts, credentials, or time-sensitive quota-reset estimates. The evidence was inspected on 2026-07-16 and left in place.

## Repository evidence

| Item | Observed state |
| --- | --- |
| Operations branch | `ops/pr-closeout-batch-20260716-050644` |
| Operations base | `1c559d6930be3a28321021eea04bcd8f7e323ecb` |
| Operations worktree | Present and clean at the base commit |
| Generated branches | `gnhf/execute-the-pr-close-8930bc` and `gnhf/execute-the-pr-close-8930bc-1` |
| Generated branch proof | Both branches are zero commits ahead of the operations base |
| Generated worktree container | Present but empty at inspection time; the two previously reported child paths are absent |
| `PR_CLOSEOUT_REPORT.md` | Not created |

No branch, worktree, log, or local evidence file was deleted during recovery inspection. There is no generated commit to cherry-pick.

## Launcher evidence

The machine-readable summaries remain under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\`. Only bounded fields are transcribed here.

| Route | Started | Completed | Preflight | Commit proof | Outcome | Exit |
| --- | --- | --- | --- | --- | --- | --- |
| `agy-natural-free` | 05:06:47 | 05:10:09 | `quota-exhausted` | 0 commits | `no-commit-proof` | 79 |
| `goose-free-provider` | 05:10:10 | 05:13:31 | not applicable | 0 commits | `no-commit-proof` | 79 |

The AGY status record classified quota exhaustion and recorded preflight exit code 1. The transcript then contained both "preflight stopped before GNHF" and "GNHF returned exit code 0 without producing a new commit." This proves the launcher fell through after a correct preflight classification. Goose also returned without commit proof, so its process result did not satisfy the sprint contract.

## Root cause and disposition

`Start-GnhfSprint.ps1` initialized its launcher exit code to 1 and later used `exitCode -eq 1` to decide whether GNHF should start. AGY also returned 1 for the quota response. One value therefore meant both "not started" and "preflight failed," allowing the warned failure to enter GNHF.

The repair replaces that implicit sentinel with an explicit launch gate, normalizes typed preflight exit codes, records whether GNHF was invoked, and adds a temporary-repository runtime regression. A routed success still requires a new GNHF branch commit ahead of the base; exit code zero alone remains insufficient.

## Recovery gate

Do not rerun the PR-closeout batch from this evidence branch. A future controlled run must start from a clean, current PR graph and must first pass:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\tests\Test-GnhfFailFastRuntime.ps1
```

This ledger does not claim a live provider fallback, PR closure, fresh-machine behavior, or cleanup of the preserved operations evidence.
