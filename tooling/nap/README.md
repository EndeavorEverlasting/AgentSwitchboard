# AgentSwitchboard Nap Sprints

A Windows-first operator surface for starting one bounded, unattended GNHF coding sprint and then stepping away.

## What it does

`Start-NapSprint.cmd` performs a guarded chain:

1. creates a local configuration on first use;
2. validates the target Git repository and requires a clean, attached base branch;
3. reads the bounded sprint prompt from the clipboard or a configured file;
4. hashes the prompt for evidence without writing its text into the JSON summary;
5. repairs AgentSwitchboard setup when local fleet state is missing;
6. selects the first ready agent from the configured preference order;
7. starts the existing AgentSwitchboard GNHF launcher with worktree mode, iteration and token caps, an observable stop condition, and sleep prevention;
8. writes an outer transcript and JSON summary whether the run completes, fails, or is blocked.

It does not merge, deploy, force-push, or automatically start a second agent after execution has begun.

## First use

Copy a bounded sprint prompt to the Windows clipboard and double-click:

```text
Start-NapSprint.cmd
```

When no local config exists, the launcher starts the configuration wizard. Enter the target repository path. The config is stored outside the Git repository:

```text
%LOCALAPPDATA%\AgentSwitchboard\Nap\nap-sprint.json
```

The default agent order is:

```text
Hermes → OpenCode → Goose → Copilot
```

The first agent marked ready in AgentSwitchboard fleet state is selected. Readiness proves that the configured command/adapter probe passed; it does not prove that a hosted provider still has quota. A quota or authentication failure after execution starts stops the run and is logged. AgentSwitchboard does not silently switch executors after partial work may exist.

## Configure explicitly

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\nap\Configure-NapSprint.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\SysAdminSuite" `
  -PreferredAgents hermes,opencode,goose,copilot `
  -MaxIterations 4 `
  -MaxTokens 250000
```

For a stable prompt file instead of the clipboard:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\nap\Configure-NapSprint.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\SysAdminSuite" `
  -PromptSource file `
  -PromptPath "C:\Path\To\bounded-sprint.md"
```

## Preflight without launching an agent

The plan mode validates the repository, prompt, setup state, limits, and agent readiness but does not install software or start GNHF:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\nap\Start-AgentSwitchboardNap.ps1 -PlanOnly
```

## Evidence

Every attempt writes:

```text
%LOCALAPPDATA%\AgentSwitchboard\Nap\runs\<timestamp>\
  nap-transcript.txt
  nap-summary.json
```

The sprint prompt is passed through an ephemeral file to avoid Windows argv limits and is deleted in `finally`. The summary records only prompt source, UTF-8 byte count, and SHA-256 identity.

The inner GNHF launcher continues to write its own evidence under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\
```

The outer summary records the detected inner log directory when available.

## Safety boundaries

- Clean target checkout required.
- Detached HEAD and existing `gnhf/*` base branches are rejected.
- Iteration and token caps are mandatory.
- Push remains disabled in the example config.
- `PlanOnly` never installs software.
- Missing setup may be repaired only during an actual run when `bootstrapIfMissing=true`.
- No prompt text, provider key, token, or credential belongs in the local JSON config or repository.
- A successful launcher exit is not an automatic merge decision; inspect the generated worktree branch and validation evidence.

## Validate contracts

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\nap\Test-NapSprintContracts.ps1
```

The validator parses all nap PowerShell files and enforces the config, clean-tree, prompt-streaming, readiness-selection, logging, push, no-runtime-failover, and clickable-CMD contracts. It does not launch an agent or mutate a target repository.
