# First Mate operational harness status

Status: **contract-ready; Windows-to-WSL bridge repaired again; physical runtime reproof required**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic and requires `local-only` with `yolo_enabled: false`.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is independent from Android profile readiness.
- The bridge no longer depends on `wslpath` or a hardcoded `/mnt/c` mount.
- Windows paths cross into WSL through `WSLENV /p` with stdout/stderr captured separately.
- Linux Git no longer runs inside the Windows-created linked worktree. The bridge derives the committed source repo, creates a WSL-owned standalone clone, checks out the exact SHA, and runs the owning harness there.
- Bootstrap stdout, WSL stderr, the WSL workspace path, exact head, floor evidence, report, and route are durable evidence.

## Broken or blocked

- The first physical command failed because `wslpath` produced no usable stdout.
- The second physical command reached exact HEAD `56901243838e8a6b32745066a226041fc0619234` and the canonical artifact registry, but WSL could not execute the visibility gate inside the Windows-created detached worktree.
- The second failure is now represented as a cross-OS Git-worktree metadata trap rather than retried with another CWD assumption.
- The WSL-owned standalone-clone repair has not yet been rerun on the physical laptop.
- No live bounded First Mate crew dispatch has completed yet.
- Herdr automatic selection remains blocked by its separate lane.
- Native-Windows First Mate behavior remains unverified.

## Missing

- One successful exact-head physical run of `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` using the WSL-owned standalone clone.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees.
- Captured worker identity, branch/worktree ownership, validator receipts, and convergence evidence.
- Any evidence sufficient to replace tmux with Herdr for a specific profile.

## Safe next state

Fetch the repaired PR head without force, create an isolated Windows launcher worktree, and run the tracked bridge. Completion requires `[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR`, exact-head proof from the WSL-owned clone, the canonical report/floor/route artifacts, bootstrap stdout, and WSL diagnostics. If the First Mate floor itself is then the blocker, preserve that evidence and repair only that dependency.

## Proof ceiling

This report proves the repository repair only after exact-head hosted CI passes. It is not physical-laptop WSL proof and not live First Mate crew proof.
