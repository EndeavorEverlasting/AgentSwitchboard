# Android → SSH → tmux Live Certificate

This guide proves one thing at a time. It separates:

1. **phone → Windows laptop SSH transport**;
2. **phone → WSL/tmux continuity through a manual Windows hop**;
3. **phone → POSIX/tmux workspace using the repo-owned `agentswitchboard-phone remote` launcher**.

Do not collapse those into one certificate. The current Android launcher supports only a POSIX/tmux SSH endpoint. A normal Windows OpenSSH endpoint is useful for a manual transport test, but it is not a supported `--host-profile posix-tmux` target.

## Audience

Use this when Termux is already installed and you want to prove that your Android phone can reach a durable coding workspace without pretending that phone-local tmux, Windows OpenSSH, WSL tmux, and a Linux server are one environment.

Start with [`android-termux.md`](android-termux.md) if Termux or `agentswitchboard-phone` is not installed yet.

---

# Certificate model

A successful continuity certificate identifies all of these:

```text
frontend       = Android / Termux
transport      = SSH
workspace host = the machine/environment that owns the repository and tmux server
session        = the exact tmux server/session identity
orchestration  = separately proved; not inferred from SSH or tmux
agent runtime  = separately proved; not inferred from SSH or tmux
```

The shortest useful question is:

> When I detach on one device and reconnect from the other, am I looking at the **same tmux session on the same workspace host**?

A matching session name alone is not enough.

---

# Path A — Manual phone → Windows laptop SSH transport certificate

This path is appropriate when your laptop already exposes Windows OpenSSH and you want to prove network reachability/authentication first.

It is **not** a certificate for the repo-owned `agentswitchboard-phone remote` command, because that command currently sends POSIX `sh` preflight commands to the SSH endpoint.

## A1. Laptop: read-only checks first

On the **Windows laptop**, open PowerShell.

Check whether the SSH server service exists and whether it is running:

```powershell
Get-Service -Name sshd -ErrorAction SilentlyContinue
```

If it exists, the expected running state is:

```text
Status   Name
------   ----
Running  sshd
```

Check whether something is listening on TCP port 22:

```powershell
Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
```

Find the laptop's local IPv4 addresses:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' } |
  Select-Object InterfaceAlias,IPAddress
```

Choose the address associated with the network the phone is actually using. On a first certificate, keep phone and laptop on the same trusted LAN/Wi-Fi rather than exposing SSH directly to the public internet.

Find the Windows account name:

```powershell
whoami
```

## A2. If Windows OpenSSH Server is missing

Installing or changing Windows OpenSSH Server is an operating-system administrator action, not an AgentSwitchboard repository mutation.

From an elevated PowerShell session, Windows' OpenSSH Server capability is commonly managed with:

```powershell
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
```

If the capability is `NotPresent` and you intentionally want Windows to accept SSH, install/start it using your Windows administration policy and Microsoft's OpenSSH Server documentation. Do not weaken firewall or host-key policy merely to make the certificate pass.

After any administrator setup, return to the read-only checks above and prove `sshd` is running and port 22 is listening.

## A3. Phone: make the first SSH connection

On the **Android phone in Termux**:

```bash
ssh WINDOWS_USER@WINDOWS_LAN_IP
```

Replace `WINDOWS_USER` and `WINDOWS_LAN_IP` with the values you just observed. They are machine-specific operator inputs, not universal repository defaults.

On a first connection, OpenSSH may ask whether to trust a host fingerprint. Do not automatically accept an unexpected fingerprint. Confirm that the target address and machine are the laptop you intended to reach.

After authentication succeeds, run on the remote Windows shell:

```powershell
hostname
whoami
```

### Pass condition for Path A

Path A passes when:

- the phone establishes SSH to the intended Windows laptop;
- host identity was intentionally accepted/verified;
- `hostname` identifies the laptop;
- `whoami` identifies the expected Windows account.

This proves **SSH transport to Windows**. It does not yet prove WSL, tmux, AgentSwitchboard, a repository, or coding-agent readiness.

---

# Path B — Manual Windows → WSL → tmux continuity certificate

Use this when your existing laptop workflow lives in WSL and you are comfortable using Windows SSH as a manual hop.

This is a valid human-operated path, but the current `agentswitchboard-phone remote` launcher does not automate this Windows-to-WSL hop.

## B1. Laptop: create or identify the WSL tmux session

On the laptop, enter the WSL distribution you normally use:

```powershell
wsl
```

Inside **WSL**:

```bash
hostname
printf 'user=%s\n' "$USER"
command -v tmux
```

Enter the repository you actually use in WSL and confirm its identity:

```bash
cd /absolute/path/to/AgentSwitchboard
git remote get-url origin
git status --short --branch
```

The origin should be the repository you intend to work in. Do not copy the example path literally; WSL repository locations are operator-specific.

Create or attach a named tmux session:

```bash
tmux new-session -A -s dev
```

Inside that tmux session, print its identity:

```bash
hostname
tmux display-message -p 'session=#S socket=#{socket_path} client=#{client_name}'
pwd
```

Record the `hostname`, `session`, `socket`, and working directory. Those are your continuity identity.

Detach with:

```text
Ctrl-b, then d
```

Do not kill the tmux session.

## B2. Phone: reconnect through Windows and enter WSL

From Termux:

```bash
ssh WINDOWS_USER@WINDOWS_LAN_IP
```

After the Windows shell opens:

```powershell
wsl
```

Inside WSL:

```bash
tmux attach-session -t dev
```

Then print the same identity fields:

```bash
hostname
tmux display-message -p 'session=#S socket=#{socket_path} client=#{client_name}'
pwd
```

### Pass condition for Path B

Path B passes only when the phone sees:

- the same WSL host identity;
- the same tmux **socket/server**;
- the same tmux session name;
- the expected repository working directory or workspace state.

If the phone sees a session named `dev` but the socket/host differs, it is a different session and continuity has **not** been proved.

### Durability boundary

This workflow depends on the laptop being awake, powered, network-reachable, and able to keep the WSL/tmux process alive. Laptop sleep removes network reachability even if tmux itself is otherwise healthy.

That is why a Linux VPS or other always-on POSIX workspace host can eventually be a stronger continuity target. It is not automatically the better first setup if your laptop already contains the working environment you trust.

---

# Path C — Repo-owned Android remote launcher to a POSIX/tmux endpoint

This is the current automated Android path.

The SSH endpoint itself must accept the POSIX adapter used by the launcher. Typical shapes include a Linux server/VPS or another SSH endpoint that lands directly in a POSIX shell with `sh`, `git`, and `tmux` available.

A Windows OpenSSH shell that then requires the operator to type `wsl` does **not** satisfy this adapter.

## C1. Remote host prerequisites

On the intended POSIX workspace host, the current launcher expects:

- `sh` execution through SSH;
- `tmux` installed;
- the AgentSwitchboard Git repository at a known absolute path;
- the repository origin to match the expected origin supplied by the operator;
- a clean working tree before launcher-managed attachment/session creation;
- the chosen tmux session to exist, unless `--create` is explicitly supplied.

The launcher does not install packages remotely.

## C2. Phone: verify local client state

On Termux:

```bash
agentswitchboard-phone status
```

Expected capability ceiling:

```text
capability_status=terminal-client-implemented
role=terminal-client
local_tmux_role=local-shell-only
cross_device_continuity=requires-remote-workspace-host
native_orchestration_runtime=unimplemented
native_agent_runtime=unproved
```

## C3. Plan the remote request

Use an SSH target that you have deliberately configured and a real absolute repository path from the remote host:

```bash
agentswitchboard-phone remote HOST \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev \
  --plan
```

Expected shape:

```text
PLAN profile=android capability_status=terminal-client-implemented role=terminal-client topology=android-termux-ssh-posix-workspace-client ... host_profile=posix-tmux ...
```

`--plan` does not contact or mutate the remote host.

## C4. Run read-only remote preflight and attach to an existing session

When the target, repository path, origin, and session are correct:

```bash
agentswitchboard-phone remote HOST \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev
```

The launcher first performs remote preflight. It records:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/remote-preflight.env
```

Inspect it after the connection ends:

```bash
cat "${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/remote-preflight.env"
```

Passing fields should include:

```text
tmux_status=ready
repository_status=present
origin_status=expected
working_tree_status=clean
session_status=present
preflight=pass
```

The exact remote OS and shell fields depend on the target.

## C5. Create a missing remote session only when intended

If preflight says the session is absent, the launcher blocks by default. That is deliberate.

Only when you intend to create the remote session:

```bash
agentswitchboard-phone remote HOST \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev \
  --create
```

The launcher creates the session with the remote repository as its working directory, rechecks the session, then attaches over SSH.

## C6. Prove the visible session identity after attachment

Inside the attached remote tmux session:

```bash
hostname
tmux display-message -p 'session=#S socket=#{socket_path} client=#{client_name}'
pwd
git remote get-url origin
git status --short --branch
```

Compare the host/socket/session against the laptop or other client that is supposed to share this workspace.

### Pass condition for Path C

The live continuity certificate passes when:

- launcher preflight passes on the intended POSIX host;
- SSH attachment visibly opens the expected tmux session;
- the workspace host identity matches the intended host;
- both clients observe the same tmux socket/server and session;
- the working directory/repository is the intended checkout.

The current launcher writes `attachment_observed=false` because the shell script itself cannot prove what the human visibly saw in the terminal. Operator observation is the missing live proof.

---

# Failure interpretation

## `ssh: connect to host ... port 22: Connection refused`

The target is reachable enough to refuse the connection, but no acceptable SSH service is listening at that address/port, or a local policy is rejecting it. Check the intended host and SSH service. Do not disable security controls blindly.

## SSH times out

Common possibilities include wrong IP/address, laptop sleep, different network, routing/firewall policy, or unreachable server. Re-establish simple network reachability before changing authentication.

## Host-key warning or changed host identification

Stop and verify the host. The repo-owned launcher intentionally preserves normal OpenSSH host-key checking. Do not solve this by adding `StrictHostKeyChecking=no`.

## `remote preflight failed`

Inspect:

```bash
cat "${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/remote-preflight.env"
```

Current remote preflight exit meanings are:

| Exit | Meaning |
|---:|---|
| 41 | `tmux` missing on remote host |
| 42 | repository missing/not a Git checkout at supplied path |
| 43 | remote origin does not equal the supplied expected origin |
| 44 | remote working tree is dirty |

Those failures are blockers, not invitations to auto-repair an unknown host.

## Session is absent

Without `--create`, this is a safe block. Confirm the session name and host before deciding to create anything remotely.

## Remote session creation exits 51

The launcher attempted the explicitly authorized tmux create operation and could not prove the session exists afterward. Treat that as a failed mutation; do not claim attachment success.

## Repository is dirty

The current remote launcher blocks. Inspect changes on the workspace host and preserve separately owned work. Do not reset or clean merely to satisfy the launcher.

---

# Safe defaults

- Start on a trusted LAN for the Windows laptop certificate.
- Do not expose Windows port 22 directly to the internet as a shortcut.
- Do not disable SSH host-key checking.
- Do not paste passwords, tokens, private keys, or credential output into issue/PR logs.
- Do not auto-install packages on an unclassified remote host.
- Do not create a remote tmux session without `--create` and operator intent.
- Do not call a Windows SSH endpoint `posix-tmux` merely because WSL also exists on that laptop.
- Do not call phone-local tmux cross-device continuity.

---

# Rollback and cleanup

## End a phone SSH client connection

Inside the remote shell, exit back through each layer deliberately:

```text
exit
```

If you are inside tmux and want the session to continue, detach with `Ctrl-b`, then `d` before exiting SSH.

## Do not kill the continuity session during a normal disconnect

`tmux kill-session` destroys the selected server session and stops programs running inside it. Use it only when you intentionally want to terminate that workspace.

## Remove an accidental SSH host entry

Do not blindly delete `~/.ssh/known_hosts` after a host-key warning. Identify and verify the specific host first, then use your normal OpenSSH host-key maintenance process if the host really changed.

---

# Evidence to retain for a live certificate

Record non-secret output for:

1. phone `agentswitchboard-phone status`;
2. intended workspace `hostname`;
3. `tmux display-message -p 'session=#S socket=#{socket_path}'` from each client;
4. repository `git remote get-url origin`;
5. repository `git status --short --branch`;
6. Android `remote-preflight.env` for Path C;
7. operator statement that the expected tmux workspace was visibly observed.

Do **not** retain passwords, private keys, PATs, cookies, provider tokens, or authentication prompts as proof artifacts.

---

# Proof ceiling

Passing Path A proves phone → Windows SSH transport.

Passing Path B proves a manual phone → Windows → WSL path can reach the same WSL tmux server/session when host/socket/session identity matches.

Passing Path C proves the repo-owned Android terminal client can preflight and request attachment to a classified POSIX/tmux workspace when operator-visible identity is confirmed.

None of those certificates, by themselves, prove native Android AgentSwitchboard orchestration, remote GNHF readiness, coding-agent/provider authentication, model access, or successful code delivery.
