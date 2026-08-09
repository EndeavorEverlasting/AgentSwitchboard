# First Mate operational harness status

Status: **contract-ready; WSL distribution-selection repair committed; physical runtime reproof required**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic and requires `local-only` with `yolo_enabled: false`.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is independent from Android profile readiness.
- The bridge does not depend on `wslpath`, a hardcoded `/mnt/c`, or Linux Git inside a Windows-created linked worktree.
- The bridge now refuses to trust the implicit WSL default. It enumerates installed distributions, skips known utility distributions such as `docker-desktop` unless explicitly requested, probes each candidate for `bash` and `git`, records the selection, and uses `--distribution <name>` for every runtime command.
- Windows paths cross into the selected distro through `WSLENV /p` with stdout/stderr captured separately.
- Linux Git uses a WSL-owned standalone clone at the exact SHA.
- Distribution probe output, bootstrap stdout, WSL stderr, WSL workspace path, exact head, floor evidence, report, and route are durable evidence.

## Broken or blocked

- Physical attempt 1 failed because `wslpath` produced no usable stdout.
- Physical attempt 2 proved that Linux Git must not use a Windows-created linked worktree.
- Physical attempt 3 reached exact HEAD `8de94b2a2d2615485442a7a83ba5e4267d785c82`, but bare `wsl.exe --exec bash` selected a registered/default WSL target without `bash` and failed with `execvpe(bash) failed: No such file or directory`.
- That third failure is now represented as an implicit-default-distro trap with a deterministic explicit-distribution selector.
- The explicit-distribution repair has not yet been rerun on the physical laptop.
- No live bounded First Mate crew dispatch has completed yet.
- Herdr automatic selection remains blocked by its separate lane.
- Native-Windows First Mate behavior remains unverified.

## Missing

- One successful exact-head physical run of `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` through an explicitly selected bash+git-capable distro.
- If no such distro is installed, one explicit operator installation/repair of a general-purpose Linux distro; the harness must report this as the blocker rather than silently using a utility distro.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees.
- Captured worker identity, branch/worktree ownership, validator receipts, and convergence evidence.
- Any evidence sufficient to replace tmux with Herdr for a specific profile.

## Safe next state

Fetch the repaired PR head without force, create an isolated Windows launcher worktree, and run the tracked bridge. The bridge must write `wsl-distro-probe.txt` before bootstrap. Completion requires `[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR`, an explicit `WSL_DISTRIBUTION=...`, exact-head proof from the WSL-owned clone, the canonical report/floor/route artifacts, bootstrap stdout, and WSL diagnostics. If no bash+git-capable distro exists, the exact blocker is the missing WSL Linux distro/toolchain, not another path-transport defect.

## Proof ceiling

This report proves the repository repair only after exact-head hosted CI passes. It is not physical-laptop WSL proof and not live First Mate crew proof.
