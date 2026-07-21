# tmux New-Instance Desktop Shortcut Harness

## Purpose

This harness installs one desktop shortcut named **AgentSwitchboard tmux - New Instance**. Double-clicking it delegates to the canonical AgentSwitchboard Windows Profile launcher, allocates the smallest unused named tmux session, and requests one separate WezTerm GUI process.

The first clicks allocate:

```text
dev-1
dev-2
dev-3
...
```

The bare `dev` session remains reserved for the default `open-or-activate` route. A second WezTerm window attached to `dev` is not considered a separate instance.

## Operator entrypoints

### Install or refresh the owned shortcut

```cmd
Install-TmuxNewInstanceShortcut.cmd
```

The CMD defaults to Apply because it is itself the explicit installer surface. It invokes PowerShell 7, copies the tracked canonical launcher and manifest beneath the current user's AgentSwitchboard profile root, creates the shortcut, and reads the shortcut properties back.

### Preview without installing

```cmd
Install-TmuxNewInstanceShortcut.cmd plan
```

Plan mode writes a local installation plan but does not create the install root, desktop directory, shortcut, tmux session, or WezTerm process.

### Preview identity allocation

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1 `
    -Mode new-instance `
    -Operation Plan `
    -ExistingSessions dev,dev-1,dev-3
```

The expected next session is `dev-2`.

## Installed files

Default install root:

```text
%LOCALAPPDATA%\AgentSwitchboard\profiles\windows\tmux-new-instance\
```

The installer writes:

- `Invoke-AgentSwitchboardOpenOrActivate.ps1`
- `tmux-new-instance-shortcut.json`
- `state/tmux-new-instance-shortcut-install-receipt.json`
- `state/tmux-new-instance-shortcut-operator-report.md`

The shortcut is created in the current user's Windows Desktop folder. The installer refuses to overwrite a shortcut whose description and arguments do not prove AgentSwitchboard ownership.

## Runtime chain

One shortcut invocation follows this boundary chain:

```text
Windows .lnk
  -> PowerShell 7
  -> installed canonical AgentSwitchboard launcher
  -> wsl.exe / selected distribution
  -> unique detached tmux session
  -> wezterm start --always-new-process
  -> explicit WSL tmux attach command
```

The canonical launcher serializes identity allocation with a named mutex, lists current tmux sessions, reserves `dev`, creates and verifies one new session, then requests one separate WezTerm process with a session-specific workspace and window class.

It does not use `tmux new-session -A`, because `-A` may attach to an existing session and would violate `new-instance` semantics.

## What is working at repository level

- A clickable CMD installer exists and defaults to Apply.
- The CMD contains no independent WezTerm or tmux lifecycle logic.
- The PowerShell installer supports Plan and Apply.
- Apply preserves foreign shortcuts, copies the canonical launcher atomically, creates the owned shortcut, and reads it back.
- Installation never launches tmux or WezTerm.
- The canonical launcher implements explicit `new-instance` identity allocation.
- The bare `dev` session is reserved.
- New instances require `wezterm start --always-new-process`, a unique workspace, and a unique window class.
- Existing explicitly named instances fail closed instead of receiving another window.
- Public synthetic fixtures cover an empty inventory, a gap in existing sessions, and an existing explicit instance.
- PowerShell and Python validators prove component completeness, deterministic Plan behavior, central registration, and generated-evidence hygiene.
- Windows and Linux CI cover the repository contract; Windows CI additionally installs and reads back a shortcut inside an isolated temporary desktop.

## What remains unproved

- The shortcut has not been installed on the operator workstation by CI.
- The actual workstation may have different WSL, tmux, WezTerm, PATH, desktop redirection, or permissions.
- A live double-click has not yet proved one visible WezTerm window.
- The exact allocated tmux session has not yet been observed as the attached client inside the visible window.
- Window styling, layout, focus behavior, repeat-click behavior, rollback, and operator acceptance remain unproved.
- The default `open-or-activate` route remains intentionally blocked until its separate implementation and runtime-proof sprint.

## Artifacts

Generated evidence is local-operational and untracked:

- `tmux-new-instance-shortcut-install-plan.json`
- `tmux-new-instance-shortcut-install-receipt.json`
- `tmux-new-instance-shortcut-operator-report.md`
- `tmux-new-instance-launch-plan.json`
- `tmux-new-instance-launch-result.json`
- `tmux-new-instance-final-handoff.json`

Do not commit local paths, terminal scrollback, environment dumps, credentials, customer data, private hostnames, or unreviewed screenshots.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-TmuxNewInstanceShortcutHarness.ps1
python tests/test_tmux_new_instance_shortcut_harness.py
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-TmuxNewInstanceShortcutStatus.ps1 -NoWrite
pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-DeviceProfileLauncherContract.ps1
Test-AppHarness.cmd
git diff --check
```

## Optional hook

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/hooks/Invoke-TmuxNewInstanceShortcutPreCommit.ps1
```

The hook runs the focused contracts, staged diff hygiene, and generated-evidence rejection. It is never installed implicitly.

## Failure handling

Preserve the first failing boundary and the existing shortcut/session state. Do not retry through raw WezTerm, create a second shortcut implementation, or automatically destroy a tmux session after a later WezTerm failure. Use `handle-failure.workflow.json`, repair the first deterministic defect in the same evidence chain, and rerun the complete applicable path.

## Rollback

This sprint does not ship an automatic destructive uninstaller. The installed files and shortcut are user-local, but removing them is still a workstation mutation. A rollback action should first read the install receipt, confirm shortcut ownership, and remove only the exact recorded shortcut and install root through a separately reviewed runtime operation.

## Proof ceiling

This repository proves tracked installer and launcher implementation, safe ownership boundaries, deterministic session allocation, exact command construction, isolated Windows shortcut creation/readback, cross-platform contract validation, and Git hygiene.

It does not prove the operator workstation's visible WezTerm result, tmux client attachment, styling, focus, repeat-click behavior, rollback, or acceptance. Those claims require the exact installed shortcut through the end-to-end runtime-validation skill.
