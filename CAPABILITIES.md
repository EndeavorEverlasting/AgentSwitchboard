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

## Public plan and startup capabilities

| Capability | Activation and output | Guardrail and proof |
|---|---|---|
| `plan.registry.read` | repository coordination or resume request; returns the public plan registry and selected plan | read-only; registry presence does not prove freshness or authorize work |
| `plan.contract.validate` | plan creation or material ownership, dependency, task, proof, or handoff change; returns deterministic findings | run `scripts/Test-PublicPlanContracts.ps1`; contract proof only |
| `startup.readiness.report` | AgentSwitchboard startup or explicit readiness request; returns console, JSON, and English local adapter-readiness evidence | read-only; no install, authentication, provider call, repository mutation, or hosted-response claim |

Public plans coordinate work. They do not grant branch, provider, merge, deployment, target-mutation, secret, or destructive-Git authority.

## Synthetic harness observer capabilities

| Capability | Activation and output | Guardrail and proof |
|---|---|---|
| `harness.composition.observe` | inspect `.ai/harness/app-composition.graph.json`; validate every registered required node, declared edge, ingress-to-observer route, and observer-to-output cascade | static registered-topology proof only; missing optional MCP/LSP readiness is an honest skip |
| `harness.proof.aggregate` | run `Test-AppHarness.cmd` or `scripts/Test-AppHarness.ps1`; emit `app-harness-validation.json` and `app-harness-validation.md` with a PASS/SKIP/FAIL matrix | offline only; bounded repository-owned validators; no network, launcher, provider, application, target, account, save, deployment, or runtime execution |

The event observer proves the composition graph that the repository has registered. It does not infer unregistered nodes, claim live event delivery, or promote a static edge into runtime behavior proof.

## Runtime event capabilities

| Capability | Activation and output | Guardrail and proof |
|---|---|---|
| `runtime.event-contract.validate` | validate the typed envelope, correlation and causation fixtures, topology registry, doctrine references, and proof boundaries | run `scripts/Test-RuntimeEventContract.ps1`; contract and synthetic causality proof only |
| `runtime.event-topology.read` | inspect registered sources, observers, handlers, sinks, event types, and directed edges | read-only; registry presence does not prove implementation or delivery |
| `runtime.event-cascade.observe` | capture one authorized runtime chain from source through observer, handler, successor or terminal, and evidence sink | unavailable until an explicit runtime lane and implementation-specific observer exist; static or synthetic checks may not claim this capability verified |

A runtime event claim records event ID, correlation ID, causation ID, sequence, source node, handler decision, successor or terminal result, sink artifact, environment, and proof ceiling. Capability presence never grants runtime execution or target mutation authority.

## Device profile launcher capabilities

| Capability | Activation and output | Guardrail and proof |
|---|---|---|
| `profile.registry.read` | inspect `.ai/harness/device-profile-registry.json` and return Windows, Linux, and Android ownership and status | read-only contract evidence; registry presence does not prove an implementation exists |
| `profile.launcher.contract.validate` | validate canonical owner, platform separation, Windows `open-or-activate`, delegate-only consumers, idempotence rules, and action-commitment fixtures | run `scripts/Test-DeviceProfileLauncherContract.ps1`; contract proof only |
| `profile.launcher.open-or-activate` | open one profile workspace or activate its existing owned instance and return `opened`, `activated`, `blocked`, or `failed` | unavailable until the profile implementation exists and an authorized runtime lane observes both open and activate paths |
| `profile.consumer.certify` | SysAdminSuite verifies exact profile version, canonical launcher identity, delegation, fixtures, and no competing lifecycle logic | certification belongs in a separate SysAdminSuite adoption PR; file presence and process exit are insufficient |

The Windows Profile is WezTerm-backed and owned by AgentSwitchboard. Raw WezTerm commands, desktop shortcuts, and SysAdminSuite are presentation or consumer surfaces only. Linux and Android remain separate profiles and may use different configuration.

## Harness doctrine capabilities

| Capability | Activation and output | Guardrail and proof |
|---|---|---|
| `harness.doctrine.validate` | instruction, doctrine, skill, template, or action-contract change; returns findings | run `scripts/Test-HarnessDoctrineContract.ps1`; contract proof only |
| `action.commitment.validate` | request claims installation, setup, build, execution, repair, configuration, upgrade, deployment, merge, or release | reject acknowledgment-only and plan-substitution contracts; require mutation, validation, and commit or GitHub proof |
| `gnhf.test-timeout.enforce` | test, smoke, provider probe, fixture, or contract-only GNHF run | maximum 30 seconds wall clock and 30 seconds per iteration; terminate the process tree |
| `deepseek.usage-window.evaluate` | selected provider model uses `deepseek/*` | permit only a fresh verified `standard` or `discounted` state with multiplier no greater than 1.0; unknown blocks |

The machine-readable limits and default-deny rules are in `.ai/harness/harness-doctrine.policy.json`.

## Verification requirements

A capability probe must be bounded, low-risk, relevant to the exact environment, recorded with command and limitation, and repeated when the environment or credentials may have changed.

## Authority formula

`verified capability + explicit task authority + repository policy + safe current state`

If any term is missing, the action is blocked or escalated.

## Degradation behavior

When a capability is missing, reuse a healthy alternative when allowed, install or repair only inside explicit scope, record a precise skip or blocker, continue independent safe lanes, and never claim success from a lower-proof fallback.

## Provider and agent separation

Record executor, provider, model, subscription, and local compute separately. Harness availability does not prove provider authentication, model reachability, or quota.

## Provider-routed GNHF capabilities

AgentSwitchboard splits provider routing into:

1. `discover-gnhf-runtime`;
2. `install-or-select-gnhf-runtime`;
3. `prove-provider-route`;
4. `launch-bounded-gnhf`;
5. `verify-committed-delivery`.

Child repositories consume `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\gnhf-runtime-capability.json`. They must not guess npm versions, invent GNHF flags, or call source-tree installers during normal launch.
