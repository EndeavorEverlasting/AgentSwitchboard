# BlacksmithGuild GNHF Night Panel

## What starts the chain

The chain starts when the operator opens the WezTerm launch menu and selects:

```text
BlacksmithGuild — GNHF Night Shift
```

That menu entry starts a new WezTerm surface using native Windows PowerShell 7. It does not enter WSL or tmux because a mixed WSL shell calling Windows-mounted GNHF/agent tools has produced terminal/backend corruption and false zero-exit results.

The execution chain is:

```text
WezTerm
  -> native Windows PowerShell 7
  -> BlacksmithGuild panel launcher
  -> strict AgentSwitchboard provider route
  -> shell-correct OpenCode dispatch
  -> exact DeepSeek model probe
  -> model-aware GNHF isolated worktree
  -> BlacksmithGuild one-click night objective
  -> committed-delivery verification
```

The default model is `deepseek/deepseek-v4-pro`. GNHF uses the truthful `opencode` adapter and receives the exact model separately. DeepSeek is not represented as a fictional native GNHF agent.

## One-click V38 sequence

The panel's default `Auto` stage selects the BlacksmithGuild `night` objective when no committed night queue exists in the source checkout.

Inside one isolated GNHF worktree, that objective performs:

```text
P37  AgentSwitchboard proves the exact DeepSeek/OpenCode route before GNHF starts.
P38  The agent writes and commits a finite evidence-backed queue and baseline report.
P41  The agent repairs at most three ready code-level items, one recoverable commit per item.
P44  The agent dispositions the queue and commits the morning closeout.
```

Keeping P38, P41, and P44 in one GNHF process allows later phases to consume the queue checkpoint without requiring a human to merge or cherry-pick an intermediate GNHF branch overnight.

## Install

From the AgentSwitchboard repository root, double-click:

```text
Install-BlacksmithGuildNightPanel.cmd
```

The installer:

- installs or repairs the strict provider-routed launcher;
- depends on the installed AgentSwitchboard GNHF capability document (not a guessed npm version);
- selects models through OpenCode (`OPENCODE_CONFIG_CONTENT`), not a fictional GNHF `--model` flag;
- installs shell-correct `.ps1`, `.cmd`/`.bat`, and native executable dispatch;
- refreshes the installed AgentSwitchboard control launcher;
- installs the BlacksmithGuild night launcher under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet`;
- installs `%USERPROFILE%\.wezterm-blacksmithguild-night.lua`;
- inserts one managed block before the single `return config` in `%USERPROFILE%\.wezterm.lua`;
- preserves the original encoding and line endings;
- creates a timestamped backup before the first config mutation;
- does not replace unrelated WezTerm settings;
- can be rerun without duplicating the managed block.

Plan-only PowerShell command:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Install-BlacksmithGuildNightPanel.ps1
```

Apply command:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Install-BlacksmithGuildNightPanel.ps1 -Apply
```

## Managed WezTerm configuration block

The installer places this block before `return config`:

```lua
-- BEGIN AgentSwitchboard BlacksmithGuild GNHF Night Panel
local tbg_night_panel = dofile(wezterm.config_dir .. '/.wezterm-blacksmithguild-night.lua')
tbg_night_panel.apply(config)
-- END AgentSwitchboard BlacksmithGuild GNHF Night Panel
```

The managed include adds this launch-menu item without changing the rest of the user's WezTerm configuration.

## Repository path

The default repository path is:

```text
%USERPROFILE%\Desktop\dev\Mods\Bannerlord\BlacksmithGuild
```

Set `TBG_REPO_PATH` before launching WezTerm to override it without editing the Lua include.

## Preconditions

- The BlacksmithGuild source checkout must be clean and attached to a non-`gnhf/*` branch.
- BlacksmithGuild main must contain `.tbg/workflows/gnhf-night-shift.contract.json` and its tracked prompts.
- AgentSwitchboard fleet state must exist under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet`.
- OpenCode must be ready. An npm-installed `opencode.ps1` or `opencode.cmd` shim is dispatched through the correct Windows shell rather than passed to `.NET Process.Start()` as a native executable.
- The exact configured DeepSeek model must be listed and must return `AGENT_SWITCHBOARD_MODEL_READY` during the bounded launch probe.
- Provider login is interactive and external to this installer. No credential values are read or stored.

## Failure posture

The panel stops before repository mutation when:

- the source checkout is dirty or detached;
- the night contract or prompt is missing;
- the required provider launcher or model-aware GNHF runtime is missing;
- OpenCode or the exact DeepSeek model is unavailable;
- the bounded provider probe fails;
- the source is already a generated `gnhf/*` branch;
- AgentSwitchboard fleet state is missing.

After GNHF starts, all of the following are operational failures rather than delivery:

- provider error or timeout;
- repeated failed iterations with zero token activity;
- exit code zero with no new commit ahead of the starting SHA;
- configured stop text without queue, repair, and closeout commits.

The panel exits nonzero for those conditions. It does not print a success message, silently switch providers, or delete the generated worktree. Preserve the worktree, run log, notes, provider-route evidence, and launcher summary for diagnosis.

## Evidence and morning review

AgentSwitchboard stores provider and launcher evidence under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs
```

The GNHF worktree should contain ordered commits for:

1. queue and baseline report;
2. up to three repair dispositions;
3. closeout.

Review the generated worktree and commits before any push or pull request. Push, merge, deployment, authentication, Bannerlord launch, and personal-save mutation are not authorized by the panel.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Test-BlacksmithGuildNightPanelContracts.ps1
```

This reaches repository/static and temporary-filesystem installer proof. It does not prove the user's local WezTerm process, provider account, quota, network, a real DeepSeek response, a completed GNHF worktree, or BlacksmithGuild runtime behavior.
