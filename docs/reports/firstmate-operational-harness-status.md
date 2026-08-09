# First Mate operational harness status

Status: **contract-ready; runtime unproved**

## Working

- AgentSwitchboard / First Mate / session-backend / worker responsibilities are separated explicitly.
- First Mate is pinned to the audited upstream commit already recorded by the interoperability floor.
- tmux remains the reference session backend.
- Direct-vs-crew routing is deterministic rather than model-preference based.
- Codebase map, workflow specs, artifact registry, validator registry, optional hooks, scoped skill, report builder, and completeness tests are tracked.
- Laptop/WSL crew readiness is explicitly independent from Android profile readiness.

## Broken or blocked

- The First Mate branch has not yet produced a live bounded crew-dispatch proof.
- Herdr automatic selection is blocked until its separate lane supplies a pinned reviewed upstream contract, aggregate registration, and live runtime/persistence evidence.
- Native Windows First Mate behavior is unverified.
- Android/Termux behavior remains owned by the Android device-profile lane.

## Missing

- One local-only First Mate sprint with at least two disjoint worker branches/worktrees.
- Captured worker identity, branch/worktree ownership, validation receipts, and convergence evidence.
- Any evidence strong enough to replace tmux with Herdr for a specific profile.

## Safe next state

On the laptop's Linux/WSL lane, pass the existing read-only First Mate interoperability floor and then run one bounded `local-only` parallel sprint on tmux. Android and Herdr work can continue independently.

## Proof ceiling

This report describes tracked repository contracts and known runtime gaps. It is not proof that First Mate or Herdr executed successfully.
