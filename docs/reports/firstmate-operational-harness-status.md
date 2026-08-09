# First Mate operational harness status

Status: **contract-ready; PowerShell-to-bash LF transport repair committed; physical runtime reproof required**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic and requires `local-only` with `yolo_enabled: false`.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is independent from Android profile readiness.
- The bridge does not depend on `wslpath`, a hardcoded `/mnt/c`, or Linux Git inside a Windows-created linked worktree.
- The bridge refuses to trust the implicit WSL default. It enumerates installed distributions, skips known utility distributions such as `docker-desktop` unless explicitly requested, probes each candidate for `bash` and `git`, records the selection, and uses `--distribution <name>` for every runtime command.
- The physical laptop has now proved that `Ubuntu` is selected successfully as a `bash`+`git` capable distro.
- Every PowerShell-originated command payload is normalized from CRLF/CR to LF before it is passed to `bash -lc`, so Windows checkout line endings cannot turn `pipefail` into `pipefail\r`.
- Windows paths cross into the selected distro through `WSLENV /p` with stdout/stderr captured separately.
- Linux Git uses a WSL-owned standalone clone at the exact SHA.
- Distribution probe output, bootstrap stdout, WSL stderr, WSL workspace path, exact head, floor evidence, report, and route are durable evidence.

## Broken or blocked

- Physical failure 1: `wslpath` produced no usable stdout after a WSL configuration warning; the wrapper then dereferenced null output.
- Physical failure 2: a valid Windows detached worktree could not serve as a portable Linux Git checkout because its linked-worktree metadata was Windows-owned.
- Physical failure 3: the implicit WSL default had no `bash`; explicit distro selection then proved `Ubuntu` is the correct available runtime candidate.
- Physical failure 4 at exact head `37c961ea43b6f402219492cc3358afd0a6ea5cd1`: Ubuntu passed the distro capability gate, but the bootstrap here-string reached `bash -lc` with CRLF and failed as `set: pipefail\r: invalid option name` before any Git bootstrap command executed.
- Failure 4 is now an explicit command-transport regression contract: all WSL command payloads are LF-normalized immediately before `ProcessStartInfo.ArgumentList` receives them.
- The LF-normalized bridge has not yet been rerun on the physical laptop.
- No live bounded First Mate crew dispatch has completed yet.
- Herdr automatic selection remains blocked by its separate lane.
- Native-Windows First Mate behavior remains unverified.

## Missing

- One successful exact-head physical run of `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` with explicit Ubuntu selection and LF-normalized command transport.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees.
- Captured worker identity, branch/worktree ownership, validator receipts, and convergence evidence.
- Any evidence sufficient to replace tmux with Herdr for a specific profile.

## Safe next state

Fetch the repaired PR head without force, create an isolated Windows launcher worktree, run the tracked bridge, and inspect the registered runtime artifacts. Completion requires `[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR`, `WSL_DISTRIBUTION=Ubuntu`, exact-head proof from the WSL-owned clone, the canonical report/floor/route artifacts, bootstrap stdout, distro probe, and WSL diagnostics. If the bootstrap crosses successfully and the First Mate floor itself blocks, preserve that evidence and repair only that next dependency.

## Proof ceiling

This report proves the repository repair only after exact-head hosted CI passes. It is not physical-laptop WSL proof and not live First Mate crew proof.
