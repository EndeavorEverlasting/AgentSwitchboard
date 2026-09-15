# Pi WSL workstation bootstrap

## Operator entrypoint

Double-click `Bootstrap-Pi-WSL.cmd` from an AgentSwitchboard checkout on Windows.

The launcher refreshes the canonical AgentSwitchboard checkout through the existing `Pull-And-Run-AgentSwitchboard.cmd` path, selects mode `bootstrap-pi-wsl`, and delegates to `tooling/pi/Install-AgentSwitchboardPiWsl.ps1`.

This is a **companion user-owned Ubuntu/WSL bootstrap**. It does not replace `Bootstrap-Pi-SystemWide.cmd`, which remains the native Windows machine-owned Pi lifecycle.

## What Apply owns

For the explicit `Ubuntu` distribution, the bootstrap may:

1. install only the bounded Ubuntu prerequisites `git`, `curl`, and `ca-certificates` when needed;
2. create or refresh `$HOME/.nvm` at `v0.40.7` when that checkout is clean;
3. install Node `24.21.0` through NVM and make it the default;
4. install `@earendil-works/pi-coding-agent@0.85.1` through the Linux-native npm owned by NVM;
5. reject `node`, `npm`, or `pi` when resolution leaks through `/mnt/...` Windows paths;
6. launch Pi interactively after a successful Apply.

`-Mode Inspect` is non-mutating and reports the current WSL paths and versions. `-NoLaunch` allows Apply validation without starting the Pi TUI.

## Authentication boundary

AgentSwitchboard does **not** choose a provider, copy another user's Pi credentials, read or write `~/.pi/agent/auth.json`, or automate OAuth/API-key entry.

After the first install, Pi opens for the current Linux user. If no provider is configured, use `/login` and choose the provider appropriate for that user. The operator's successful LPW003ASI173 run used OpenAI Codex, but that choice is not forced on other workstations.

## Existing-runtime safety

- An existing non-Git `$HOME/.nvm` blocks rather than being overwritten.
- A dirty NVM checkout blocks rather than being reset or cleaned.
- Windows package managers are not used.
- WSL distributions are not installed or removed by this lane.
- The native Windows Pi system bootstrap remains independently available.

## Proof ceiling

Repository tests and CI can prove the launcher/dispatcher/installer contract. The operator screenshot on LPW003ASI173 proves the manual Ubuntu → NVM → Node → npm Pi → OpenAI Codex login path works on one workstation. It does not by itself prove `Bootstrap-Pi-WSL.cmd` on a second workstation. That field observation is the next runtime proof after mainline integration.
