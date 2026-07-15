# Technician Quick Start: AgentSwitchboard tmux + GNHF Workstation

Use this page when setting up the owner's workstation or a technician's Windows computer. The normal path requires **one repository clone and one CMD launcher**. You do not need to copy PowerShell, Bash, JSON, Lua, or tmux commands out of a chat.

## What this installs and configures

```text
Windows
  -> WSL Ubuntu
  -> tmux session dev
  -> WSL-native Node 20+
  -> GNHF 0.1.42
  -> WSL-native OpenCode
  -> WezTerm
  -> AgentSwitchboard tmux desktop shortcut
```

The setup preserves unmanaged configuration, creates local logs, uses a bounded GNHF worktree wrapper, and stops instead of pretending a required reboot occurred.

It does **not** authenticate providers, collect tokens, call a paid model during validation, push Git branches, unregister WSL, or prove that an agent completed useful model work.

## Step 1: Use the daily Windows account

Sign into the Windows account that will use WezTerm, WSL, tmux, and GNHF every day.

A Windows UAC prompt may appear only when Windows features must be enabled. The elevated step enables those features and then stops for reboot. User configuration resumes later under the same daily account.

## Step 2: Clone the current integration branch once

### WINDOWS POWERSHELL 7

```powershell
New-Item -ItemType Directory -Force "$HOME\Desktop\dev" | Out-Null
git clone --branch feat/tmux-gnhf-workstation-bootstrap --single-branch https://github.com/EndeavorEverlasting/AgentSwitchboard.git "$HOME\Desktop\dev\AgentSwitchboard"
```

After the stacked pull requests merge, clone `main` instead.

## Step 3: Double-click the setup CMD

Open this folder in File Explorer:

```text
Desktop\dev\AgentSwitchboard
```

Double-click:

```text
Setup-TmuxGnhfWorkspace.cmd
```

The launcher will:

1. create a computer-local manifest from safe defaults when none exists;
2. check WSL and Ubuntu before invoking deeper setup;
3. enable only the required Windows features through UAC when necessary;
4. stop honestly for reboot or Ubuntu first-run initialization;
5. run a read-only repository plan;
6. require the exact word `INSTALL` before apply;
7. install Linux packages as WSL root without storing the Linux password;
8. run the repository-owned installer and validators;
9. write a durable local log and JSON summary;
10. keep the window open so the result cannot disappear.

When the launcher says reboot is required, reboot, sign into the same daily Windows account, and double-click the **same CMD** again. Do not search for a replacement command.

## Step 4: Know the two safe confirmations

Depending on computer state, the launcher may ask for one of these exact words:

| Prompt | Meaning |
|---|---|
| `ENABLE` | Enable the WSL and VirtualMachinePlatform Windows features, then stop for reboot. |
| `INSTALL` | Install Ubuntu or apply the reviewed workstation plan. |

When the setup reaches apply, **type INSTALL** exactly. Any other response stops without beginning that stage.

## Step 5: Find the logs

Every click creates a separate run directory:

```text
%LOCALAPPDATA%\AgentSwitchboard\tmux-gnhf\setup-runs\<timestamp>\
```

Important files:

```text
operator.log
operator-summary.json
post-validation.json
wsl-base.runtime.json
tmux-gnhf-workstation.runtime.json
```

The runtime manifests are local evidence. They are not written back into the repository and contain no provider credentials.

Exit codes shown by the CMD:

| Code | Meaning |
|---:|---|
| `0` | Plan or setup completed. |
| `10` | Operator cancelled before apply. |
| `20` | Required Windows prerequisite is unavailable. |
| `30` | Reboot, distribution installation, or first-run continuation is required. Run the same CMD again afterward. |
| `40` | Apply failed. Read `operator.log`. |
| `50` | Installation occurred but post-install validation failed. |

## Step 6: Open the persistent workspace

After a successful setup, double-click the desktop shortcut:

```text
AgentSwitchboard tmux
```

WezTerm should open already attached to tmux session:

```text
dev
```

Do not type `tmux` again when a tmux status bar is already visible.

## Step 7: Authenticate OpenCode manually

### WEZTERM / TMUX BASH

AgentSwitchboard deliberately leaves provider authentication to the operator. Configure OpenCode through its supported provider flow.

A successful version check proves only that the executable exists:

```bash
opencode --version
```

It does not prove that a provider, model, credit balance, or hosted response is ready.

## Step 8: Run the first bounded sprint

Use a small clean repository first.

### WEZTERM / TMUX BASH

```bash
cd ~/dev/agents/AgentSwitchboard
git status --short
gnhf-safe "inspect one small documentation defect, fix it only when confirmed, validate it, and stop"
```

Do not proceed when `git status --short` prints unknown work.

The managed wrapper supplies worktree isolation, no automatic push, a 10-iteration cap, a 5,000,000-token cap, and sleep prevention. Review every resulting commit before merging or pushing.

## Existing configuration safeguard

An unmanaged Windows `.wezterm.lua` or customized GNHF config is preserved rather than blindly replaced. The failure log identifies the proposed file and the deliberate advanced switch required for replacement.

Technicians must not use replacement switches merely to make an error disappear.

## Technician completion checklist

Record these outcomes in the ticket or handoff:

- setup CMD exit code;
- `operator-summary.json` status;
- whether a reboot occurred;
- whether Ubuntu first-run initialization completed;
- whether the **AgentSwitchboard tmux** shortcut opens WezTerm;
- whether tmux reports session `dev`;
- whether `gnhf --version` reports `0.1.42`;
- whether `opencode --version` resolves;
- provider authentication: completed manually / not completed;
- detach and reopen persistence: observed / not observed;
- hosted model response: observed / not observed.

Do not mark authentication, persistence, or hosted model response as proven merely because installation passed.
