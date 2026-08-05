# Device Profile Launcher Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard/docs/governance/device-profile-launcher-contract.md`.
Machine-readable policy: `.ai/harness/device-profile-launcher.policy.json`.
Environment authority: `docs/governance/environment-capability-contract.md`.

AgentSwitchboard owns one canonical launcher per platform profile. The Windows Profile is WezTerm-backed and uses idempotent `open-or-activate`. Consumer repositories and desktop shortcuts delegate only; they do not own lifecycle, discovery, activation, duplicate prevention, or raw frontend fallback.

Classify the frontend, transport, workspace host, orchestration runtime, and agent runtime before profile installation or certification.

A profile frontend does not prove its workspace host, repository, tmux server, orchestration runtime, agent or provider route, authentication, persistence, or live behavior. Matching tmux session names on different hosts do not identify one workspace.

Linux and Android are separate implementations. Local rules define their exact role ceiling and implementation status, but may not silently inherit Windows behavior, substitute a lower-role topology, or claim runtime readiness from repository or package presence.

Static contracts and fixtures prove ownership and shape only. Runtime proof requires fresh environment identity, exact workspace-host and runtime identity, effective-state readback, opened or activated behavior, duplicate prevention, and operator-visible evidence.

Validate with the repository-local environment-capability and device-profile validators. Local rules may strengthen this contract but may not weaken canonical ownership, topology, delegation, or proof boundaries.
