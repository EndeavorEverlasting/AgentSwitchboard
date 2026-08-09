# First Mate operational harness status

Status: **Windows Python child-process portability repaired in source; exact-head hosted and physical reproof required**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic and requires `local-only` with `yolo_enabled: false`.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is independent from Android profile readiness.
- Windows has a native harness front door: `Test-AgentSwitchboard-FirstMate-Harness.ps1` plus a location-independent CMD wrapper.
- Windows contract/report/route modes do not require Bash or WSL.
- GitHub origin normalization is owned by portable Python and reused by the Linux/WSL probe.
- Platform-neutral Python tests that launch repository Python tools now reuse `sys.executable` rather than assuming a `python3` alias exists on Windows.
- The WSL bridge no longer depends on `wslpath`, a hardcoded `/mnt/c`, or Linux Git running inside a Windows-created linked worktree.
- Windows paths cross into WSL through `WSLENV /p`, the bridge binds to canonical Ubuntu, and WSL stdout/stderr are captured separately.
- Bootstrap stdout, WSL stderr, the WSL workspace path, exact head, floor evidence, report, and route are durable evidence.

## Broken or blocked

- Physical failure 1: the original bridge used `wslpath` and produced no usable stdout.
- Physical failure 2: WSL could not execute the visibility gate inside a Windows-created detached linked worktree.
- Physical failure 3: the operator's Windows-native `python tests/test_firstmate_integration_contract.py` spawned bare Bash (`bash`) and passed it a `C:\\...` path. The Bash subprocess failed before the intended WSL runtime floor.
- Physical failure 4: at exact head `cf179b881717af22e55d35d12f6a406c87c22c6a`, the Windows-native front door successfully ran the 11-test integration contract, then `tests/test_firstmate_operational_harness.py` launched selector/report-builder children with literal `python3`; Windows returned exit `9009` because that alias was unavailable. Six child-process tests errored and the expected-write-error test returned `9009` instead of `2`.
- Failure 4 is a harness interpreter-routing defect. The parent `python.exe` was already running, so it does not prove Python itself, Ubuntu, WSL, tmux, or First Mate failed.
- No live bounded First Mate crew dispatch has completed yet.
- Herdr automatic selection remains blocked by its separate lane.
- Native-Windows First Mate runtime behavior remains unverified.

## Missing

- Exact-head hosted Windows/Linux validation of the `sys.executable` portability repair.
- One successful physical Windows `contract` run through `Test-AgentSwitchboard-FirstMate-Harness.ps1` after this repair, including the operational completeness suite and final parent receipt.
- One successful exact-head physical `runtime-floor` run using canonical Ubuntu and the WSL-owned standalone clone.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees and observable useful completion.
- Captured worker identity, branch/worktree ownership, validator receipts, and convergence evidence.
- Any evidence sufficient to replace tmux with Herdr for a specific profile.

## Safe next state

After exact-head hosted CI passes, fetch the repair branch into an isolated Windows worktree and run the registered PowerShell-native harness in `contract` mode. Completion requires the operational completeness suite to pass without exit `9009`, the child bridge ContractOnly receipt to return, the parent to emit `[PASS] FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS`, and the canonical operator report to generate. Only after that physical contract gate passes should the same front door advance to `runtime-floor`; only after that floor passes should a real tmux-backed First Mate local-only task be used as the productivity proof.

## Proof ceiling

This report describes tracked harness state. Hosted CI can prove the interpreter-continuity contract and Windows-native front door. It cannot prove the physical laptop until the exact repair head executes there, and it cannot prove productive First Mate crew work until a real bounded task completes with runtime evidence.
