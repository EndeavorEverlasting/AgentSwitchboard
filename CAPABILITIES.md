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
| `dependency.install` | package manager or installer works | explicit setup/repair scope |
| `git.commit` | commits can be created | allowed for bounded sprint |
| `git.push` | branch can be pushed | explicit task or repo contract |
| `pr.write` | PRs/comments can be created or updated | allowed when delivery requires it |
| `merge` | PR can be merged | blocked unless explicitly authorized |
| `release.deploy` | release or deployment interface exists | blocked unless explicitly authorized |
| `target.mutate` | external workstation, server, game, or customer target can change | blocked unless explicitly authorized and environment-proven |
| `secrets.access` | credentials or secret stores are reachable | blocked by default; never persist in Git |
| `destructive.git` | force-push, reset, branch deletion | blocked unless explicit recovery authorization |

## Harness doctrine capabilities

| Capability | Activation and output | Guardrail and proof |
|---|---|---|
| `harness.doctrine.validate` | instruction, doctrine, skill, template, or action-contract change; returns findings | run `scripts/Test-HarnessDoctrineContract.ps1`; contract proof only |
| `action.commitment.validate` | request claims installation, setup, build, execution, repair, configuration, upgrade, deployment, merge, or release | reject acknowledgment-only and plan-substitution contracts; require mutation, validation, and commit or GitHub proof |
| `gnhf.test-timeout.enforce` | test, smoke, provider probe, fixture, or contract-only GNHF run | maximum 30 seconds wall clock and 30 seconds per iteration; terminate the process tree |
| `deepseek.usage-window.evaluate` | selected provider model uses `deepseek/*` | permit only a fresh verified `standard` or `discounted` state with multiplier no greater than 1.0; unknown blocks |

The machine-readable limits and default-deny rules are in `.ai/harness/harness-doctrine.policy.json`.

## Verification requirements

A capability probe must be:

- bounded and low-risk;
- relevant to the exact environment;
- recorded with command, result, and limitation;
- repeated when the environment or credentials may have changed.

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

## Provider and agent separation

Record executor, provider, model, subscription, and local compute separately. A harness being available does not prove a provider is authenticated, a model is reachable, or quota remains.

## Provider-routed GNHF capabilities

AgentSwitchboard splits the provider route into independently classifiable operations:

1. `discover-gnhf-runtime` — npm dist-tags/versions, installed binary, CLI flags, and optional upstream source facts;
2. `install-or-select-gnhf-runtime` — transactional install/selection against a capability matrix, not a guessed version;
3. `prove-provider-route` — shell-correct OpenCode dispatch and bounded model marker;
4. `launch-bounded-gnhf` — start GNHF only after provider proof and usage-window eligibility;
5. `verify-committed-delivery` — require a commit ahead of the base; reject zero-exit/no-commit.

Child repositories consume the installed capability document at `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\gnhf-runtime-capability.json` (`agentswitchboard.gnhf-runtime-capability.v1`). They must not guess npm versions, invent GNHF flags, or call source-tree installers during normal launch.
