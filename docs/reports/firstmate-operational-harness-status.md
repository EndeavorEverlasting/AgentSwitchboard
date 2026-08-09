# First Mate operational harness status

Status: **contract repair in progress; Windows-native validation added; physical runtime reproof still required**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic and requires `local-only` with `yolo_enabled: false`.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is independent from Android profile readiness.
- Windows now has a native harness front door: `Test-AgentSwitchboard-FirstMate-Harness.ps1` plus a location-independent CMD wrapper.
- Windows contract/report/route modes do not require Bash or WSL.
- GitHub origin normalization is owned by portable Python and reused by the Linux/WSL probe.
- The WSL bridge no longer depends on `wslpath`, a hardcoded `/mnt/c`, or Linux Git running inside a Windows-created linked worktree.
- Windows paths cross into WSL through `WSLENV /p`, the bridge binds to canonical Ubuntu, and WSL stdout/stderr are captured separately.
- Bootstrap stdout, WSL stderr, the WSL workspace path, exact head, floor evidence, report, and route are durable evidence.

## Broken or blocked

- Physical failure 1: the original bridge used `wslpath` and produced no usable stdout.
- Physical failure 2: WSL could not execute the visibility gate inside a Windows-created detached linked worktree.
- Physical failure 3: the operator's Windows-native `python tests/test_firstmate_integration_contract.py` spawned bare Bash (`bash`) and passed it a `C:\\...` path. The Bash subprocess failed before the intended WSL runtime floor.
- Failure 3 is a harness portability defect. It does not prove Ubuntu, WSL, tmux, or First Mate failed.
- The new Windows-native harness and portable origin-normalization repair still require exact-head physical-laptop reproof after hosted CI.
- No live bounded First Mate crew dispatch has completed yet.
- Herdr automatic selection remains blocked by its separate lane.
- Native-Windows First Mate runtime behavior remains unverified.

## Missing

- Hosted Windows/Linux validation of the Windows-native portability repair at the exact repair head.
- One successful physical Windows `contract` run through `Test-AgentSwitchboard-FirstMate-Harness.ps1` with no Bash/WSL dependency.
- One successful exact-head physical `runtime-floor` run using canonical Ubuntu and the WSL-owned standalone clone.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees and observable useful completion.
- Captured worker identity, branch/worktree ownership, validator receipts, and convergence evidence.
- Any evidence sufficient to replace tmux with Herdr for a specific profile.

## Safe next state

After hosted CI passes, fetch the exact portability-repair head into an isolated Windows worktree and run the registered PowerShell-native harness in `contract` mode. That is the immediate regression proof for the failure observed on the laptop. Only after it passes should the same front door advance to `runtime-floor`; only after that floor passes should a real tmux-backed First Mate local-only task be used as the productivity proof.

## Proof ceiling

This report describes tracked harness state. Hosted CI can prove the portability contract and Windows-native front door. It cannot prove the physical laptop until that exact head executes there, and it cannot prove productive First Mate crew work until a real bounded task completes with runtime evidence.
