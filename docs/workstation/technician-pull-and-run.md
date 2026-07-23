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
7. installs or resolves WezTerm through the official WinGet package and known WinGet install roots;
8. verifies the `Ubuntu` WSL distribution;
9. installs or verifies tmux, Antigravity CLI (`agy`), and OpenCode inside Ubuntu from their official Linux installers;
10. resolves the absolute WSL path for each tool;
11. creates repo-owned Windows shims for `wezterm`, `tmux`, `agy`, and `opencode` beneath `%LOCALAPPDATA%\AgentSwitchboard\bin`;
12. registers the shim directory in the user PATH and verifies the commands from PowerShell;
13. invokes the canonical AgentSwitchboard Windows Profile launcher when a launch mode is requested.

It never runs `git reset`, `git clean`, `git stash`, force-push, or destructive tmux cleanup. It does not edit `.wezterm.lua` or `.tmux.conf`.

## Current branch command

Until the pull request lands on `main`, open **Command Prompt** and run:

```cmd
curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/feat/technician-pull-and-run-cmd/Pull-And-Run-AgentSwitchboard.cmd -o "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" && call "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" setup "%USERPROFILE%\Desktop\dev\AgentSwitchboard" feat/technician-pull-and-run-cmd
```

After setup succeeds, open a new PowerShell window and use:

```powershell
wezterm --version
tmux -V
agy --version
opencode --version
```

Then request the desired surface from Command Prompt or PowerShell:

```cmd
call "%USERPROFILE%\Desktop\dev\AgentSwitchboard\Pull-And-Run-AgentSwitchboard.cmd" shell
call "%USERPROFILE%\Desktop\dev\AgentSwitchboard\Pull-And-Run-AgentSwitchboard.cmd" agy
call "%USERPROFILE%\Desktop\dev\AgentSwitchboard\Pull-And-Run-AgentSwitchboard.cmd" opencode
```

After merge, the normal first command is:

```cmd
curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/main/Pull-And-Run-AgentSwitchboard.cmd -o "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" && call "%TEMP%\Pull-And-Run-AgentSwitchboard.cmd" setup
```

## Modes

```cmd
Pull-And-Run-AgentSwitchboard.cmd setup
Pull-And-Run-AgentSwitchboard.cmd shell
Pull-And-Run-AgentSwitchboard.cmd agy
Pull-And-Run-AgentSwitchboard.cmd opencode
Pull-And-Run-AgentSwitchboard.cmd hermes
```

- `setup` installs and verifies WezTerm, tmux, AGY, OpenCode, and the PowerShell-visible command shims without launching WezTerm.
- `shell` performs core setup, then opens or activates the canonical `dev` tmux workspace in WezTerm.
- `agy` performs core setup, opens the canonical workspace, and opens or selects an `agy` tmux window using the resolved absolute WSL command path.
- `opencode` performs core setup, opens the canonical workspace, and opens or selects an `opencode` tmux window using the resolved absolute WSL command path.
- `hermes` is isolated from the core path. It installs or resolves native Hermes and runs `hermes setup --portal` with one newline supplied before the browser handoff and a bounded timeout.

AGY, OpenCode, and Hermes authentication remains interactive. The CMD does not read, store, or print provider credentials.

## Why tmux can now run from PowerShell

`tmux` remains installed inside Ubuntu. The setup does not pretend it is a native Windows executable. Instead, it writes an AgentSwitchboard-owned `tmux.cmd` shim that delegates to the exact `/usr/bin/tmux` path inside the selected distribution. The same pattern is used for the WSL-owned AGY and OpenCode commands.

WezTerm receives its own shim pointing to the resolved Windows executable. This avoids relying on the current terminal inheriting a PATH update performed by WinGet.

## Hermes boundary

Hermes is no longer part of the default WezTerm/tmux/AGY/OpenCode setup. A Hermes install or browser-auth failure cannot block the requested core stack.

The explicit `hermes` mode supplies a newline to the child process before the browser handoff. If the browser or callback still hangs, the process is bounded and the run writes separate stdout and stderr evidence instead of requiring the technician to recover with Ctrl+C or `/debug`.

## July 22, 2026 live-cert report

The first reported technician deployment is classified as **failed**, despite prior green CI:

| Stage | Observed result |
|---|---|
| Repository pull | Pass |
| OpenCode installation | Pass |
| Hermes browser handoff | Fail — stalled before website launch and required Ctrl+C or `/debug` |
| AGY installation | Fail |
| WezTerm resolution from PowerShell | Fail |
| tmux resolution from PowerShell | Fail |

The sanitized fixture is stored at:

```text
tooling/profiles/windows/harness/live-certification/fixtures/technician-quickstart-2026-07-22-fail.fixture.json
```

The repair is not live-certified until the exact remote setup command is rerun on an authorized technician workstation.

## Expected prerequisites and blockers

- Git for Windows and PowerShell 7 must already be on `PATH`.
- When WezTerm is missing and WinGet is available, the CMD installs package `wez.wezterm` and resolves it from PATH, WinGet links, standard install roots, or the WinGet package root.
- WSL and the `Ubuntu` distribution must already be initialized. When missing, the CMD stops with the exact `wsl --install -d Ubuntu` repair instruction because WSL installation may require elevation and a reboot.
- Installing tmux inside Ubuntu may prompt for the technician's Ubuntu `sudo` password.

## Evidence

Local, untracked setup evidence is written under:

```text
%LOCALAPPDATA%\AgentSwitchboard\technician-quickstart\runs\<run-id>\
```

Each run records a transcript and JSON summary. Hermes mode also records bounded portal stdout and stderr. Command acknowledgement proves only that setup and launch requests completed. Authentication, provider responses, visible-window behavior, tmux client attachment, and agent task results require separate runtime observation.
