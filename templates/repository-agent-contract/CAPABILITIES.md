# Capabilities

Capability presence is not authority. Probe the current environment and record each required capability as `available`, `verified`, `constrained`, `blocked`, or `unknown`.

## Public plan capabilities

- `plan.registry.read` — read the public plan registry and selected plan; read-only and not freshness proof.
- `plan.contract.validate` — validate machine-readable plan shape and registered paths; contract proof only.

A public plan never authorizes authentication, merge, deployment, target mutation, secret access, or destructive Git.

## Repository-specific capability constraints

`REPLACE_CAPABILITY_CONSTRAINTS`
