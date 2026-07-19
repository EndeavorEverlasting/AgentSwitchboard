# OpenCode free-model defaults for WezTerm and tmux

The managed WSL OpenCode instance must default to an OpenCode Zen free model rather than a paid DeepSeek provider model.

Managed global config:

```text
~/.config/opencode/opencode.json
```

Managed default and small model:

```text
opencode/deepseek-v4-flash-free
```

The OpenCode Zen picker is restricted to these provider-local IDs:

- `deepseek-v4-flash-free`
- `mimo-v2.5-free`
- `north-mini-code-free`
- `nemotron-3-ultra-free`

These free endpoints are limited-time provider offerings. The manifest and installer provide a reviewed allowlist, but current availability still has to be confirmed by OpenCode. The installer does not authenticate, inspect credential values, or silently choose a paid model.

## Preferred reusable repair workflow

Run the repository-owned workflow instead of reconstructing recovery commands from chat history:

```text
Repair-OpenCodeFreeDefaults.cmd
```

The one-click entrypoint delegates to `tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1`. The workflow:

1. inspects the source checkout without rewriting it;
2. fetches the reviewed remote branch;
3. verifies an optional commit belongs to that branch;
4. creates or safely reuses a clean isolated detached worktree;
5. runs the managed installer from the validated worktree;
6. independently reads back the effective OpenCode settings;
7. writes run context, artifact registry, an English operator report, and a compressed handoff.

Runtime evidence is stored outside Git under:

```text
%LOCALAPPDATA%\AgentSwitchboard\OpenCodeFreeDefaults\runs\<run-id>\
```

Read-only status:

```powershell
& {
    $RepoPath = Join-Path $HOME "Desktop\dev\AgentSwitchboard"

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "AgentSwitchboard repository not found: $RepoPath"
    }

    Set-Location -LiteralPath $RepoPath

    & pwsh -NoLogo -NoProfile -File .\tooling\wsl\Get-OpenCodeFreeDefaultsHarnessStatus.ps1
}
```

The complete workflow contract is under `tooling/wsl/harness/opencode-free-defaults/`.

## Managed WSL dependency

The configurator uses `jq` to preserve unrelated OpenCode settings while updating only the managed fields. When `jq` is absent and `opencode.autoInstallDependencies` is `true`, apply mode runs a bounded WSL-root `apt-get update` and installs only the Ubuntu `jq` package with `--no-install-recommends`.

Plan mode never installs packages. It reports whether `jq` is missing and whether apply mode would install it. A failed or unavailable `apt` operation stops configuration before the OpenCode file is changed.

The installer normalizes its Bash configurator to LF, stages it inside WSL, and does not execute the Windows-mounted `.sh` file directly.

## Apply the lower-level installer directly

The reusable repair workflow is preferred. The lower-level installer remains available for development and focused diagnostics.

```powershell
& {
    $RepoPath = Join-Path $HOME "Desktop\dev\AgentSwitchboard"

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "AgentSwitchboard repository not found: $RepoPath"
    }

    Set-Location -LiteralPath $RepoPath

    $ManifestPath = Join-Path $RepoPath "tooling\wsl\tmux-gnhf-workstation.example.json"
    $InstallerPath = Join-Path $RepoPath "tooling\wsl\Set-OpenCodeFreeDefaults.ps1"

    & pwsh -NoLogo -NoProfile -File $InstallerPath -ManifestPath $ManifestPath
    $InstallerExitCode = $LASTEXITCODE

    if ($InstallerExitCode -ne 0) {
        throw "OpenCode free-default installation failed with exit code $InstallerExitCode."
    }
}
```

Plan without changing WSL packages or the OpenCode config:

```powershell
& {
    $RepoPath = Join-Path $HOME "Desktop\dev\AgentSwitchboard"

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "AgentSwitchboard repository not found: $RepoPath"
    }

    Set-Location -LiteralPath $RepoPath

    $ManifestPath = Join-Path $RepoPath "tooling\wsl\tmux-gnhf-workstation.example.json"
    $InstallerPath = Join-Path $RepoPath "tooling\wsl\Set-OpenCodeFreeDefaults.ps1"

    & pwsh -NoLogo -NoProfile -File $InstallerPath -ManifestPath $ManifestPath -PlanOnly
}
```

The full WezTerm/tmux installer also applies this configuration during setup:

```powershell
& {
    $RepoPath = Join-Path $HOME "Desktop\dev\AgentSwitchboard"

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "AgentSwitchboard repository not found: $RepoPath"
    }

    Set-Location -LiteralPath $RepoPath

    $ManifestPath = Join-Path $RepoPath "tooling\wsl\tmux-gnhf-workstation.example.json"
    $WorkspaceInstaller = Join-Path $RepoPath "tooling\wsl\Install-TmuxGnhfWorkspace.ps1"

    & pwsh -NoLogo -NoProfile -File $WorkspaceInstaller -ManifestPath $ManifestPath -Apply
}
```

## Inspect the installed WSL configuration

From Windows PowerShell 7:

```powershell
& {
    $RepoPath = Join-Path $HOME "Desktop\dev\AgentSwitchboard"

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "AgentSwitchboard repository not found: $RepoPath"
    }

    Set-Location -LiteralPath $RepoPath

    & wsl.exe -d Ubuntu -e bash -lc 'jq -e -c "{model,small_model,share,whitelist:.provider.opencode.whitelist}" "$HOME/.config/opencode/opencode.json"'
    $InspectionExitCode = $LASTEXITCODE

    if ($InspectionExitCode -ne 0) {
        throw "OpenCode configuration inspection failed with exit code $InspectionExitCode."
    }
}
```

Expected core values:

```json
{
  "model": "opencode/deepseek-v4-flash-free",
  "small_model": "opencode/deepseek-v4-flash-free",
  "share": "disabled",
  "whitelist": [
    "deepseek-v4-flash-free",
    "mimo-v2.5-free",
    "north-mini-code-free",
    "nemotron-3-ultra-free"
  ]
}
```

The lower-level installer also writes runtime evidence outside the repository:

```text
~/.local/state/agent-switchboard/tmux-gnhf/opencode-free-defaults-summary.json
```

## OpenCode precedence and explicit paid overrides

The global `model` changes the normal OpenCode default used by WezTerm and tmux sessions. It also prevents OpenCode from reusing the last paid DeepSeek V4 Pro selection as its ordinary default.

An explicit OpenCode `--model` argument has higher priority than the config file. AgentSwitchboard provider-routed runs may also set process-local `OPENCODE_CONFIG_CONTENT`. Those explicit mechanisms are reserved for a deliberately selected route and can override the free default for that process.

The unattended workstation proof does not use a paid fallback when no model is explicitly requested. It reads the managed config first, then selects the first currently advertised model from the reviewed free allowlist, and stops when no approved free model is available.

## Authentication boundary

OpenCode Zen still has to be connected through OpenCode before its hosted models can answer. Use OpenCode's provider connection flow inside Ubuntu. The AgentSwitchboard installer changes model selection and visibility only; it does not write or expose credentials.
