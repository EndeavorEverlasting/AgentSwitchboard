# AgentSwitchboard GNHF Fleet

Windows-first launchers for bounded unattended GNHF sprints.

## Safety contract

- GNHF runs in isolated Git worktrees.
- The target checkout must be clean.
- Every run has an iteration cap and an observable stop condition.
- Push is off by default.
- No merge, deployment, force-push, reset of user work, or secret handling is automated.
- Parallel lanes must have disjoint owned scopes.
- AGY is enabled only when an ACP server command is verified.

## Install

Open PowerShell 7 in the extracted bundle:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -GnhfRepoPath "C:\path\to\your\gnhf" `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

Add `-InstallOpenCodeAndCopilot` only when those two commands are missing.

If AGY exposes ACP but auto-detection does not recognize its launch form:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -GnhfRepoPath "C:\path\to\your\gnhf" `
  -AgyAcpCommand "agy <exact-acp-server-arguments>"
```

The installer writes the operational files to:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet
```

## Authenticate once

Run each agent interactively before unattended work:

```powershell
opencode
goose
agy
copilot
```

Use each tool's own login/provider flow. Do not put provider keys in the fleet manifest or prompts.

## Start one sprint

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -File "$root\Start-GnhfSprint.ps1" `
  -RepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard" `
  -Agent opencode `
  -PromptPath "$root\prompts\opencode-implementation.md" `
  -Name "agent-switchboard-core" `
  -MaxIterations 6 `
  -MaxTokens 500000 `
  -StopWhen "The bounded change is committed, targeted validation passes, and no unrelated files changed."
```

## Start the fleet

Edit `gnhf-fleet.json` first. Enable only lanes with disjoint scope.

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -File "$root\Start-GnhfFleet.ps1" `
  -ManifestPath "$root\gnhf-fleet.json" `
  -KeepWindowsOpen
```

To push each generated GNHF branch after successful iterations, explicitly add `-PushBranches`. Local commit-only mode is safer for the first controlled run.

## Morning review

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -File "$root\Get-GnhfFleetStatus.ps1" `
  -ManifestPath "$root\gnhf-fleet.json"
```

The report is written under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports
```

## Agent mapping

| Requested agent | GNHF integration |
|---|---|
| OpenCode | Native `--agent opencode` |
| Copilot CLI | Native `--agent copilot` |
| Goose | ACP custom command `acp:goose acp` |
| AGY | ACP only; exact server launch command must be detected or supplied |

## Scope discipline

Do not launch four agents against the same files. Good parallel lanes:

- implementation: `installers/`, `scripts/core/`
- tests: `tests/`, `tests/fixtures/`
- architecture: `docs/architecture/`, `diagrams/`
- validation/reporting: `validators/`, `reports/templates/`

Each prompt must name owned scope, forbidden scope, validation, and an observable stop condition.
