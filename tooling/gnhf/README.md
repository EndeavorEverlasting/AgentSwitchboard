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
- CLI readiness requires a successful version probe, not command presence alone.
- Prompt files are streamed over stdin so detailed PRDs do not hit Windows argv limits.

## Idempotence contract

Bootstrap and reporting commands are safe to run repeatedly:

- A healthy existing GNHF, OpenCode, or Copilot CLI installation is reused.
- Missing or unhealthy requested tools are installed or repaired.
- Existing directories are reused; missing directory trees are created.
- A file occupying a required directory path, or a directory occupying a required file path, produces a clear blocking error.
- Files already running from the installed fleet directory are not copied onto themselves.
- An existing customized `gnhf-fleet.json` is preserved by default.
- `-ResetManifest` is required to replace the installed manifest from the template.
- `-RebuildGnhf` is required to rebuild a healthy GNHF command from the source clone.
- One missing fleet repository or prompt causes that lane to be skipped and recorded; it does not prevent valid lanes from launching.
- Morning review records missing repositories and stale worktree directories instead of aborting the whole report.

## Start here: launch an agent and code

From the AgentSwitchboard checkout, run bootstrap and the readiness probe against your target repository:

```powershell
cd "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"

pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\SysAdminSuite" `
  -Bootstrap `
  -ListAgents
```

The same command can be run again after an interrupted or partial setup. Bootstrap refreshes scripts and readiness state while preserving the installed fleet manifest.

The bootstrap installs, repairs, or reuses GNHF; probes OpenCode, Goose, AGY, and Copilot; writes local fleet state under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet`; and installs this reusable launcher:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd
```

For a target repository such as SysAdminSuite, supply the real bounded sprint prompt. The fastest path is to copy the prompt to the Windows clipboard, enter the clean target repository, and launch:

```powershell
cd "C:\Users\Cheex\Desktop\dev\SysAdminSuite"

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" `
  -Agent opencode `
  -Prompt (Get-Clipboard -Raw) `
  -MaxIterations 4 `
  -MaxTokens 250000
```

Or launch from a tracked or local prompt file:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" `
  -Agent goose `
  -PromptPath "C:\path\to\bounded-sprint.md" `
  -MaxIterations 2 `
  -MaxTokens 100000 `
  -StopWhen "The scoped validation is complete, evidence is recorded, and no implementation files changed."
```

List the detected adapters without starting work:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

The bundled OpenCode, Goose, AGY, and Copilot prompts are scoped specifically to AgentSwitchboard. They are selected automatically only when the target repository folder is named `AgentSwitchboard`; other repositories must receive `-Prompt` or `-PromptPath` so the launcher cannot silently apply the wrong owned scope. Use `-PushBranch` only after a controlled local run proves the lane; local commit-only worktrees are the default.

## Validate the fleet contracts

The validator uses the built-in PowerShell parser, temporary-directory behavior checks, and deterministic text/manifest checks. It does not launch agents or mutate a target repository.

```powershell
pwsh -NoLogo -NoProfile -File .\Test-GnhfFleetContracts.ps1
```

It checks:

- PowerShell syntax and manifest structure;
- readiness gating and asynchronous probe output draining;
- prompt streaming and incompatible flag rejection;
- creation and reuse of nested directories;
- file-versus-directory collision handling;
- repeated same-path file copies;
- existing-manifest preservation;
- reuse of healthy installations;
- invalid-lane skipping;
- missing-repository and stale-worktree reporting.

## Install or repair

Open PowerShell 7 in the AgentSwitchboard checkout or installed fleet directory:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -GnhfRepoPath "C:\path\to\your\gnhf" `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

A healthy global `gnhf` command is used as-is. When GNHF is unavailable or unhealthy, the installer builds the existing source clone when possible, then falls back to installing the published package.

Use an explicit source rebuild only when needed:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -GnhfRepoPath "C:\path\to\your\gnhf" `
  -RebuildGnhf
```

Install or repair OpenCode and Copilot when requested:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -InstallOpenCodeAndCopilot
```

Reset the installed fleet manifest only when intentionally discarding its customizations:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -ResetManifest `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

If AGY exposes ACP but auto-detection does not recognize its launch form:

```powershell
pwsh -File .\Install-AgentSwitchboardGnhf.ps1 `
  -AgyAcpCommand "agy <exact-acp-server-arguments>"
```

The installer writes operational files to:

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

`-Wait` is intended for automation and cannot be combined with `-KeepWindowsOpen`; interactive windows must not hold an unattended parent process open indefinitely.

Every enabled lane receives a launch record. Invalid paths, unknown agents, blocked agents, and process-start failures are recorded with explicit statuses while healthy lanes continue.

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

The report survives missing configured repositories and stale worktree registrations. Those conditions are emitted as `unavailable` or `worktree-missing` evidence instead of terminating the report.

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
