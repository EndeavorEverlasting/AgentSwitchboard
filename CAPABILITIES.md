# Capability Contract

Capabilities describe what an agent or tool can technically do in the current environment. They do not grant permission.

## Capability states

- `available` — the interface or command exists;
- `verified` — a bounded probe succeeded in the current environment;
- `constrained` — usable only within named limits;
- `blocked` — unavailable, unsafe, unauthorized, or failing;
- `unknown` — not yet probed.

Agents must not infer `verified` from command presence, prior sessions, documentation, or another machine.

## Canonical capability classes

| Capability | Typical evidence | Default authority |
|---|---|---|
| `repository.read` | files and Git history can be inspected | allowed |
| `repository.write` | tracked files can be modified | task-scoped |
| `command.execute` | local deterministic commands run | task-scoped |
| `network.read` | public or connected sources can be queried | task-scoped |
| `prompt.registry.read` | pinned registry and source hashes validate | allowed, read-only |
| `prompt.render` | exact prompt variables render without unresolved required fields | task-scoped, output only |
| `dependency.install` | package manager or installer works | explicit setup/repair scope |
| `git.commit` | commits can be created | allowed for bounded sprint |
| `git.push` | branch can be pushed | explicit task or repo contract |
| `pr.write` | PRs/comments can be created or updated | allowed when delivery requires it |
| `merge` | PR can be merged | blocked unless explicitly authorized |
| `release.deploy` | release or deployment interface exists | blocked unless explicitly authorized |
| `target.mutate` | external workstation, server, game, or customer target can change | blocked unless explicitly authorized and environment-proven |
| `secrets.access` | credentials or secret stores are reachable | blocked by default; never persist in Git |
| `destructive.git` | force-push, reset, branch deletion | blocked unless explicit recovery authorization |

## Verification requirements

A capability probe must be:

- bounded and low-risk;
- relevant to the exact environment;
- recorded with command, result, and limitation;
- repeated when the environment or credentials may have changed.

For prompt-kit capabilities, verification additionally requires the vendored snapshot SHA, every selected prompt text hash, variable closure, and the regular-AI versus GNHF execution-surface boundary.

## Authority formula

An action is permitted only when:

`verified capability + explicit task authority + repository policy + safe current state`

If any term is missing, the action is blocked or escalated.

## Degradation behavior

When a capability is missing:

- reuse a healthy alternative when the contract allows it;
- install or repair only inside explicit setup scope;
- record a precise skip or blocker;
- continue independent safe lanes;
- never claim success from a fallback that provides lower proof.

Prompt selection must not fall back to remembered text or fetch a newer registry silently when the local snapshot fails integrity validation.

## Provider and agent separation

Record executor, provider, model, subscription, and local compute separately. A harness being available does not prove a provider is authenticated, a model is reachable, or quota remains.
