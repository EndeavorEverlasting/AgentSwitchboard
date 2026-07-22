---
id: windows-tmux-launch
version: 1.0.0
status: canonical
---

# Windows tmux launch

## Trigger conditions

Use this skill when an operator asks to open AgentSwitchboard/WezTerm/tmux, continue the last workspace, create an isolated new terminal instance, repair an obsolete launcher, or prove that two launches do not attach to the same tmux conversation.

## Required inputs

- Current AgentSwitchboard repository and branch.
- Intended mode: `continue` or `new`.
- Windows, WSL distribution, tmux, and WezTerm availability for runtime proof.
- Current Git status and ownership of any workstation-launcher changes.

## Mode contract

- `continue`: target only the canonical `dev` tmux session. Activate the existing marked WezTerm frontend when present. If no frontend exists, create `dev` only when absent and launch one frontend attached to it. Never allocate `dev-N`.
- `new`: inspect existing tmux sessions, allocate the smallest unused `dev-N`, create it, and start one separate WezTerm process. Never attach to `dev` or an existing `dev-N`.

No fallback between modes is allowed.

## Procedure

1. Read `docs/workstation/windows-tmux-launch.md` and `.ai/harness/workflows/windows-tmux-launch.workflow.json`.
2. Run `tooling/profiles/windows/Test-AgentSwitchboardTmuxLaunchers.ps1`.
3. Install or refresh the two desktop CMDs with `Install-AgentSwitchboard-Tmux-Launchers.cmd`.
4. Select exactly one launcher based on operator intent.
5. Inspect the generated plan/result artifact and record session name, workspace, class, process outcome, and proof ceiling.
6. For live certification, click Continue twice and prove no second marked frontend is started; click New twice and prove two distinct unused numbered sessions and processes are requested.
7. Hand off with validator output, receipt/result paths, observed tmux sessions, and exact unresolved runtime evidence.

## Expected outputs

- Two explicit CMD launch surfaces.
- Installed launcher receipt and English operator report.
- Per-run plan/result JSON.
- Passing deterministic harness validator.
- Runtime certificate only when visible behavior was actually observed.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\profiles\windows\Test-AgentSwitchboardTmuxLaunchers.ps1
git diff --check
```

## Stop and escalate

Stop without launching when WSL, tmux, or WezTerm is unavailable; the manifest is invalid; a marked Continue frontend exists but `dev` does not; no numbered session remains; or the requested mode would fall back to the other mode.

## Forbidden scope

- Rewriting `.wezterm.lua` or tmux configuration.
- Closing, killing, or deleting existing sessions/processes.
- Removing legacy launchers automatically.
- Claiming visible-window success from static or command-ack evidence.
- Changing repository governance.
