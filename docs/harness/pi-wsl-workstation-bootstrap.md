# Pi WSL workstation bootstrap

## Operator entrypoint

Double-click `Bootstrap-Pi-WSL.cmd` from an AgentSwitchboard checkout on Windows.

The launcher refreshes the canonical AgentSwitchboard checkout through the existing `Pull-And-Run-AgentSwitchboard.cmd` path, selects mode `bootstrap-pi-wsl`, and delegates to `tooling/pi/Install-AgentSwitchboardPiWsl.ps1`.

This is a **companion user-owned Ubuntu/WSL bootstrap**. It does not replace `Bootstrap-Pi-SystemWide.cmd`, which remains the native Windows machine-owned Pi lifecycle.

## What Apply owns

For the explicit `Ubuntu` distribution, the bootstrap may:

1. install only the bounded Ubuntu prerequisites `git`, `curl`, and `ca-certificates` when needed;
2. create `$HOME/.nvm` at bootstrap pin `v0.40.7` when NVM is absent;
3. preserve an existing clean functional user NVM checkout instead of changing its branch/tag state;
4. install Node `24.21.0` through NVM and make it the default;
5. install `@earendil-works/pi-coding-agent@0.85.1` through the Linux-native npm owned by NVM;
6. repair each required `.bashrc` NVM initialization line independently so partial initialization does not masquerade as complete setup;
7. reject `node`, `npm`, or `pi` when resolution leaks through `/mnt/...` Windows paths;
8. launch Pi interactively after a successful Apply.

Noninteractive Inspect/Apply WSL work is bounded (`120s` Inspect, `1800s` Apply) and kills the WSL process tree on timeout with `STATUS=BLOCKED_WSL_TIMEOUT`. The final Pi TUI is intentionally unbounded because it is the operator's interactive session.

`-Mode Inspect` is non-mutating and reports the current WSL paths and versions. `READY` requires Linux-native NVM-owned `node`, `npm`, and `pi`, exact Node `24.21.0`, exact Pi `0.85.1`, and a functional NVM command; drift returns a non-ready result. `-NoLaunch` allows Apply validation without starting the Pi TUI.

## Authentication boundary

AgentSwitchboard does **not** choose a provider, copy another user's Pi credentials, read or write `~/.pi/agent/auth.json`, or automate OAuth/API-key entry.

After the first install, Pi opens for the current Linux user. If no provider is configured, use `/login` and choose the provider appropriate for that user. The operator's successful LPW003ASI173 run used OpenAI Codex, but that choice is not forced on other workstations.

## Existing-runtime safety

- An existing non-Git `$HOME/.nvm` blocks rather than being overwritten.
- A dirty NVM checkout blocks rather than being reset or cleaned.
- An existing clean functional NVM checkout is preserved in place; `v0.40.7` is the bootstrap pin only for a newly created NVM checkout.
- Windows package managers are not used.
- WSL distributions are not installed or removed by this lane.
- The native Windows Pi system bootstrap remains independently available.

## Proof ceiling

Repository tests and CI can prove the launcher/dispatcher/installer contract. The operator screenshot on LPW003ASI173 proves the manual Ubuntu → NVM → Node → npm Pi → OpenAI Codex login path works on one workstation. It does not by itself prove `Bootstrap-Pi-WSL.cmd` on a second workstation. That field observation is the next runtime proof after mainline integration.
