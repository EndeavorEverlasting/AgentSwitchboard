# Capabilities

Capability presence is not authority. Probe the current environment and record each required capability as `available`, `verified`, `constrained`, `blocked`, or `unknown`.

## Environment capability and continuity

Classify `frontend`, `transport`, `workspaceHost`, `orchestrationRuntime`, and `agentRuntime` independently. Select one current role ceiling: `full-runtime-host`, `workspace-host`, `terminal-client`, `local-shell-only`, `transport-only`, or `unsupported`.

- `environment.capability.read` — inspect the canonical/local policy and registered topologies; read-only contract evidence.
- `environment.topology.select` — return one topology, role ceiling, blockers, and forbidden claims; no mutation.
- `environment.remote.preflight` — inspect remote OS/shell, tmux, repository identity/state, orchestration, agent/provider, and persistence before mutation.
- `environment.role.certify` — require fresh effective-state and operator-visible evidence for the exact selected role.

Terminal access is not workspace hosting. SSH reachability is not shell compatibility. Repository or package presence is not runtime readiness. Same-named tmux sessions on different hosts are not one workspace. Command acknowledgement or CI is not live behavior.

## Public plan capabilities

- `plan.registry.read` — read the public plan registry and selected plan; read-only and not freshness proof.
- `plan.contract.validate` — validate machine-readable plan shape and registered paths; contract proof only.

A public plan never authorizes authentication, merge, deployment, target mutation, secret access, or destructive Git.

## Repository-specific capability constraints

`REPLACE_CAPABILITY_CONSTRAINTS`
