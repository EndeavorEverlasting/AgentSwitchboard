# First Mate operational harness status

Status: **contract-ready; Windows-to-WSL bridge repaired; physical runtime reproof required**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit already recorded by the interoperability floor.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic rather than model-preference based.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is explicitly independent from Android profile readiness.
- The Windows-to-WSL bridge no longer depends on `wslpath`; it uses the exact Windows worktree as `wsl.exe`'s process working directory.
- WSL stdout and stderr are captured separately so `/etc/wsl.conf` warnings cannot corrupt machine-readable output.
- The bridge proves WSL sees the same exact AgentSwitchboard HEAD before running the owning harness, report builder, read-only First Mate floor, and route selector.

## Broken or blocked

- The prior operator command failed before the runtime floor because `wsl.exe wslpath -a -u <Windows-temp-path>` returned no usable stdout; the subsequent `.Trim()` dereferenced null.
- That physical-laptop failure class is repaired in the tracked bridge but has not yet been rerun on the laptop.
- The First Mate branch has not yet produced a live bounded crew-dispatch proof.
- Herdr automatic selection is blocked until its separate lane supplies a pinned reviewed upstream contract, aggregate registration, and live runtime/persistence evidence.
- Native Windows First Mate behavior is unverified; only Windows-to-WSL orchestration is in this bridge.
- Android/Termux behavior remains owned by the Android device-profile lane.

## Missing

- One successful exact-head run of `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` on the physical laptop.
- One local-only First Mate sprint with at least two disjoint worker branches/worktrees.
- Captured worker identity, branch/worktree ownership, validation receipts, and convergence evidence.
- Any evidence strong enough to replace tmux with Herdr for a specific profile.

## Safe next state

On the laptop, fetch the repaired PR head into an isolated worktree and run the tracked Windows-to-WSL bridge. Completion requires `[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR`, the canonical report, floor evidence, route artifact, and WSL diagnostics. If that passes, proceed to one bounded `local-only` parallel First Mate sprint on tmux. Android and Herdr work continue independently.

## Proof ceiling

This report proves the repository repair and its hosted/static contracts only after CI passes at the repaired head. It is not yet proof that the physical laptop's WSL floor or a First Mate crew executed successfully.
