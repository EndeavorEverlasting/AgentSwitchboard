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

## Exact-head field acceptance

Use the tracked validator rather than pasting an inline `if`/`else` script.

Validation-only mode:

```cmd
Validate-Technician-ExactHead.cmd "<repo-path>" "<remote-ref>" "<expected-sha>" validate
```

Complete field-readiness mode:

```cmd
Validate-Technician-ExactHead.cmd "<repo-path>" "<remote-ref>" "<expected-sha>" ready
```

`ready` mode requires the explicit remote ref and expected SHA. It then performs one owned sequence:

1. Verify the origin URL.
2. Fetch only the named remote ref.
3. Compare `FETCH_HEAD` with the expected SHA.
4. Create or safely reuse an exact detached worktree without modifying the operator checkout.
5. Run Python, Windows PowerShell 5.1, and PowerShell 7 validators.
6. Generate the harness-status artifact.
7. Run P00 and accept only a new preflight artifact created after that invocation began.
8. Run `Technician-AgentSwitchboard-Ready.cmd setup` from the exact worktree.
9. Accept only a new technician-ready summary created after readiness began.
10. Require successful startup readiness, observed canonical fleet state, a real `AgentSwitchboard` command shim, and a usable status other than `not-configured` or `blocked`.
11. Persist the actual worktree HEAD, P00 artifact, readiness status, and readiness artifact in JSON and Markdown.

The validator never resets, cleans, stashes, force-pushes, or treats the requested SHA as proof. The persisted and displayed verified SHA comes from the detached worktree after equality validation.

## Evidence

Technician setup is under `%LOCALAPPDATA%\AgentSwitchboard\technician-ready\runs\<runId>`. Exact-head field acceptance is under `%LOCALAPPDATA%\AgentSwitchboard\exact-head-validation\runs\<runId>`. Canonical fleet state is `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json`.

## Proof ceiling

Local readiness proves installed commands, adapter discovery, canonical local fleet state, fresh-shell command resolution, and launcher command acknowledgement. It does not prove provider authentication, exact hosted-model availability, quota, hosted response, agent task quality, visible-window focus, or operator acceptance.
