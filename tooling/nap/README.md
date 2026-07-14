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
8. contains detailed child output behind a technician-safe process boundary;
9. displays a stable failure code and one next action instead of dumping an unhandled PowerShell error into the operator window.

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
pwsh -NoLogo -NoProfile -File .\tooling\nap\Invoke-NapSprintSafely.ps1 -PlanOnly
```

## Technician-safe failure behavior

`Start-NapSprint.cmd` delegates to `Invoke-NapSprintSafely.ps1`. The wrapper runs the strict inner launcher as a child process, redirects detailed child output to a log, and returns a concise result such as:

```text
[NAP-REPOSITORY] The target repository is not safe for unattended work.
Next action: Open the repository, run git status --short, preserve existing work, and retry from a clean attached branch.
```

Stable failure families are:

| Code | Meaning |
|---|---|
| `NAP-CONFIG` | Missing or invalid machine-local configuration |
| `NAP-PROMPT` | Missing clipboard or prompt-file content |
| `NAP-REPOSITORY` | Unsafe, dirty, detached, or invalid Git checkout |
| `NAP-SETUP` | Missing or unhealthy AgentSwitchboard/GNHF setup |
| `NAP-AGENT` | No ready agent, provider authentication, quota, or rate-limit issue |
| `NAP-EXECUTION` | A bounded run started but did not complete |
| `NAP-INTERNAL` | Unexpected local wrapper failure |

Automatic retry and cross-agent failover remain disabled after a coding run begins. That prevents a second agent from working against unknown partial state.

## Evidence

The strict inner launcher writes:

```text
%LOCALAPPDATA%\AgentSwitchboard\Nap\runs\<timestamp>\
  nap-transcript.txt
  nap-summary.json
```

The technician-safe wrapper writes independently:

```text
%LOCALAPPDATA%\AgentSwitchboard\Nap\operator-runs\<timestamp>\
  technician-console.log
  operator-summary.json
```

This outer report is still produced when the inner launcher returns a nonzero exit code. It records the stable failure code, concise message, next action, retryability, child exit code, and linked inner summary path when available.

The sprint prompt is passed through an ephemeral file to avoid Windows argv limits and is deleted in `finally`. The summaries do not persist prompt text or raw bound arguments.

The inner GNHF launcher continues to write its own evidence under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\
```

## Safety boundaries

- Clean target checkout required.
- Detached HEAD and existing `gnhf/*` base branches are rejected.
- Iteration and token caps are mandatory.
- Push remains disabled in the example config.
- `PlanOnly` never installs software.
- Missing setup may be repaired only during an actual run when `bootstrapIfMissing=true`.
- No prompt text, provider key, token, or credential belongs in the local JSON config or repository.
- A successful launcher exit is not an automatic merge decision; inspect the generated worktree branch and validation evidence.
- A wrapper failure never authorizes destructive cleanup, force-push, merge, deployment, or silent executor switching.

## Validate contracts and the failure path

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\nap\Test-NapSprintContracts.ps1
pwsh -NoLogo -NoProfile -File .\tooling\nap\Test-NapOperatorHarness.ps1
```

The contract validator parses all nap PowerShell files and enforces the config, clean-tree, prompt-streaming, readiness-selection, logging, push, no-runtime-failover, clickable-CMD, technician-wrapper, and stable-failure contracts.

The failure harness uses a temporary `LOCALAPPDATA`, deliberately launches with a missing configuration, and verifies that the wrapper returns nonzero while still producing `operator-summary.json`, `technician-console.log`, `NAP-CONFIG`, a retryable next action, and no leftover prompt artifact. It does not launch an agent or mutate a target repository.
