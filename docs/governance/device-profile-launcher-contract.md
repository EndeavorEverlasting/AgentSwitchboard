# Device Profile Launcher Contract

Machine-readable authority: `.ai/harness/device-profile-launcher.policy.json`.

Environment and continuity authority: `docs/governance/environment-capability-contract.md` and `.ai/harness/environment-capability.policy.json`.

This contract governs platform-specific launcher surfaces. It extends the harness doctrine, runtime-event contract, and environment-capability contract; it does not grant installation, runtime, target-mutation, deployment, authentication, or release authority.

## Profile model

AgentSwitchboard owns separate platform profiles:

- **Windows Profile** — its terminal frontend is WezTerm and its canonical lifecycle operation is `open-or-activate`.
- **Linux Profile** — a separate reserved profile with its own future implementation and certification. Windows implementation details may not be copied into it by assumption.
- **Android Profile** — a separate terminal-client implementation using Termux. Its current status is `terminal-client-implemented`, not a native orchestration or agent runtime.

A profile identifies a frontend and launcher contract. It does not by itself prove where the repository, tmux server, orchestration runtime, agent executable, provider, model, or authentication live.

Before cross-platform installation, auto-configuration, phone continuity, SSH, or remote tmux work, classify the five environment layers:

`frontend -> transport -> workspace host -> orchestration runtime -> agent runtime`

Use `.ai/skills/environment-capability-routing/SKILL.md` and the registered environment topologies. A profile may not exceed the role ceiling of its selected topology.

## Implementation status vocabulary

Profiles use only:

- `reserved`;
- `contract-only`;
- `terminal-client-implemented`;
- `workspace-host-implemented`;
- `full-runtime-implemented`;
- `runtime-proved`.

`repository-implemented` is forbidden because repository presence does not state which capability was implemented and does not prove an orchestration or agent runtime.

## Canonical ownership

For each profile, exactly one repository owns lifecycle decision logic. For the Windows Profile:

- canonical owner: `EndeavorEverlasting/AgentSwitchboard`;
- canonical operation: `open-or-activate`;
- canonical source contract: `tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1`;
- installed contract path: `%LOCALAPPDATA%\AgentSwitchboard\profiles\windows\Invoke-AgentSwitchboardOpenOrActivate.ps1`;
- consumer and certifier: `EndeavorEverlasting/SysAdminSuite`.

For the Android terminal client:

- canonical owner: `EndeavorEverlasting/AgentSwitchboard`;
- canonical operation: `open-or-activate` within the selected topology;
- canonical source contract: `tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh`;
- installed path: `$PREFIX/bin/agentswitchboard-phone`;
- bootstrap: `Bootstrap-AgentSwitchboard-Termux.sh`;
- current role ceiling: `terminal-client`;
- phone-local tmux role: `local-shell-only`;
- native Android orchestration runtime: `unimplemented`;
- native Android agent runtime: `unproved`.

The Android implementation may render a terminal, maintain a phone-local shell, or attach through SSH to a separately classified remote workspace host. It may not be described as a full AgentSwitchboard runtime.

## Idempotent open-or-activate behavior

Repeated calls with the same profile and workspace identity converge on one logical workspace only when the workspace host and tmux server/session identity also match.

1. Resolve the selected profile, environment topology, and canonical launcher version.
2. Discover the exact workspace host and owned workspace identity.
3. For tmux, identify the host/server/socket and session—not merely the session name.
4. When the exact owned workspace already exists, activate or attach to it.
5. Otherwise, open it once only when creation is explicitly owned.
6. Return one explicit profile-specific outcome such as `opened`, `activated`, `blocked`, or `failed`.
7. Record enough evidence to distinguish activation from a new launch and a local shell from remote continuity.

A tmux session named `dev` in Termux and a session named `dev` in WSL are different workspaces unless evidence proves both clients reached the same host and tmux server/session identity.

The launcher may not create duplicate logical workspaces merely because a raw process or window was not found by a weak heuristic. Process exit code or SSH acknowledgement alone is not proof of open-or-activate behavior.

## Android terminal-client boundary

The Android launcher supports two different topologies and must keep them visibly separate.

### Phone-local shell

`android-termux-local-shell` may create or attach to a phone-local tmux session. Its role ceiling is `local-shell-only` and its continuity scope is `device-local-only`.

It does not resume a Windows, WSL, Linux-server, or other remote tmux session. Android process persistence is a separate runtime limitation.

### Remote POSIX tmux client

`android-termux-ssh-posix-workspace-client` uses Termux as the frontend and SSH as transport to a separately classified POSIX workspace host.

Before remote mutation, the current adapter requires:

- explicit `--host-profile posix-tmux` selection;
- an absolute repository path;
- an expected Git origin;
- successful remote shell execution;
- `tmux` presence;
- repository presence and matching origin;
- a clean working tree;
- observed session presence or absence.

A missing session blocks unless `--create` was explicitly supplied. Unsupported or unknown remote shell classes block. SSH reachability does not prove POSIX compatibility, tmux readiness, repository readiness, orchestration runtime readiness, or agent/provider readiness.

The remote terminal client cannot claim a native Android orchestration runtime or a `full-runtime-host` role.

## Delegation-only consumers

Desktop shortcuts, repository wrappers, SysAdminSuite, Android presentation surfaces, and other consumers may:

- locate the certified AgentSwitchboard launcher;
- validate the expected profile ID, environment topology, contract version, and launcher identity;
- pass reviewed profile/workspace arguments;
- preserve the canonical exit code and result artifact;
- report a clear blocker when the canonical launcher or required topology is absent or uncertified.

They may not:

- call `wezterm`, `wezterm.exe`, or `wezterm-gui.exe` as an independent Windows fallback;
- recreate session discovery, window detection, tmux attachment, process ownership, activation, or duplicate-prevention logic;
- generate a shortcut that targets consumer-owned lifecycle code;
- silently substitute a different profile, host class, shell class, or platform implementation;
- claim certification from file presence, repository presence, command presence, SSH reachability, or process exit alone.

A shortcut or terminal wrapper is presentation only. It points to the installed canonical profile launcher and contains no competing lifecycle decision logic.

## SysAdminSuite certification

SysAdminSuite consumes and certifies the Windows Profile; it does not own it. Certification must verify:

- the expected AgentSwitchboard profile ID and contract version;
- the canonical launcher path and identity;
- exact delegate-only invocation;
- no raw WezTerm fallback;
- no consumer-owned open, activate, session, or duplicate-prevention branch;
- valid `opened`, `activated`, `blocked`, and `failed` fixtures;
- idempotence across repeated equivalent invocations;
- honest proof level and proof ceiling.

A missing or uncertified AgentSwitchboard launcher is `blocked`, not permission for SysAdminSuite to launch WezTerm itself.

## Runtime-event composition

A delivered launcher must register and observe the event chain:

`profile request -> environment topology selected -> canonical launcher resolved -> workspace host discovered -> opened or activated -> terminal result -> evidence sink`

The runtime event contract supplies correlation, causation, immutable envelopes, successor rules, and sink requirements. Static profile doctrine proves ownership and contract shape only. Synthetic fixtures prove classification and idempotence contracts only. Runtime proof requires fresh correlated evidence for the exact selected topology, workspace host, opened or activated path, and operator-visible result.

## Action-commitment rule

A prompt, title, mission, or expected output that claims it will install, build, configure, repair, certify, or deploy a platform profile or launcher must require corresponding tracked implementation and proof.

A valid execution contract names:

- profile ID and canonical owner;
- environment topology and role ceiling;
- frontend, transport, workspace host, orchestration runtime, and agent runtime;
- canonical entrypoint and installed path;
- consumer/certifier;
- owned and forbidden launch surfaces;
- open-or-activate identity and outcomes;
- topology and artifacts;
- validators and runtime evidence required;
- commit or GitHub evidence;
- achieved proof level and ceiling.

A rewritten prompt, architecture note, plan, source checkout, package list, or handoff is not a substitute for requested implementation or runtime proof.

## Validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-EnvironmentCapabilityHarness.ps1
python .\tests\test_environment_capability_harness.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-DeviceProfileLauncherContract.ps1
python .\tests\test_device_profile_launcher_contract.py
```

Then run the wider doctrine, documentation, repository-family, and aggregate harness validators. These checks never launch WezTerm, WSL, tmux, SSH, AgentSwitchboard, SysAdminSuite, an agent, a browser, or a provider.

## Proof ceiling

Passing the contract proves profile ownership, platform separation, environment-topology registration, Android terminal-client role ceilings, and synthetic rejection of false proof promotion. It does not prove any workstation, phone, remote host, tmux server, repository, orchestration runtime, agent runtime, provider, authentication, visible window, terminal attachment, or operator acceptance.
