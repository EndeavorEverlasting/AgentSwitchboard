# Technician AgentSwitchboard Ready

## Objective

Produce a useful AgentSwitchboard workstation, not merely a green prerequisite check.

The supported operator surface is a repository-owned command file. Do not paste multiline PowerShell, PowerShell prompts (`PS C:\...>`), continuation prompts (`>>`), command output, stack traces, or copied transcript text into an active shell.

## Canonical setup and launch

From a current repository checkout:

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

From a current checkout:

```cmd
Validate-Technician-ExactHead.cmd "<repo-path>" "<remote-ref>" "<expected-sha>" ready
```

When the current checkout predates `Validate-Technician-ExactHead.cmd`, bootstrap the exact validator from the named commit without switching, resetting, cleaning, or overwriting that checkout:

```powershell
$repo='<repo-path>'; $sha='<expected-sha>'; $runner=Join-Path $env:TEMP ('AgentSwitchboard-ExactHead-'+$sha.Substring(0,8)+'.ps1'); & git.exe -C $repo fetch --no-tags origin refs/heads/main; if ($LASTEXITCODE -ne 0) { throw 'Fetch failed.' }; $spec=$sha+':scripts/Invoke-TechnicianExactHeadValidation.ps1'; $source=@(& git.exe -C $repo show $spec); if ($LASTEXITCODE -ne 0 -or $source.Count -eq 0) { throw 'Could not extract the exact validator from the named commit.' }; [IO.File]::WriteAllLines($runner,[string[]]$source,[Text.UTF8Encoding]::new($false)); & pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runner -RepoRoot $repo -RemoteRef 'refs/heads/main' -ExpectedHead $sha -RunReadiness; if ($LASTEXITCODE -ne 0) { throw "Exact-head field readiness failed with exit code $LASTEXITCODE." }
```

This bootstrap retrieves only the tracked validator from the exact fetched commit. The validator then owns the detached worktree, cross-shell validation, P00, setup, fleet-state proof, and readiness evidence.

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
