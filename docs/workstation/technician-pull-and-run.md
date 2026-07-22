# Technician Pull and Run

Use one repository-owned CMD to obtain the current AgentSwitchboard code, verify that the checkout can be updated without discarding work, prepare the Windows Profile prerequisites, and open the requested terminal surface.

## What the CMD does

`Pull-And-Run-AgentSwitchboard.cmd`:

1. defaults the checkout to `%USERPROFILE%\Desktop\dev\AgentSwitchboard`;
2. clones `https://github.com/EndeavorEverlasting/AgentSwitchboard.git` when the checkout is absent;
3. verifies the existing `origin` when the checkout is present;
4. blocks on local changes or detached Git state;
5. fetches and uses `git pull --ff-only` for the requested ref;
6. hands off to the freshly pulled repository copy;
7. installs WezTerm through the official WinGet package when missing;
8. verifies the `Ubuntu` WSL distribution;
9. installs or verifies tmux, Antigravity CLI (`agy`), and OpenCode inside Ubuntu from their official installers;
10. invokes the canonical AgentSwitchboard Windows Profile launcher.

It never runs `git reset`, `git clean`, `git stash`, force-push, or destructive tmux cleanup. It does not edit `.wezterm.lua` or `.tmux.conf`.

## Current branch command

Until the pull request lands on `main`, open Command Prompt and run:

```cmd
curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/feat/technician-pull-and-run-cmd/Pull-And-Run-AgentSwitchboard.cmd -o "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" && call "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" shell "%USERPROFILE%\Desktop\dev\AgentSwitchboard" feat/technician-pull-and-run-cmd
```

After merge, the normal command is:

```cmd
curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/main/Pull-And-Run-AgentSwitchboard.cmd -o "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" && call "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" shell
```

## Modes

```cmd
Pull-And-Run-AgentSwitchboard.cmd shell
Pull-And-Run-AgentSwitchboard.cmd agy
Pull-And-Run-AgentSwitchboard.cmd opencode
Pull-And-Run-AgentSwitchboard.cmd setup
```

- `shell` installs or verifies prerequisites, then opens or activates the canonical `dev` tmux workspace in WezTerm.
- `agy` performs setup, opens the canonical workspace, and opens or selects an `agy` tmux window.
- `opencode` performs setup, opens the canonical workspace, and opens or selects an `opencode` tmux window.
- `setup` installs and verifies the prerequisites without launching WezTerm.

AGY and OpenCode authentication remains interactive. The CMD does not read, store, or print provider credentials.

## Expected prerequisites and blockers

- Git for Windows and PowerShell 7 must already be on `PATH`.
- When WezTerm is missing and WinGet is available, the CMD installs package `wez.wezterm` for the current machine according to WinGet policy.
- WSL and the `Ubuntu` distribution must already be initialized. When missing, the CMD stops with the exact `wsl --install -d Ubuntu` repair instruction because WSL installation may require elevation and a reboot.
- Installing tmux inside Ubuntu may prompt for the technician's Ubuntu `sudo` password.

## Evidence

Local, untracked setup evidence is written under:

```text
%LOCALAPPDATA%\AgentSwitchboard\technician-quickstart\runs\<run-id>\
```

Each run records a transcript and JSON summary. Command acknowledgement proves only that setup and launch requests completed. Authentication, provider responses, visible-window behavior, and agent task results require separate runtime observation.
