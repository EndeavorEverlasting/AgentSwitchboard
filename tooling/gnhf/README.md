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
- Hermes is enabled only when both `hermes --version` and `hermes acp --help` succeed.
- CLI readiness requires a successful command probe, not command presence alone.
- Prompt files are streamed over stdin so detailed PRDs do not hit Windows argv limits.

## Idempotence and failure contract

Bootstrap and reporting commands are safe to run repeatedly:

- A healthy existing GNHF, OpenCode, Copilot CLI, or Hermes installation is reused.
- Missing or unhealthy requested tools are installed or repaired.
- Hermes installation failure does not erase the rest of the fleet; Hermes is recorded as `BLOCKED` with evidence.
- Every clickable setup run writes a transcript and JSON summary under `%LOCALAPPDATA%\AgentSwitchboard\setup-logs`.
- Existing directories are reused; missing directory trees are created.
- A file occupying a required directory path, or a directory occupying a required file path, produces a clear blocking error.
- Files already running from the installed fleet directory are not copied onto themselves.
- An existing customized `gnhf-fleet.json` is preserved by default.
- `-ResetManifest` is required to replace the installed manifest from the template.
- `-RebuildGnhf` is required to rebuild a healthy GNHF command from the source clone.
- One missing fleet repository or prompt causes that lane to be skipped and recorded; it does not prevent valid lanes from launching.
- Morning review records missing repositories and stale worktree directories instead of aborting the whole report.

## Click once: robust setup

From the AgentSwitchboard checkout, double-click:

```text
tooling\gnhf\Setup-AgentSwitchboard.cmd
```

The window stays open after success or failure. The launcher:

1. verifies PowerShell 7;
2. installs or repairs Hermes from its official Windows installer;
3. installs or repairs GNHF, OpenCode, and Copilot CLI while reusing healthy installations;
4. probes OpenCode, Goose, AGY, Copilot, and Hermes;
5. persists Hermes as the ACP adapter `acp:hermes acp` only when its version and ACP probes succeed;
6. runs the core fleet and Hermes-specific contract validators;

## Start here: launch an agent and code

After setup, list readiness without starting work:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

The reusable fleet lives under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet
```

For a target repository such as SysAdminSuite, supply the real bounded sprint prompt. Copy the prompt to the Windows clipboard, enter the clean target repository, and launch:

```powershell
cd "C:\Users\Cheex\Desktop\dev\SysAdminSuite"

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" `
  -Agent hermes `
  -Prompt (Get-Clipboard -Raw) `
  -MaxIterations 4 `
  -MaxTokens 250000 `
  -StopWhen "The scoped validation is complete, evidence is recorded, and no implementation files changed."
```

Change `hermes` to `opencode`, `goose`, `agy`, or `copilot` when that adapter reports `READY`.

Or launch from a tracked or local prompt file:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" `
  -Agent goose `
  -PromptPath "C:\path\to\bounded-sprint.md" `
  -MaxIterations 2 `
  -MaxTokens 100000 `
  -StopWhen "The scoped validation is complete, evidence is recorded, and no implementation files changed."
```

The bundled OpenCode, Goose, AGY, Copilot, and Hermes prompts are scoped specifically to AgentSwitchboard. They are selected automatically only when the target repository folder is named `AgentSwitchboard`; other repositories must receive `-Prompt` or `-PromptPath` so the launcher cannot silently apply the wrong owned scope. Use `-PushBranch` only after a controlled local run proves the lane; local commit-only worktrees are the default.

## Bootstrap or repair from PowerShell

`Start-AgentSwitchboard.ps1 -Bootstrap` delegates to the same robust setup orchestrator, so refreshing the fleet cannot silently remove the Hermes readiness record:

```powershell
cd "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"

pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\SysAdminSuite" `
  -Bootstrap `
  -InstallOpenCodeAndCopilot `
  -ListAgents
```

The same command can be rerun after an interrupted or partial setup. Bootstrap refreshes scripts and readiness state while preserving the installed fleet manifest.

## Validate the fleet contracts

The validators use the built-in PowerShell parser, temporary-directory behavior checks, and deterministic text/manifest checks. They do not launch agents or mutate a target repository.

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Test-GnhfFleetContracts.ps1
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Test-HermesSetupContracts.ps1
```

They check:

- PowerShell syntax and manifest structure;
- readiness gating and asynchronous probe output draining;
- prompt streaming and incompatible flag rejection;
- creation and reuse of nested directories;
- file-versus-directory collision handling;
- repeated same-path file copies;
- existing-manifest preservation;
- reuse of healthy installations;
- invalid-lane skipping;
- missing-repository and stale-worktree reporting;
- official Hermes installer routing;
- Hermes ACP capability probing and state persistence;
- setup transcript and JSON summary production;
- double-click launcher visibility, exit-code preservation, and log guidance;
- Hermes operator and prompt integration.

## Lower-level GNHF installer

The lower-level installer remains available when only GNHF fleet internals need repair:

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

## Authenticate once

Run each READY agent interactively before unattended work:

```powershell
opencode

goose

agy

copilot

hermes model
hermes
```

Use each tool's own login/provider flow. Do not put provider keys in the fleet manifest, prompts, setup summary, or repository.

## Start one sprint directly

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -File "$root\Start-GnhfSprint.ps1" `
  -RepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard" `
  -Agent hermes `
  -PromptPath "$root\prompts\hermes-implementation.md" `
  -Name "agent-switchboard-hermes" `
  -MaxIterations 4 `
  -MaxTokens 250000 `
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
| Hermes | ACP custom command `acp:hermes acp`; version and ACP probes must pass |
| AGY | ACP only; exact server launch command must be detected or supplied |

## Scope discipline

Do not launch multiple agents against the same files. Good parallel lanes:

- implementation: `installers/`, `scripts/core/`
- Hermes integration: `tooling/hermes/`, `docs/integrations/hermes/`, `tests/hermes/`
- tests: `tests/`, `tests/fixtures/`
- architecture: `docs/architecture/`, `diagrams/`
- validation/reporting: `validators/`, `reports/templates/`

Each prompt must name owned scope, forbidden scope, validation, and an observable stop condition.

## Orchestration contracts (P00)

The `tooling/gnhf/schemas` directory defines the P00 mainline orchestration surface:

| Schema | Purpose |
|---|---|
| `prompt-queue.schema.json` | Ordered, dependency-aware queue of bounded GNHF prompts. |
| `queue-plan.schema.json` | Deterministic compilation of a prompt queue into a stage plan. |
| `lane-result.schema.json` | Evidence record for one executed stage. |
| `child-operation-request.schema.json` | Typed request from AgentSwitchboard to a child repository operation. |
| `child-operation-result.schema.json` | Result returned by a child repository operation. |
| `trigger-snapshot.schema.json` | Immutable snapshot of the external trigger that started a run. |

Compile a prompt queue into a plan:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Compile-GnhfPromptQueue.ps1 `
  -QueuePath .\tooling\gnhf\tests\fixtures\example-prompt-queue.json `
  -OutputPath .local\gnhf-plans\example-plan.json
```

Validate a child operation request against the registry without executing it:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Invoke-GnhfChildOperation.ps1 `
  -RequestPath .\tooling\gnhf\tests\fixtures\example-child-operation-request.json `
  -OutputPath .local\gnhf-results\example-result.json `
  -ValidateOnly
```

Validate the P00 contracts on Linux or Windows without launching agents:

```bash
python3 tooling/gnhf/tests/validate_orchestration_contracts.py
```

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Test-GnhfOrchestrationContracts.ps1
```

These validators only prove schema, registry, and parse correctness. They do not prove PowerShell runtime behavior, child repository execution, provider readiness, or GNHF worktree completion.
