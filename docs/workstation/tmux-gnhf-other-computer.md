# Install WezTerm, tmux, AgentSwitchboard, and GNHF on Another Windows Computer

This guide is for a Windows computer where the intended coding experience is:

```text
WezTerm -> tmux -> coding agent -> GNHF bounded worktree run
```

WSL is the Windows backend that hosts Linux and tmux. It is not the user-facing goal. PowerShell 7 performs the Windows-side setup. WezTerm is the graphical terminal. Bash runs inside WSL. tmux is the persistent workspace inside Bash.

## What is automated

`Install-TmuxGnhfWorkspace.ps1` automates the checks that should not be delegated to the operator:

- validates the manifest;
- reuses the existing AgentSwitchboard WSL bootstrap;
- detects or installs the selected WSL distribution;
- installs the declared Linux packages, including tmux;
- verifies Node 20 or newer;
- when necessary, installs a checksum-verified official Node LTS archive without pipe-to-shell execution;
- installs GNHF from its published npm package;
- installs the configured default agent inside WSL when missing;
- creates an isolated, capped `gnhf-safe` wrapper;
- configures `~/.gnhf/config.yml` without overwriting an existing customized config by default;
- disables GNHF telemetry when requested;
- renders a WezTerm configuration that opens or attaches to tmux session `dev`;
- starts a hidden, owned WSL keepalive so tmux can survive visible terminal closure;
- generates Start, Status, and destructive Stop scripts;
- creates an optional Windows desktop shortcut;
- performs automated command-level validation and writes local state evidence.

It does **not** authenticate coding agents, call a paid model, or prove that an agent completed useful work.

## Before beginning

Use the computer's administrator account when Windows installation policy requires it.

Required or automatically planned:

- Windows 10 or 11 with WSL support;
- PowerShell 7;
- Git;
- WinGet for automatic WezTerm installation;
- an internet connection for WSL packages, official Node downloads, npm packages, and repository cloning.

The bootstrap does not unregister or reset WSL. Existing repositories and dotfiles are preserved or backed up.

## 1. Clone AgentSwitchboard

### WINDOWS POWERSHELL 7

Open **PowerShell 7** from the Windows Start menu. The prompt should begin with `PS`.

```powershell
New-Item -ItemType Directory -Path "$HOME\Desktop\dev" -Force | Out-Null
Set-Location "$HOME\Desktop\dev"

git clone https://github.com/EndeavorEverlasting/AgentSwitchboard.git
Set-Location .\AgentSwitchboard
```

Until the integration branch is merged, check out the PR branch named in the pull request for this feature. After merge, stay on `main`.

```powershell
git fetch --all --prune
git status --short
git branch --show-current
```

Do not continue from a dirty checkout. Preserve unknown files and use a clean clone or worktree.

## 2. Copy and review the manifest

### WINDOWS POWERSHELL 7

```powershell
Copy-Item `
  .\tooling\wsl\tmux-gnhf-workstation.example.json `
  .\tooling\wsl\tmux-gnhf-workstation.local.json

notepad.exe .\tooling\wsl\tmux-gnhf-workstation.local.json
```

The JSON file is **FILE CONTENT**. Edit it in Notepad or an editor. Do not paste JSON directly at a PowerShell or Bash prompt.

Important defaults:

- WSL distribution: `Ubuntu`;
- tmux session: `dev`;
- GNHF default agent: `opencode`;
- GNHF telemetry: disabled;
- worktree mode: enabled;
- automatic push: disabled;
- maximum iterations: 10;
- maximum tokens: 5,000,000.

The runtime caps are placed in `gnhf-safe` because GNHF documents iteration and token caps as runtime-only flags rather than persistent `config.yml` values.

## 3. Run the read-only plan

### WINDOWS POWERSHELL 7

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\wsl\Install-TmuxGnhfWorkspace.ps1 `
  -ManifestPath .\tooling\wsl\tmux-gnhf-workstation.local.json
```

No `-Apply` switch means plan mode. Review the output for:

- WSL or reboot requirements;
- the selected distribution;
- packages that would be installed;
- Node and npm posture;
- GNHF and OpenCode posture;
- WezTerm installation;
- configuration replacement or preservation decisions;
- shortcut and persistent-workspace actions.

If a reboot is required, reboot Windows and rerun the plan. Do not add `-ForceRebootAck` to skip a real reboot requirement during live setup.

## 4. Apply the setup

### WINDOWS POWERSHELL 7

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\wsl\Install-TmuxGnhfWorkspace.ps1 `
  -ManifestPath .\tooling\wsl\tmux-gnhf-workstation.local.json `
  -Apply
```

On a new computer with no `.wezterm.lua`, the script installs the managed configuration directly.

When an existing unmanaged `C:\Users\<you>\.wezterm.lua` is found, the script preserves it and writes a proposed configuration under the AgentSwitchboard install root. Review the proposed file before intentionally rerunning with:

```powershell
-ReplaceExistingWezTermConfig
```

That switch is not necessary on a clean machine and should not be used casually.

The Linux package manager may request the WSL user's password for `sudo`. The bootstrap never asks for an agent token or performs provider login.

## 5. Use the generated shortcut

The setup creates a desktop shortcut named:

```text
AgentSwitchboard tmux
```

Double-click it. Do not keep the setup PowerShell window open. The shortcut launches an independent `wezterm-gui.exe` process.

The new window should already be inside tmux. A tmux status line is visible at the bottom.

Do **not** type `tmux` again when the status line is present.

## 6. Verify the environment

### WEZTERM / TMUX BASH

Type these commands inside the newly opened WezTerm window:

```bash
printf 'shell=%s\n' "$SHELL"
printf 'inside_tmux=%s\n' "${TMUX:+yes}"
tmux -V
tmux display-message -p 'session=#{session_name}'
node --version
gnhf --version
opencode --version
command -v gnhf-safe
```

Expected essentials:

```text
inside_tmux=yes
session=dev
tmux 3.x
node v20 or newer
```

The installer writes a local summary inside WSL at:

```text
~/.local/state/agent-switchboard/tmux-gnhf/setup-summary.json
```

The Windows-side setup summary and generated scripts live under the manifest's `workspace.installRoot`.

## 7. Authenticate the selected agent manually

### WEZTERM / TMUX BASH

AgentSwitchboard does not automate account authentication. Follow the selected agent's own login or provider-configuration process.

For OpenCode, confirm that a usable provider is configured before starting an unattended GNHF run. A version response only proves command availability, not authentication or model readiness.

## 8. Run a bounded GNHF sprint

GNHF must be run from a Git repository with a clean working tree. The managed wrapper uses worktree isolation, does not push, prevents sleep, and applies the configured iteration and token caps.

### WEZTERM / TMUX BASH

```bash
cd ~/dev/agents/AgentSwitchboard
git status --short
git branch --show-current

gnhf-safe "improve one bounded, well-tested part of the repository"
```

Do not start GNHF from a dirty working tree. Do not use automatic push for the first run. Review the resulting branch, commits, `.gnhf/runs/` evidence, and morning summary before merging anything.

GNHF stores local run metadata under `.gnhf/runs/`, commits each successful iteration, rolls back ordinary failed iterations, and preserves worktree branches with commits for review. GNHF's upstream behavior and flags can change, so the AgentSwitchboard validator must remain pinned to the supported contract.

## 9. Detach and reconnect

### WEZTERM / TMUX KEYSTROKES

To detach without ending the session:

1. Press `Ctrl+B`.
2. Release both keys.
3. Press `D`.

Reopen the **AgentSwitchboard tmux** shortcut. It should attach to the same `dev` session.

### WINDOWS POWERSHELL 7

Check status without opening the GUI:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\tmux-gnhf\Get-TmuxGnhfWorkspaceStatus.ps1" |
  Format-List
```

A command acknowledgment is not proof of persistence. Confirm that the same tmux windows return after closing and reopening WezTerm.

## 10. Stop the persistent workspace intentionally

Stopping the workspace terminates the tmux session and any agents running inside it.

### WINDOWS POWERSHELL 7

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\tmux-gnhf\Stop-TmuxGnhfWorkspace.ps1"
```

PowerShell displays a high-impact confirmation prompt. Do not run the Stop script merely to close the visible WezTerm window.

## FILE CONTENT versus shell commands

- PowerShell blocks go into **WINDOWS POWERSHELL 7**.
- Bash blocks go into **WEZTERM / TMUX BASH**.
- JSON, YAML, Lua, and configuration examples are **FILE CONTENT** and belong in the named file, not directly in a shell prompt.
- WezTerm reads Lua configuration. PowerShell does not execute the Lua file.

## Known gaps

- Contract and fixture tests do not prove live WSL installation or GUI behavior.
- The first live run may require a Windows reboot before WSL is usable.
- Existing unmanaged WezTerm and GNHF configurations are preserved, which may require manual review before replacement.
- GNHF installation does not authenticate an agent or configure paid-provider credentials.
- `gnhf-safe` defaults to OpenCode. Other agents require explicit AgentSwitchboard integration and readiness proof.
- The WSL keepalive preserves tmux only while Windows is running. A Windows restart ends the session.
- Native Linux and WSL are separate execution domains; success in WSL is not native-Linux proof.
- The generated workspace status proves processes and tmux metadata, not that an agent is responsive.
- GNHF upstream may add or change agents, flags, configuration fields, telemetry behavior, or failure handling. Review upstream changes before raising the supported version range.

## Risks

- Unattended coding agents can make incorrect or overly broad changes even when isolated in worktrees.
- GNHF may reset ordinary failed iterations. Never point it at unknown uncommitted work.
- Large iteration or token caps can consume significant provider quota.
- Windows-to-WSL executable bridges can have path, signal, and terminal-mode differences. The managed GNHF default uses a WSL-native OpenCode installation instead.
- Killing WSL, ending the keepalive, or running the Stop script terminates the persistent tmux workspace.

## Next steps after installation

1. Prove detach, close, reopen, and same-session recovery.
2. Prove the selected agent responds inside tmux.
3. Run one small GNHF worktree sprint with low caps.
4. Review every generated commit and the GNHF exit summary.
5. Record exact failures in AgentSwitchboard fixtures and validators.
6. Only then consider additional agents, larger caps, multiple parallel worktrees, or scheduled unattended runs.

## Impact

Once live proof is complete, the setup removes the need to remember which terminal receives which command. A new Windows machine can be prepared through one plan/apply entrypoint, while AgentSwitchboard preserves configuration boundaries, GNHF uses bounded worktrees, tmux provides persistent sessions, and all authentication remains an explicit human action.
