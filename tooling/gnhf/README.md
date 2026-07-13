# AgentSwitchboard GNHF Fleet

Windows-first installation and launchers for bounded unattended GNHF sprints.

## Safety contract

- GNHF runs in isolated Git worktrees.
- The target checkout must be clean.
- Every run has an iteration cap and an observable stop condition.
- Push is off by default.
- No merge, deployment, force-push, reset of user work, or secret handling is automated.
- Parallel lanes must have disjoint owned scopes.
- AGY is enabled for GNHF only when an ACP server command is verified.
- CLI readiness requires a successful version probe, not command presence alone.
- Prompt files are streamed over stdin so detailed PRDs do not hit Windows argv limits.
- Remote installers are allowlisted to official Goose, Google Antigravity, Anthropic, and OpenAI sources, downloaded into a temporary directory, executed, and removed.
- AGY installation and GNHF readiness are separate facts. AGY remains available for direct interactive use when its current CLI has no supported ACP server mode.

## Start here: install agents and launch code

From the AgentSwitchboard checkout, run the workstation bootstrap and readiness probe against your target repository:

```powershell
cd "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\SysAdminSuite" `
  -Bootstrap `
  -InstallProfile Core `
  -ListAgents
```

`Core` installs missing copies of GNHF, Goose CLI, OpenCode, and Antigravity CLI (`agy`). Existing commands are preserved and re-probed. The bootstrap writes local fleet state under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet` and installs this reusable launcher:

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

List detected adapters without starting work:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

The bundled OpenCode, Goose, AGY, and Copilot prompts are scoped specifically to AgentSwitchboard. They are selected automatically only when the target repository folder is named `AgentSwitchboard`; other repositories must receive `-Prompt` or `-PromptPath` so the launcher cannot silently apply the wrong owned scope. Claude, Codex, and Pi also require an explicit prompt because no AgentSwitchboard-specific default lane exists for them. Use `-PushBranch` only after a controlled local run proves the lane; local commit-only worktrees are the default.

## Workstation install profiles

The operator launcher exposes idempotent install profiles. `-Bootstrap` runs even when fleet state already exists, so it can install missing agents and refresh evidence.

### Core: Goose, OpenCode, and AGY

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard" `
  -Bootstrap `
  -InstallProfile Core `
  -ListAgents
```

### GNHF native: OpenCode, Copilot, Claude, Codex, and Pi

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard" `
  -Bootstrap `
  -InstallProfile GnhfNative `
  -ListAgents
```

### All automated agents

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard" `
  -Bootstrap `
  -InstallProfile All `
  -ListAgents
```

`All` installs Goose, OpenCode, AGY, Copilot, Claude, Codex, and Pi. Gemini CLI remains explicit opt-in because AGY is the intended Google consumer terminal path:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Start-AgentSwitchboard.ps1 `
  -RepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard" `
  -Bootstrap `
  -InstallProfile None `
  -InstallAgent gemini `
  -ListAgents
```

The lower-level installer can also be run directly from `tooling\gnhf`:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentSwitchboardWorkstation.ps1 `
  -InstallProfile Core `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

The important outputs are:

- `state.json`: fleet readiness plus workstation install evidence
- `workstation-install-report.json`: requested profile, actions, command paths, and version probes
- `gnhf-fleet.json`: editable sprint manifest

## What is and is not installed

AgentSwitchboard installs **CLI applications**, not cloud models. It does not write provider keys or subscription credentials. Model selection and authentication remain inside each CLI.

| Agent | Automated install source | GNHF route after proof |
|---|---|---|
| OpenCode | `opencode-ai@latest` | Native `--agent opencode` |
| Goose | Official stable Windows PowerShell installer | ACP `acp:goose acp` after `goose acp --help` succeeds |
| AGY | Official `antigravity.google/cli/install.ps1` | Direct interactive use; GNHF-blocked until supported ACP exists |
| Copilot CLI | `@github/copilot@latest` | Native `--agent copilot` |
| Claude Code | Official `claude.ai/install.ps1` | Native `--agent claude` |
| Codex CLI | Official `chatgpt.com/codex/install.ps1` | Native `--agent codex` |
| Pi | `@earendil-works/pi-coding-agent@latest` | Native `--agent pi` |
| Gemini CLI | `@google/gemini-cli@latest`, explicit opt-in | ACP `acp:gemini` after capability proof |
| Rovo Dev | Manual Atlassian `acli` setup | Native `--agent rovodev` after detection |

## Authenticate once

Run only the installed tools you plan to use and complete their own login/provider flow:

```powershell
goose
opencode
agy
copilot
claude
codex
pi
```

Do not put provider keys in the fleet manifest, prompt files, or repository.

## Validate the fleet contracts

The validator uses the built-in PowerShell parser and deterministic text/manifest checks; it does not launch agents or mutate a target repository.

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Test-GnhfFleetContracts.ps1
```

It checks PowerShell syntax, the example manifest, operator bootstrap wiring, official installer allowlists, install-profile membership, temporary-file cleanup, readiness gating, asynchronous probe output draining, prompt streaming, incompatible flag rejection, controlled failure reporting, and report-directory recovery.

## Lower-level fleet-only install

Use the fleet-only installer when the agent CLIs are already installed and only GNHF detection or bundle refresh is needed:

```powershell
pwsh -File .\tooling\gnhf\Install-AgentSwitchboardGnhf.ps1 `
  -GnhfRepoPath "C:\path\to\your\gnhf" `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

If AGY later exposes a supported ACP mode but auto-detection does not recognize its launch form:

```powershell
pwsh -File .\tooling\gnhf\Install-AgentSwitchboardGnhf.ps1 `
  -GnhfRepoPath "C:\path\to\your\gnhf" `
  -AgyAcpCommand "agy <exact-acp-server-arguments>"
```

The operational bundle is written to `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet`.

## Start one sprint directly

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

## Morning review

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -File "$root\Get-GnhfFleetStatus.ps1" `
  -ManifestPath "$root\gnhf-fleet.json"
```

The report is written under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports`.

## Scope discipline

Do not launch multiple agents against the same files. Good parallel lanes:

- implementation: `installers/`, `scripts/core/`
- tests: `tests/`, `tests/fixtures/`
- architecture: `docs/architecture/`, `diagrams/`
- validation/reporting: `validators/`, `reports/templates/`

Each prompt must name owned scope, forbidden scope, validation, and an observable stop condition.
