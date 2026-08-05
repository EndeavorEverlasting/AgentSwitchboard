# Technician Pull and Run

## Start here — one portable bootstrap

The technician should not need to know where the repository lives before starting. The production first-machine entrypoint is `AgentSwitchboard-Technician-Bootstrap.cmd`, pinned to `main`.

From **Command Prompt**, PowerShell, Downloads, Desktop, or the user profile, obtain and run the single bootstrap:

```cmd
curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/main/AgentSwitchboard-Technician-Bootstrap.cmd -o "%TEMP%\AgentSwitchboard-Technician-Bootstrap.cmd" && call "%TEMP%\AgentSwitchboard-Technician-Bootstrap.cmd"
```

Git for Windows, PowerShell 7, and `curl.exe` must be available for this first network bootstrap. WSL, Ubuntu, WezTerm, tmux, AGY, and OpenCode are **not** assumed to be ready.

## Repository binding across workstations

The bootstrap selects the checkout in this order:

1. explicit first argument;
2. `AGENT_SWITCHBOARD_REPO` environment override;
3. the bootstrap directory when it is already a Git checkout;
4. the current directory when it is already a Git checkout;
5. the verified per-machine binding at `%LOCALAPPDATA%\AgentSwitchBoard\state\repo-path.txt`;
6. known historical AgentSwitchBoard checkout candidates;
7. the portable new-machine default `%USERPROFILE%\dev\AgentSwitchBoard-Live`.

The default intentionally avoids Desktop and OneDrive redirection. Existing healthy checkouts at unusual paths are not moved: run the bootstrap once from that checkout or pass its path explicitly, and the verified path becomes that machine's binding.

The binding file is written only after canonical repository acquisition succeeds. A failed binding write is reported as a warning and is never presented as a pass.

## First-machine execution order

The production bootstrap owns this sequence:

```text
resolve/bind repository
    -> clone or fast-forward main only
    -> Repair-Technician-WSL-Ubuntu.cmd
    -> reboot boundary when Windows requires it
    -> Pull-And-Run-AgentSwitchboard.cmd setup
    -> Run-Technician-LiveCert.cmd
```

This order is deliberate. Repository acquisition must not require a pre-existing WSL installation, and workstation setup must not run until the WSL/Ubuntu prerequisite is healthy.

### Reboot boundary

When the WSL repair returns Windows exit code `3010`, the bootstrap stops with **REBOOT REQUIRED**. The repair registers a one-time same-user continuation. It does not automatically reboot the workstation.

After the reboot and the WSL repair continuation complete, run the same `AgentSwitchboard-Technician-Bootstrap.cmd` again from anywhere. The machine binding resolves the checkout, so the technician does not need to reconstruct the repository path.

## Repository acquisition safety

`Pull-Repo-And-Setup-AgentSwitchboard.cmd` downloads the reviewed `Pull-And-Run-AgentSwitchboard.cmd` and invokes its `acquire` mode. Acquisition:

1. clones `https://github.com/EndeavorEverlasting/AgentSwitchboard.git` when absent;
2. verifies the existing `origin` when present;
3. refuses dirty or detached checkouts;
4. fetches only the verified `origin` remote;
5. uses `git pull --ff-only` for the selected ref;
6. hands off to the freshly pulled repository copy;
7. stops before workstation setup.

It never runs `git reset`, `git clean`, `git stash`, force-push, or destructive tmux cleanup.

## Pull-and-run modes

```cmd
Pull-And-Run-AgentSwitchboard.cmd acquire
Pull-And-Run-AgentSwitchboard.cmd setup
Pull-And-Run-AgentSwitchboard.cmd shell
Pull-And-Run-AgentSwitchboard.cmd agy
Pull-And-Run-AgentSwitchboard.cmd opencode
Pull-And-Run-AgentSwitchboard.cmd hermes
```

- `acquire` clones or fast-forwards the repository and deliberately stops before workstation mutation.
- `setup` installs and verifies WezTerm, tmux, AGY, OpenCode, and PowerShell-visible command shims without launching WezTerm.
- `shell` performs core setup, then opens or activates the canonical `dev` tmux workspace in WezTerm.
- `agy` performs core setup, opens the canonical workspace, and opens or selects an `agy` tmux window using the resolved absolute WSL command path.
- `opencode` performs core setup, opens the canonical workspace, and opens or selects an `opencode` tmux window using the resolved absolute WSL command path.
- `hermes` remains optional and isolated from the core path.

AGY, OpenCode, and Hermes authentication remains interactive. The CMD does not read, store, or print provider credentials.

## WSL / Ubuntu first-machine repair

`Repair-Technician-WSL-Ubuntu.cmd` is the canonical first-machine repair. It may request same-user UAC elevation. It:

- enables Windows Subsystem for Linux system-wide;
- enables Virtual Machine Platform system-wide;
- treats Windows restart requirements as an explicit `3010` reboot boundary;
- registers one bounded same-user continuation rather than looping;
- updates WSL with one bounded web-download fallback;
- installs and registers Ubuntu for the current Windows user when missing;
- sets WSL 2 defaults;
- opens the official Ubuntu first-run initialization when the Linux account still needs to be created;
- verifies non-interactive Bash before reporting success.

It does not unregister distributions, invent a Linux password, enable passwordless sudo, or automatically restart Windows.

## Why tmux can run from PowerShell

`tmux` remains installed inside Ubuntu. Setup writes an AgentSwitchboard-owned Windows shim that delegates to the resolved tmux path inside the selected distribution. The same pattern is used for WSL-owned AGY and OpenCode commands.

WezTerm receives a shim pointing to the resolved Windows executable. This avoids depending on an already-open shell inheriting PATH changes made during setup.

## Live-cert sequence

After first-machine prerequisites and setup succeed, the bootstrap starts the tracked core live certificate:

```text
P00 Preflight
P01 Network
P02 Pull and Setup
P03 Verify Commands
P04 Launch Shell
P05 Launch AGY
P06 Launch OpenCode
P07 Repeatability
P08 Finalize
```

P09 Hermes remains optional and outside the core certificate.

When a stage fails, the orchestrator stops at the first failed boundary, names the mapped repair CMD, preserves evidence, and prints the exact resume command. Static or CI success never substitutes for target-workstation proof.

## Evidence

Local untracked setup evidence is written beneath:

```text
%LOCALAPPDATA%\AgentSwitchboard\technician-quickstart\runs\<run-id>\
```

Technician live-cert evidence is written beneath:

```text
%LOCALAPPDATA%\AgentSwitchboard\technician-live-cert\runs\<run-id>\
```

Command acknowledgement proves only that setup or launch requests completed. Authentication, provider response, visible-window behavior, tmux client attachment, repeatability, and field acceptance require their corresponding runtime observations.
