# Environment Capability Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard/docs/governance/environment-capability-contract.md`.
Machine-readable policy: `.ai/harness/environment-capability.policy.json`.

Before installation, auto-configuration, cross-device, phone, SSH, remote-tmux, WSL/Linux/Windows, or uncertain runtime work, classify these layers independently:

`frontend -> transport -> workspace host -> orchestration runtime -> agent runtime`

Select one current role ceiling:

- `full-runtime-host`;
- `workspace-host`;
- `terminal-client`;
- `local-shell-only`;
- `transport-only`;
- `unsupported`.

The following are not equivalent:

- frontend and workspace host;
- transport reachability and remote-shell compatibility;
- repository or package presence and runtime readiness;
- same-named tmux sessions on different hosts and one workspace;
- phone-local tmux and cross-device continuity;
- terminal client and full runtime host;
- command acknowledgement or CI and live behavior.

A tmux identity is scoped to the workspace host, tmux server/socket, and session. Auto-configuration must observe, classify, select a topology, report blockers, mutate only the selected boundary, read effective state, validate, and then perform explicitly authorized runtime certification.

Unknown host, shell, repository identity/state, tmux identity, orchestration runtime, agent/provider state, persistence, or authority blocks the dependent mutation. A lower-role topology must not be silently substituted for the requested experience.

Local repository rules may strengthen this contract but may not weaken it. Runtime claims require fresh same-run effective-state and operator-visible evidence.
