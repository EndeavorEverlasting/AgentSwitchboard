# First Mate operational harness status

Status: **Windows Python child-process portability hosted-green; physical laptop reproof required**

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
- Platform-neutral Python tests that launch repository Python tools reuse `sys.executable` rather than assuming a `python3` alias exists on Windows.
- Hosted Windows validation of the interpreter-continuity repair passes the integration contract, operational completeness suite, portability suite, bridge contract, parent Windows harness receipt, repository foundation, and diff hygiene.
- Hosted Linux validation passes the same portable contracts plus Linux/WSL shell parsing, report generation, repository foundation, and diff hygiene.
- The repository-wide documentation/governance contract passes on both Windows and Linux for this repair.
- The WSL bridge no longer depends on `wslpath`, a hardcoded `/mnt/c`, or Linux Git running inside a Windows-created linked worktree.
- Windows paths cross into WSL through `WSLENV /p`, the bridge binds to canonical Ubuntu, and WSL stdout/stderr are captured separately.
- Bootstrap stdout, WSL stderr, the WSL workspace path, exact head, floor evidence, report, and route are durable evidence.

## Broken or blocked

- Physical failure 1: the original bridge used `wslpath` and produced no usable stdout.
- Physical failure 2: WSL could not execute the visibility gate inside a Windows-created detached linked worktree.
- Physical failure 3: the operator's Windows-native `python tests/test_firstmate_integration_contract.py` spawned bare Bash (`bash`) and passed it a `C:\\...` path. The Bash subprocess failed before the intended WSL runtime floor.
- Physical failure 4: at exact head `cf179b881717af22e55d35d12f6a406c87c22c6a`, the Windows-native front door successfully ran the 11-test integration contract, then `tests/test_firstmate_operational_harness.py` launched selector/report-builder children with literal `python3`; Windows returned exit `9009` because that alias was unavailable. Six child-process tests errored and the expected-write-error test returned `9009` instead of `2`.
- Failure 4 is repaired in the harness by preserving interpreter identity with `sys.executable`, and the repair is hosted-green. It still requires exact-head physical-laptop acceptance.
- No live bounded First Mate crew dispatch has completed yet.
- Herdr automatic selection remains blocked by its separate lane.
- Native-Windows First Mate runtime behavior remains unverified.

## Missing

- One successful physical Windows `contract` run through `Test-AgentSwitchboard-FirstMate-Harness.ps1` after this repair, including the operational completeness suite and final parent receipt.
- One canonical operator report generated on the physical laptop from that successful contract run.
- One successful exact-head physical `runtime-floor` run using canonical Ubuntu and the WSL-owned standalone clone.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees and observable useful completion.
- Captured worker identity, branch/worktree ownership, validator receipts, and convergence evidence.
- Any evidence sufficient to replace tmux with Herdr for a specific profile.

## Safe next state

Fetch the exact repair head into an isolated Windows worktree and run the registered PowerShell-native harness in `contract` mode. Completion requires the operational completeness suite to pass without exit `9009`, the child bridge ContractOnly receipt to return, the parent to emit `[PASS] FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS`, `git diff --check` and clean-worktree gates to pass, and the canonical operator report to generate. Only after that physical contract gate passes should the same front door advance to `runtime-floor`; only after that floor passes should a real tmux-backed First Mate local-only task be used as the productivity proof.

## Proof ceiling

Hosted validation proves the interpreter-continuity contract and Windows-native harness behavior in hosted Windows/Linux environments. It does not prove the physical laptop until the exact current repair head executes there, and it cannot prove productive First Mate crew work until a real bounded task completes with runtime evidence.
