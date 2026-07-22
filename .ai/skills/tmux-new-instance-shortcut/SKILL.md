---
id: tmux-new-instance-shortcut
version: 1.0.0
status: canonical
---

# tmux New-Instance Desktop Shortcut

## Trigger

Use when the operator asks for a desktop shortcut, clickable CMD installer, or one-click Windows Profile entrypoint that must create a genuinely separate tmux workspace rather than another view of the existing `dev` session.

This skill owns the shortcut installation and explicit `new-instance` route only. The default `open-or-activate` mode remains a separate implementation and runtime-proof lane.

## Required inputs

- repository and branch;
- `AGENTS.md`, device-profile policy, and launch-mode registry;
- tracked shortcut manifest;
- canonical Windows Profile launcher path;
- selected WSL distribution;
- tmux session prefix and maximum instance count;
- user-local install root and desktop directory;
- PowerShell 7 and WezTerm CLI paths for Apply mode;
- exact validation order and proof ceiling.

## Procedure

1. Read `tooling/profiles/windows/harness/tmux-new-instance-shortcut/codebase-map.json`.
2. Confirm that `Install-TmuxNewInstanceShortcut.cmd` delegates to `tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1` and contains no independent WezTerm or tmux lifecycle logic.
3. Confirm that the installer delegates every shortcut invocation to `tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1` with `-Mode new-instance -InstanceId auto`.
4. Run installer Plan mode first when changing paths, naming, arguments, or ownership rules.
5. Preserve any existing shortcut whose description and arguments do not prove AgentSwitchboard ownership.
6. Install the canonical launcher and manifest under the current user's local AgentSwitchboard profile root.
7. Create or refresh the owned desktop shortcut and read back its target, arguments, icon, description, and working directory.
8. For deterministic launch validation, run the canonical launcher in `-Operation Plan` with synthetic existing-session inventories.
9. Require automatic allocation to reserve bare `dev` for default mode and choose `dev-1`, `dev-2`, and so on using the smallest unused positive integer.
10. Require the launch command to create a new detached tmux session before requesting WezTerm.
11. Require `wezterm start --always-new-process`, a unique workspace, and a unique window class.
12. Reject an explicit instance ID that already exists; never attach a second window and call it a new instance.
13. Run the focused PowerShell and Python validators, the existing launch-mode and device-profile contracts, the wider safe harness, and `git diff --check`.
14. Emit an English operator report, commit SHA, PR state, generated-artifact policy, proof ceiling, and one exact next command.

## Expected outputs

Tracked:

- CMD installer;
- PowerShell installer;
- canonical Windows Profile launcher;
- manifest;
- codebase map, registry, graph, workflows, schema, and fixtures;
- focused validator and dependency-free tests;
- opt-in hook;
- status reporter;
- operator guide and CI.

Generated and untracked:

- install plan;
- install receipt;
- operator report;
- launch plan;
- launch result;
- final handoff when a runtime lane is completed.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-TmuxNewInstanceShortcutHarness.ps1
python tests/test_tmux_new_instance_shortcut_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-DeviceProfileLauncherContract.ps1
git diff --check
```

Plan examples:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Install-TmuxNewInstanceShortcut.ps1 -Mode Plan

pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1 `
    -Mode new-instance `
    -Operation Plan `
    -ExistingSessions dev,dev-1,dev-3
```

## Proof promotion

- Installer Plan proves paths and delegation intent only.
- Apply plus COM readback proves the owned shortcut and installed launcher were written correctly.
- Launch plan proves deterministic identity and command construction.
- Session creation plus WezTerm process acknowledgement proves only `command-ack`.
- Visible window, exact tmux attachment, styling/layout, one-window behavior, repeat-click behavior, rollback, and operator acceptance require `.ai/skills/end-to-end-runtime-validation/SKILL.md` on the target workstation.

## Forbidden scope

- No `AGENTS.md` mutation in a harness-only sprint.
- No raw WezTerm or tmux lifecycle logic inside the desktop shortcut or CMD wrapper.
- No second window attached to `dev` presented as a separate instance.
- No `tmux new-session -A` reuse in `new-instance` mode.
- No silent overwrite of a foreign shortcut.
- No automatic WSL, tmux, WezTerm, package, provider, or credential installation.
- No replacement of `.wezterm.lua` or `.tmux.conf`.
- No tracked local paths, logs, receipts, terminal contents, or screenshots.
- No runtime-success claim from CI, process exit, session creation, or configuration intent alone.

## Stop and escalate

Stop when the canonical launcher is missing, the requested shortcut is foreign, PowerShell 7 or WezTerm is absent in Apply mode, WSL or tmux is absent at launch, identity allocation is exhausted, an explicit instance already exists, the new session cannot be verified, the process command omits `--always-new-process`, or observed runtime state contradicts the allocated session.

Escalate with the exact failing boundary, local artifact paths, bounded stderr, preserved existing shortcut/session state, rollback position, proof ceiling, and one safe next command.
