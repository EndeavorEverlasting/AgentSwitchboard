# Commit-Required Harness Doctrine

Canonical source: `EndeavorEverlasting/AgentSwitchboard/docs/governance/harness-doctrine.md`.

Every writing sprint identifies repository, branch or worktree, PR or sprint, lane, owned and forbidden scope, expected artifacts, validation order, proof ceiling, and environment topology/role ceiling when work crosses platforms, hosts, shells, frontends, or runtimes.

Use the executable loop:

`request -> evidence review -> bounded decision -> repo or Git or GitHub mutation -> artifacts -> validation -> report -> next decision`

A prompt that claims installation, setup, build, execution, repair, configuration, upgrade, deployment, merge, release, or certification must require the corresponding mutation and proof. Acknowledgment, architecture, a plan, a repository clone, package presence, summary, or handoff is not a substitute.

## Environment capability

Read `docs/governance/environment-capability-contract.md` before cross-platform, auto-configuration, phone, SSH, remote-tmux, WSL/Linux/Windows, or uncertain runtime work.

Classify:

`frontend -> transport -> workspace host -> orchestration runtime -> agent runtime`

Select one supported topology and current role ceiling. Do not promote terminal access, transport reachability, repository/package presence, same-named tmux sessions, command acknowledgement, or CI into workspace or runtime proof. A lower-role topology may not be silently substituted for the requested experience. Unknown environment identity or capability blocks dependent mutation.

## Runtime events

Read `docs/governance/runtime-event-contract.md`. Register source, typed envelope, observer, handler, successor, and evidence sink. Static topology does not prove runtime delivery. Validate with `scripts/Test-RuntimeEventContract.ps1`.

## Device profiles

Read `docs/governance/device-profile-launcher-contract.md` after environment classification. AgentSwitchboard owns one canonical launcher per profile. Consumers delegate only, raw frontend fallback is forbidden, and platform implementations remain separate. Contract-only proof does not prove open-or-activate behavior. Validate with the repository-local environment-capability and device-profile validators.

## Test-only and provider gates

Test-only GNHF runs are bounded to 30 seconds wall clock and 30 seconds per iteration, normally one iteration, with process-tree termination. DeepSeek is fail-closed unless a fresh verified local schedule reports `standard` or `discounted` usage with multiplier no greater than `1.0`.

Local rules may strengthen this doctrine but may not weaken it.
