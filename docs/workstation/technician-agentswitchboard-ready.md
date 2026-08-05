# Technician AgentSwitchboard Ready

## Objective

Produce a useful AgentSwitchboard workstation, not merely a green prerequisite check.

The supported operator surface is a repository-owned command file. Do not paste multiline PowerShell, PowerShell prompts (`PS C:\...>`), continuation prompts (`>>`), command output, stack traces, or copied transcript text into an active shell.

## Canonical setup and launch

From the repository root:

```cmd
Technician-AgentSwitchboard-Ready.cmd shell
```

Supported modes: `shell`, `agy`, `opencode`, `setup`, and explicit isolated `hermes`.

The command owns these outcomes:

1. Resolve and verify WezTerm.
2. Verify initialized Ubuntu through WSL.
3. Install or repair tmux, AGY, and OpenCode inside Ubuntu.
4. Register fresh-shell Windows command shims for `AgentSwitchboard`, `wezterm`, `tmux`, `agy`, and `opencode`.
5. Run the canonical GNHF fleet setup without collecting credentials.
6. Require `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json`.
7. Run the canonical startup-readiness reporter.
8. Fail if readiness is `not-configured` or `blocked`.
9. Prove `AgentSwitchboard -ListAgents` in a fresh CMD process.
10. Create the `AgentSwitchboard.lnk` operator shortcut.
11. Write a unique technician-ready summary and transcript under `%LOCALAPPDATA%\AgentSwitchboard\technician-ready\runs`.

Hermes remains isolated. Core readiness does not depend on Hermes installation or browser authentication unless the operator explicitly selects `hermes`.

## Exact-head validation

Use the tracked validator rather than pasting an inline `if`/`else` script:

```cmd
Validate-Technician-ExactHead.cmd "<repo-path>" "<remote-ref>" "<expected-sha>"
```

The validator fetches only the named origin ref, verifies `FETCH_HEAD`, creates or safely reuses a detached worktree, runs Python plus Windows PowerShell 5.1 and PowerShell 7 validators, accepts only fresh P00 evidence, and prints and persists the actual worktree HEAD. It never resets, cleans, stashes, or force-pushes.

## Evidence

Technician setup is under `%LOCALAPPDATA%\AgentSwitchboard\technician-ready\runs\<runId>`. Exact-head validation is under `%LOCALAPPDATA%\AgentSwitchboard\exact-head-validation\runs\<runId>`. Canonical fleet state is `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json`.

## Proof ceiling

Local readiness proves installed commands, adapter discovery, canonical local fleet state, fresh-shell command resolution, and launcher command acknowledgement. It does not prove provider authentication, exact hosted-model availability, quota, hosted response, agent task quality, visible-window focus, or operator acceptance.
