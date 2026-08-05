# AgentSwitchboard Android Terminal Client — Termux

## Current classification

The Android implementation is **`terminal-client-implemented`**.

It is not a native AgentSwitchboard orchestration runtime and it is not a Windows-equivalent profile. The current role ceiling is:

- `local-shell-only` for phone-local tmux;
- `terminal-client` when attaching to a separately classified remote workspace host.

Read `docs/governance/environment-capability-contract.md` before changing this classification or presenting Android as “AgentSwitchboard running on the phone.”

## The actual topology

Phone-local shell:

```text
frontend: Android / Termux
transport: local process boundary
workspace host: Android / Termux / phone-local tmux server
orchestration runtime: unimplemented
agent runtime: unproved
continuity scope: device-local-only
```

Remote terminal client:

```text
frontend: Android / Termux
transport: SSH
workspace host: explicitly classified remote POSIX host / tmux / repository
orchestration runtime: separately observed on the remote/control host
agent runtime: separately observed on the remote/control host
```

A tmux session named `dev` in Termux and a tmux session named `dev` in WSL are different sessions. Cross-device continuity exists only when both devices attach to the same workspace host and the same tmux server/session identity.

## What the bootstrap installs

`Bootstrap-AgentSwitchboard-Termux.sh` installs only the Android terminal-client floor:

- `git`;
- `openssh`;
- `tmux`;
- `curl`;
- the tracked `agentswitchboard-phone` launcher;
- a source checkout used to obtain and validate tracked terminal-client files.

The repository clone is **not** proof that the following are configured on Android:

- PowerShell 7;
- Windows setup and `%LOCALAPPDATA%` fleet state;
- WSL or WezTerm;
- GNHF fleet behavior;
- OpenCode, AGY, Goose, Hermes, Copilot, or Pi;
- provider authentication or model access;
- isolated worktree execution;
- full AgentSwitchboard runtime certification.

## Execution hold

The earlier phone bootstrap command is withdrawn as a live certificate. Do not execute the Android bootstrap merely because PR #62 has static or CI validation.

A new immutable phone command must be issued only after:

1. the environment-capability harness is green at an exact reviewed head;
2. the Android launcher and bootstrap are re-reviewed at that head;
3. the command pins immutable content;
4. the operator explicitly begins the live-device certification lane.

## Operator surfaces

Read-only phone status:

```bash
agentswitchboard-phone status
```

Expected ceiling:

```text
capability_status=terminal-client-implemented
role=terminal-client
local_tmux_role=local-shell-only
continuity_scope=device-local-only
cross_device_continuity=requires-remote-workspace-host
native_orchestration_runtime=unimplemented
native_agent_runtime=unproved
```

### Phone-local shell only

Plan:

```bash
agentswitchboard-phone local-shell --session dev --plan
```

Run only when a phone-local shell is actually desired:

```bash
agentswitchboard-phone local-shell --session dev
```

This creates or attaches to the phone’s tmux server. It does not resume a desktop, WSL, server, or remote AgentSwitchboard workspace.

### Remote POSIX tmux workspace client

The current remote adapter supports only an explicitly selected `posix-tmux` host profile. Other remote shell classes are blocked.

Plan:

```bash
agentswitchboard-phone remote workbox \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev \
  --plan
```

Attach to an existing session after preflight:

```bash
agentswitchboard-phone remote workbox \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev
```

Create the session only when that mutation is intended:

```bash
agentswitchboard-phone remote workbox \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev \
  --create
```

Remote preflight checks:

- the selected remote shell accepts the POSIX adapter;
- `tmux` exists;
- the repository exists at the exact absolute path;
- the origin matches the supplied expected origin;
- the working tree is clean;
- the selected tmux session is present or absent.

The launcher does not prove remote AgentSwitchboard orchestration, agents, providers, authentication, or a visible attachment. Those remain separate live certification stages.

## SSH boundary

The bootstrap and launcher do **not**:

- create SSH keys;
- copy credentials;
- disable host-key verification;
- edit remote SSH policy;
- infer a target from prior machines;
- assume an SSH target is POSIX;
- install packages or agents on the remote host.

`--host-profile posix-tmux` is an explicit adapter selection, not automatic detection. A future environment-classification implementation may replace that manual selection only after it can fail closed on unsupported remote shells.

## Android process boundary

Android and Termux impose process-lifetime and execution-environment constraints. Phone-local tmux is therefore not the preferred durability boundary for cross-device work. A separately managed always-on workspace host is the stronger topology, but it must still be classified and certified.

## Evidence

Local untracked state:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/
```

Artifacts:

- `bootstrap-result.env` — terminal-client installation evidence;
- `last-result.env` — last local or remote request boundary;
- `remote-preflight.env` — remote OS/shell, tmux, repository, origin, cleanliness, and session observations.

`attachment_observed=false` remains correct until an end-to-end live lane records the user-visible attachment.

## Validation

```bash
bash -n Bootstrap-AgentSwitchboard-Termux.sh
bash -n tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh
python3 tests/test_environment_capability_harness.py
python3 tests/test_android_termux_profile.py
python3 tests/test_device_profile_launcher_contract.py
```

Wider repository gates:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-EnvironmentCapabilityHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-DeviceProfileLauncherContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
```

## Proof ceiling

Tracked code and hosted CI can prove terminal-client contracts, argument validation, offline plans, fail-closed remote preflight logic, registry wiring, and forbidden proof promotion. They cannot prove a phone installation, SSH authentication, remote shell compatibility on a particular host, remote repository state, tmux attachment, Android process persistence, AgentSwitchboard orchestration, agent/provider readiness, or operator acceptance.
