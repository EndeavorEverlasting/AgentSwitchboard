# Windows Profile Launch-Mode Harness

## Purpose

This harness defines the contract around two intentionally different Windows Profile launch behaviors:

1. **`open-or-activate`** — the default. A stable workspace identity converges to one visible WezTerm window. Repeating the same request activates the existing workspace and must not create another top-level window.
2. **`new-instance`** — explicit only. One named instance creates exactly one additional top-level WezTerm window, uses a distinct frontend process, and attaches to a unique tmux session. Repeating the same instance ID activates that named instance instead of creating another window.

Both modes remain operations of one canonical AgentSwitchboard launcher. Raw WezTerm commands, shortcuts, and consumer repositories are not separate lifecycle owners.

## What is working

- The repository has a canonical Windows Profile policy and one-owner boundary.
- The launch-mode registry distinguishes default convergence from explicit named isolation.
- Intake selects exactly one workflow.
- Synthetic fixtures prove:
  - an existing `dev` workspace activates without a new window;
  - an explicit `research` instance adds one window and one unique tmux session;
  - one request creating two new windows is rejected as `duplicate-detected`.
- A focused PowerShell validator and dependency-free Python contract check tracked files, JSON, workflow semantics, fixtures, central registration, and evidence hygiene.
- An opt-in pre-commit hook is available but is never installed implicitly.
- A read-only status reporter produces an English summary and machine-readable status without launching WezTerm.

## What is broken or unproved

- The canonical launcher source and installed launcher are not proven by this contract-only sprint.
- The current workstation’s duplicate-window cause has not been correlated to the caller, launcher, WezTerm process flags, `default_prog` recursion, shortcut delegation, or repeated tmux attachment.
- Window activation, distinct process creation, and unique tmux session creation require a separate authorized end-to-end runtime lane.
- SysAdminSuite still needs a separate consumer-certification sprint after the canonical launcher exists.

## Workflow selection

Use `launch-request-intake.workflow.json`.

- Omitted mode → `open-or-activate-verification`.
- Explicit `new-instance` plus a valid instance ID and unique tmux session → `new-instance-verification`.
- More than one top-level window for one request correlation, or repeated unexpected workspace identity → `duplicate-window-diagnosis`.
- Ambiguous mode, missing instance ID, reused canonical tmux session, unresolved launcher identity, or missing before-state evidence → blocked.

## Artifact policy

Generated evidence lives under an operator-controlled temporary root such as:

```text
%TEMP%/AgentSwitchboard/WindowsProfileLaunchModes/<run-id>/
```

Registered artifacts:

- `windows-launch-mode-run-context.json`
- `windows-launch-before-snapshot.json`
- `windows-launch-after-snapshot.json`
- `windows-launch-mode-result.json`
- `windows-launch-mode-operator-report.md`
- `windows-launch-mode-final-handoff.json`
- bounded per-stage stdout and stderr logs

These files are local-operational and untracked. Do not commit private paths, command lines containing credentials, customer data, or raw screenshots.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1
python tests/test_windows_profile_launch_mode_harness.py
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-WindowsProfileLaunchModeStatus.ps1 -NoWrite
Test-AppHarness.cmd
git diff --check
```

## Hook

The optional hook is:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/hooks/Invoke-WindowsProfileLaunchModePreCommit.ps1
```

It runs the focused validators, checks staged diff hygiene, and rejects staged launch-mode evidence. It is not installed automatically.

## Proof ceiling

This harness proves tracked component completeness, workflow selection, launch-mode semantics, fixture classification, central registration, generated-artifact policy, and cross-platform offline validation.

It does not prove the current WezTerm configuration, canonical launcher implementation, window activation, separate process creation, tmux session isolation, duplicate prevention on the workstation, SysAdminSuite certification, or operator acceptance.
