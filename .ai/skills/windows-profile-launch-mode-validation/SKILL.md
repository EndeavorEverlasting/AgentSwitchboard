---
id: windows-profile-launch-mode-validation
version: 1.0.0
status: canonical
---

# Windows Profile Launch Mode Validation

## Trigger

Use when the Windows Profile must distinguish its default `open-or-activate` behavior from an explicit `new-instance` request, or when one operator invocation appears to create duplicate WezTerm windows.

This skill validates launch-mode contracts and supplied or synthetic evidence. It does not implement the launcher.

## Inputs

- exact repository branch and selected launcher policy;
- requested mode: `open-or-activate` or `new-instance`;
- canonical workspace identity;
- explicit instance ID for `new-instance`;
- exact operator command;
- before and after top-level window inventory;
- process and tmux-session inventory;
- request correlation ID;
- child stdout and stderr evidence;
- proof ceiling and authorized runtime boundary.

## Procedure

1. Load `.ai/harness/device-profile-launcher.policy.json`.
2. Load `tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json`.
3. Run `launch-request-intake.workflow.json` and select exactly one workflow.
4. Treat an omitted mode as `open-or-activate`.
5. Reject `new-instance` unless it was explicit and includes a valid instance ID and unique tmux session identity.
6. Freeze the exact operator command and capture the pre-invocation window, process, and tmux-session inventories.
7. Preserve child stdout, stderr, exit code, timing, and request correlation.
8. For `open-or-activate`, require the same workspace identity to converge: zero new windows when it already exists, or exactly one when it does not.
9. For `new-instance`, require exactly one new top-level WezTerm window, a distinct frontend process, and a unique tmux session. Repeating the same instance ID must activate that named instance rather than create another window.
10. Route any one-request multi-window result or repeated workspace identity to `duplicate-window-diagnosis.workflow.json`.
11. Read back effective window and tmux state; do not infer behavior from configuration intent or process exit alone.
12. Emit the registered local artifacts and an English report with one next command.

## Outputs

- selected workflow;
- `windows-launch-mode-run-context.json`;
- before and after snapshots;
- `windows-launch-mode-result.json`;
- `windows-launch-mode-operator-report.md`;
- `windows-launch-mode-final-handoff.json`.

Generated evidence remains local-operational and untracked.

## Deterministic validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLaunchModeHarness.ps1
python tests/test_windows_profile_launch_mode_harness.py
```

A contract pass proves workflow selection, fixture semantics, registration, and generated-artifact policy only.

Runtime success additionally requires the exact operator invocation, correlated before/after observations, user-visible confirmation, and end-to-end evidence through `.ai/skills/end-to-end-runtime-validation/SKILL.md`.

## Forbidden scope

- No raw `wezterm`, `wezterm.exe`, or `wezterm-gui.exe` fallback as a second lifecycle owner.
- No implicit `new-instance` behavior.
- No use of the canonical `dev` tmux session for an explicit separate instance.
- No claim that two windows showing the same tmux workspace are independent instances.
- No diagnosis based on process count alone.
- No launcher product-code mutation in a harness-only sprint.
- No tracked runtime logs, private paths, credentials, or screenshots.
- No runtime success claim from static checks or CI.

## Stop and escalate

Stop when the canonical launcher identity is unresolved, the requested mode is ambiguous, a new-instance request lacks a unique identity, before/after inventory is missing, child diagnostics are unavailable, one request created more than one window, or the observed state contradicts the selected workflow.

Escalate with the request correlation, exact command, first divergent boundary, bounded stdout and stderr evidence, window and tmux-session deltas, proof ceiling, and one safe next diagnostic command.
