# Environment Capability Harness

## Mission

Prevent AgentSwitchboard from steering an operator into an unproved platform path by separating frontend access, transport, workspace hosting, orchestration runtime, and agent runtime before installation or launch.

## Canonical components

- Doctrine: `docs/governance/environment-capability-contract.md`
- Policy: `.ai/harness/environment-capability.policy.json`
- Topology registry: `tooling/profiles/harness/environment-capability/environment-capability.registry.json`
- Schema: `tooling/profiles/harness/environment-capability/schemas/environment-capability.schema.json`
- Codebase map: `tooling/profiles/harness/environment-capability/codebase-map.json`
- Artifact registry: `tooling/profiles/harness/environment-capability/artifact-registry.json`
- Skill: `.ai/skills/environment-capability-routing/SKILL.md`
- PowerShell validator: `scripts/Test-EnvironmentCapabilityHarness.ps1`
- Python contract: `tests/test_environment_capability_harness.py`

## Why the previous Android implementation was insufficient

The initial Android PR installed a Termux package floor and a tmux/SSH launcher, then promoted Android to `repository-implemented`. That status collapsed several independent capabilities:

- a repository clone;
- a phone terminal;
- a phone-local tmux server;
- an SSH client;
- a remote workspace host;
- the Windows-first AgentSwitchboard control plane;
- agent CLIs and provider authentication.

Only the first four were implemented. The new harness renames that result `terminal-client-implemented` and limits phone-local tmux to `local-shell-only`.

## Registered topologies

### Windows WezTerm and WSL control plane

```text
frontend: Windows / WezTerm
transport: local process boundary
workspace host: WSL/Linux / tmux / repository
orchestration runtime: Windows / PowerShell 7 / AgentSwitchboard / GNHF
agent runtime: selected and separately verified
```

Implementation can exist without live proof. The `full-runtime-host` role requires current end-to-end evidence.

### Android Termux local shell

```text
frontend: Android / Termux
transport: local process boundary
workspace host: Android / Termux / local tmux
orchestration runtime: absent
agent runtime: unproved
```

Role ceiling: `local-shell-only`.

This can preserve a phone-local shell only while Android permits the processes to remain alive. It is not a desktop or remote workspace continuation.

### Android Termux SSH client to a POSIX workspace host

```text
frontend: Android / Termux
transport: SSH
workspace host: separately classified POSIX host / tmux / repository
orchestration runtime: remote and separately observed
agent runtime: remote and separately observed
```

Role ceiling before remote runtime certification: `terminal-client`.

An SSH alias is not sufficient. The target shell, tmux, repository, orchestration runtime, agent runtime, and persistence must be observed.

### Native Android full runtime

Reserved and unsupported. No current tracked implementation ports or certifies the Windows-first PowerShell, GNHF, worktree, agent, provider, authentication, and runtime evidence chain for Termux.

## Decision table

| Evidence | Maximum honest result |
|---|---|
| Termux opens | frontend available |
| `tmux` exists in Termux | local shell capability available |
| repository clones in Termux | repository readable/writable subject to Git proof |
| SSH connects | transport reachable |
| remote POSIX shell and tmux are observed | workspace-host candidate |
| same remote tmux server/session attaches from phone and desktop | cross-device terminal continuity observed |
| AgentSwitchboard orchestration commands and agent/provider route pass on workspace/control host | runtime candidate |
| exact operator path and visible behavior pass with fresh same-run evidence | role may be runtime-certified |

## Required rejection examples

- `Termux + tmux + repo = AgentSwitchboard works on Android`
- `dev` in Termux equals `dev` in WSL
- SSH success means the remote target accepts Bash/tmux commands
- a command returned zero, therefore a terminal attached
- a phone-local session is durable because tmux exists
- an Android shell can use Windows profile scripts because both are command lines

## Android corrective implementation target

The Android launcher must:

- report `terminal-client` rather than full profile readiness;
- state that local tmux is device-local only;
- distinguish local shell from remote workspace continuity;
- refuse a remote mutation until a supported remote host class is explicitly selected or observed;
- preserve remote authentication and host-key policy;
- record requested versus observed outcomes separately;
- avoid claiming an AgentSwitchboard runtime merely because the repository exists.

The bootstrap must:

- say it installs a terminal client, not a complete AgentSwitchboard runtime;
- avoid presenting a repository clone as runtime setup;
- emit the exact capability ceiling;
- leave provider and remote-host configuration separate.

## Validation

```powershell
python .\tests\test_environment_capability_harness.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-EnvironmentCapabilityHarness.ps1
python .\tests\test_device_profile_launcher_contract.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-DeviceProfileLauncherContract.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-HarnessDoctrineContract.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-AgentDocumentationContract.ps1
```

The validators are offline. They inspect tracked contracts and synthetic fixtures. They do not install packages, open SSH connections, launch WezTerm, create tmux sessions, call providers, or mutate a target.

## Live certification order

1. Freeze the exact operator command.
2. Record phone/Termux identity and process constraints.
3. Select local-shell or remote-client topology explicitly.
4. For remote use, preflight the target without mutation.
5. Record workspace-host and tmux server/session identity.
6. Execute the bounded requested operation.
7. Observe the visible attachment or activation.
8. Re-run to prove idempotent activation.
9. Record runtime and provider gaps separately.
10. Emit the exact role reached and the next blocked dependency.

## Proof ceiling

Passing this harness proves that repository contracts reject known false equivalences and route environment work through a bounded topology model. It does not prove a phone, workstation, SSH host, tmux server, AgentSwitchboard runtime, agent, provider, or authentication route works.
