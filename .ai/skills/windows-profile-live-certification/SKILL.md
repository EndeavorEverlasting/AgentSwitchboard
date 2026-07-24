---
id: windows-profile-live-certification
version: 1.1.0
status: canonical
---

# Windows Profile Live Certification

## Trigger

`profile.workstation-certification-request`, explicit live-certification invocation, or an operator report that the technician pull/setup/launch path failed or hung.

## Inputs

- Exact AgentSwitchboard commit SHA
- Exact installed launcher path and manifest hash
- Requested mode: open-or-activate or new-instance
- Exact operator command and exact operator shell
- WSL distribution name
- Expected tmux identity
- Expected command-resolution surface for Windows and WSL tools
- Evidence root path
- Timeout seconds
- Any required interactive input or browser handoff

## Procedure

1. Freeze the run context: repo, commit, launcher path, manifest hash, mode, operator command, exact operator shell, distribution, tmux identity, evidence root, timeout, rollback boundary, proof ceiling.
2. Capture before snapshot: desktop shortcut target and arguments, WezTerm frontend processes and top-level windows, tmux sessions, tmux clients, installed launcher and manifest hashes.
3. Preflight every command in the shell where the operator was told to run it. A WSL-only command does not count as PowerShell-ready unless the contract explicitly instructs `wsl.exe` or installs a repo-owned shim and verifies it from PowerShell.
4. Treat optional agents separately from the requested core path. Hermes, another optional provider, or browser authentication may not block a requested WezTerm -> WSL -> tmux -> AGY/OpenCode setup unless that optional surface was explicitly selected.
5. For a browser handoff that waits for Enter, model the newline as required deterministic input. Supply it once, bound the wait, preserve stdout and stderr, and fail with the exact stage when the browser or callback does not complete.
6. Execute the exact operator command in the requested mode.
7. Capture after snapshot: same fields as before.
8. Compare before and after: new windows, new tmux sessions, new tmux clients, command resolution, tool versions, and effective PATH or shim state.
9. Classify result: opened, activated, new-instance-opened, duplicate-detected, blocked, or failed.
10. Emit stage ledger, mode result, duplicate report, English operator report, and final handoff.
11. When Live mode: require user-visible observation fields. Process handles and tmux session existence alone are insufficient.
12. Observed live failure outranks static and CI success for the same operator path. Record a sanitized failure fixture or PR report, repair the same evidence chain, and rerun the exact operator command before promoting proof.

## Outputs

- Run context (untracked)
- Before and after snapshots (untracked)
- Stage ledger (untracked)
- Shell-specific command-resolution report (untracked)
- Mode result (untracked)
- Duplicate report (untracked)
- English operator report (untracked)
- Final handoff (untracked)
- Deliberately minimized public failure fixture when a live failure changes repository doctrine or validation

## Deterministic validation

- Run context schema validates
- All required stages completed or failed with an exact boundary identity
- The exact operator shell resolves every command the runbook promises
- Windows commands resolve to Windows executables or repo-owned shims
- WSL commands resolve inside the named distribution by absolute path
- Optional browser-auth stages cannot block the core path
- Required newline or other deterministic input is represented and bounded
- Proof ceiling declared
- No tracked private runtime evidence
- No private hostnames, usernames, or unredacted command lines in fixtures
- A live failure cannot be overridden by a passing parser, fixture, or CI run

## Forbidden scope

- Runtime execution in CI
- Storing private hostnames, usernames, or unredacted command lines in committed fixtures
- Claiming live proof from static tests or command acknowledgement
- Treating command presence in another shell or operating-system boundary as operator-shell readiness
- Allowing an optional agent or provider to block an explicitly narrower core setup
- Blind waits or operator-only Ctrl+C/debug recovery at a known interactive boundary
- Installing hooks implicitly
- Mutating launcher product code outside the declared repair sprint
- Process handles as visible-window proof
- tmux session existence as client-attachment proof

## Stop and escalate

- Launcher path or hash differs from the pinned contract
- WezTerm, WSL, or tmux prerequisites are missing or unresolved in the promised shell
- AGY or OpenCode installation completes without an absolute command path and version proof
- Hermes or another browser-auth flow waits without the declared input and timeout contract
- The operator command was not acknowledged
- Duplicate detection finds more than one new window per request
- Observed live behavior contradicts static or CI evidence
- Rollback fails
