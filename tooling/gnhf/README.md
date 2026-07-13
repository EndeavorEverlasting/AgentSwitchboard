# AgentSwitchboard GNHF Fleet

Windows-first installation and launchers for bounded unattended GNHF sprints.

## Safety contract

- GNHF runs in isolated Git worktrees.
- The target checkout must be clean.
- Every run has an iteration cap and an observable stop condition.
- Push is off by default.
- No merge, deployment, force-push, reset of user work, or secret handling is automated.
- Parallel lanes must have disjoint owned scopes.
- CLI readiness requires a successful version probe, not command presence alone.
- Prompt files are streamed over stdin so detailed PRDs do not hit Windows argv limits.
- Remote installers are allowlisted to official Goose, Google Antigravity, Anthropic, and OpenAI sources, downloaded into a temporary directory, executed, and removed.
- AGY installation and GNHF readiness are separate facts. AGY remains interactive-only unless a supported ACP server command is verified.

## Execute the workstation install

Open PowerShell 7 in `tooling\gnhf` and run:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentSwitchboardWorkstation.ps1 `
  -InstallProfile Core `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

`Core` is the default profile. It installs missing copies of GNHF, Goose CLI, OpenCode, and Antigravity CLI (`agy`), then installs the fleet bundle and writes evidence under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet
```

The important outputs are:

- `state.json`: fleet readiness plus workstation install evidence
- `workstation-install-report.json`: requested profile, actions, command paths, and version probes
- `gnhf-fleet.json`: editable sprint manifest

### Install every automated profile agent

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentSwitchboardWorkstation.ps1 `
  -InstallProfile All `
  -DefaultRepoPath "C:\Users\Cheex\Desktop\dev\agents\AgentSwitchboard"
```

`All` adds GitHub Copilot CLI, Claude Code, Codex CLI, and Pi. These tools may require subscriptions, API access, or their own provider configuration.

### Add one agent without reinstalling a profile

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentSwitchboardWorkstation.ps1 `
  -InstallProfile None `
  -InstallAgent codex,gemini
```

`gemini` is explicit opt-in because Antigravity CLI is the intended Google consumer terminal path. Keep Gemini CLI only for a verified enterprise, API-key, or ACP fallback use case.

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

The validator uses the built-in PowerShell parser and deterministic text/manifest checks. It does not launch agents or mutate a target repository.

```powershell
pwsh -NoLogo -NoProfile -File .\Test-GnhfFleetContracts.ps1
```

It checks PowerShell syntax, manifest shape, official installer allowlists, profile membership, temporary-file cleanup, readiness gating, prompt streaming, controlled failure reporting, and report-directory recovery.

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

`-Wait` is intended for automation and cannot be combined with `-KeepWindowsOpen`.

## Morning review

```powershell
$root = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -File "$root\Get-GnhfFleetStatus.ps1" `
  -ManifestPath "$root\gnhf-fleet.json"
```

Reports are written under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports`.

## Scope discipline

Do not launch multiple agents against the same files. Each prompt must name owned scope, forbidden scope, validation, and an observable stop condition.
