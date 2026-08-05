# Environment Capability and Continuity Contract

Machine-readable authority: `.ai/harness/environment-capability.policy.json`.

This contract prevents platform labels, terminal availability, package installation, repository presence, or tmux session names from being promoted into an unproved AgentSwitchboard runtime claim.

## Why this contract exists

AgentSwitchboard is currently Windows-first. Its established control plane includes Windows PowerShell, PowerShell 7, Windows-local installation paths, WSL, WezTerm, tmux, GNHF fleet scripts, agent CLIs, provider authentication, worktrees, validators, and local evidence. A new frontend or transport may extend access to that control plane without becoming the control plane itself.

The phrase **works on this environment** is invalid unless the exact role and capability level are named.

## Five-layer topology

Every environment claim must identify these layers separately:

1. **Frontend** — the user-facing terminal, TUI, GUI, or application that renders input and output.
2. **Transport** — the local process boundary or connection used to reach another host, such as SSH.
3. **Workspace host** — the host and operating-system environment that owns the repository checkout, working tree, tmux server, and session socket.
4. **Orchestration runtime** — the host and process environment that executes AgentSwitchboard setup, routing, validators, worktree creation, and GNHF control-plane behavior.
5. **Agent runtime** — the executable agent, provider/model route, authentication state, and network endpoint that perform model-backed work.

A layer may be local or remote. No layer inherits readiness or proof from another layer.

## Environment roles

An observed environment receives exactly one current role for the requested operation:

- `full-runtime-host` — the complete required orchestration and agent capability chain is implemented and runtime-proved on this host.
- `workspace-host` — the repository and durable terminal workspace are hosted here, but the complete AgentSwitchboard and provider runtime is not proved.
- `terminal-client` — the environment can render a terminal and reach a selected workspace host, but does not own the orchestration runtime.
- `local-shell-only` — the environment can run local shell or tmux commands, but no cross-device continuity or AgentSwitchboard runtime is proved.
- `transport-only` — a connection mechanism exists but the target workspace or runtime has not been classified.
- `unsupported` — the requested topology cannot be performed safely with current implementation and evidence.

`terminal-client`, `local-shell-only`, and `transport-only` are not aliases for `full-runtime-host`.

## tmux identity is host-scoped

A tmux session is identified by its tmux server and socket namespace on one workspace host. A session named `dev` in Termux and a session named `dev` in WSL are different sessions, even when the names match.

A cross-device continuity claim requires evidence that both frontends attach to the same workspace host and the same tmux server/session identity. Session-name equality alone is insufficient.

Phone-local tmux may preserve a phone-local shell while Android permits the process to live. It does not resume a Windows, WSL, Linux-server, or other remote tmux workspace.

## Platform separation

- **Windows Profile** may use WezTerm, WSL, and the repository-owned Windows launcher.
- **Android Profile** may use Termux as a terminal frontend and SSH as a transport.
- Android must not be described as a native WezTerm platform unless a separately verified Android WezTerm implementation exists.
- Termux is not a generic GNU/Linux host. Android process lifetime, filesystem layout, executable paths, package builds, and app sandboxing are material capability boundaries.
- Linux, WSL, Android, and Windows remote shells must be classified independently. An SSH target is not presumed POSIX merely because the client is Termux.

## Implementation status vocabulary

Profile and topology status uses only:

- `reserved` — named but not implemented;
- `contract-only` — doctrine and schemas exist, but executable behavior does not;
- `terminal-client-implemented` — frontend/transport behavior is tracked and validated; orchestration and agent runtime are not claimed;
- `workspace-host-implemented` — repository/tmux host behavior is tracked and validated; full orchestration and agent runtime are not claimed;
- `full-runtime-implemented` — the complete required implementation exists, but live runtime proof is still separate;
- `runtime-proved` — the exact requested operator path was observed with fresh same-run evidence.

`repository-implemented` is forbidden because it does not identify what was implemented.

## Auto-configuration rule

“Auto-configure on any environment” means:

1. observe the current environment without mutation;
2. classify frontend, transport, workspace host, orchestration runtime, agent runtime, persistence, and repository identity;
3. select one registered topology whose prerequisites match;
4. present blockers and the exact mutation boundary;
5. install or repair only the packages and files owned by the selected topology;
6. read back effective state;
7. run focused deterministic validation;
8. perform explicitly authorized runtime certification;
9. report the achieved role and proof ceiling.

It does not mean running one universal installer, treating every shell as Linux, installing every possible runtime, or silently substituting a local phone shell for a remote AgentSwitchboard workspace.

## Remote-host preflight

A remote workspace operation must classify the target before mutation. The preflight records:

- target alias without credentials;
- remote operating-system and shell class;
- tmux presence and version;
- repository path and origin identity when a repository is requested;
- clean or dirty working-tree state;
- orchestration-runtime command availability;
- agent-runtime/provider state as `verified`, `blocked`, or `unknown`;
- persistence and reachability limitations;
- exact topology selected.

Unknown shell class, missing tmux, absent or unexpected repository, dirty checkout, missing orchestration runtime, or ambiguous host identity blocks automatic session creation unless the requested operation explicitly owns the repair.

## Android capability boundary

The tracked Android implementation may prove:

- Termux shell detection;
- phone-side package-floor installation;
- local-shell tmux creation or attachment;
- SSH client availability;
- bounded plan generation;
- explicit attachment to a separately classified remote POSIX tmux workspace;
- local untracked evidence.

It may not claim:

- native Windows AgentSwitchboard setup;
- WezTerm on Android;
- GNHF fleet readiness;
- OpenCode, AGY, Goose, Hermes, Copilot, Pi, or provider authentication;
- remote Windows or POSIX shell compatibility without classification;
- remote repository readiness without readback;
- durable Android background execution;
- cross-device continuity from phone-local tmux;
- a full AgentSwitchboard runtime from cloning the repository.

## Evidence and proof

A capability claim records:

- environment ID and role;
- layer assignments;
- topology ID;
- observed commands and versions;
- workspace-host identity;
- tmux server/session identity when applicable;
- repository identity and state;
- orchestration and agent runtime status;
- mutation performed;
- effective-state readback;
- generated artifact paths;
- proof level and ceiling.

Static files and hosted CI can prove contracts and deterministic behavior. They cannot prove a phone installation, remote authentication, session attachment, process persistence, provider response, or operator acceptance.

## Required rejection cases

The harness must reject:

- `repository cloned` interpreted as `AgentSwitchboard runtime ready`;
- `tmux installed` interpreted as `cross-device continuity ready`;
- two same-named sessions on different hosts interpreted as one workspace;
- Termux interpreted as generic Linux without profile evidence;
- SSH reachability interpreted as target shell compatibility;
- remote command acknowledgement interpreted as attachment or agent behavior;
- local Android tmux presented as a durable replacement for a remote workspace host;
- any Android `full-runtime-host` claim while Windows-first orchestration and agent prerequisites remain absent or unproved.

## Validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-EnvironmentCapabilityHarness.ps1
python .\tests\test_environment_capability_harness.py
```

Then run the device-profile, documentation, harness-doctrine, repository-family, and aggregate harness validators.

## Proof ceiling

This contract and its synthetic fixtures prove topology vocabulary, layer separation, role classification, required blockers, and forbidden proof promotion. They do not prove any specific phone, workstation, remote host, tmux session, repository, orchestration runtime, agent runtime, provider, or network path works.
