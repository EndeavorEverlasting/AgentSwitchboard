# Native Windows OpenCode system bootstrap

AgentSwitchboard owns a complete-script Windows path for installing OpenCode machine-wide and enabling its stable LSP integration without depending on a user-local Node/npm runtime or assuming a package manager.

## Operator entrypoint

Run the repository-owned entrypoint from an elevated Windows shell:

```cmd
Bootstrap-OpenCode-SystemWide.cmd
```

The entrypoint routes through `Pull-And-Run-AgentSwitchboard.cmd bootstrap-opencode`, refreshes the selected repository ref through the existing safe dispatcher, and executes `tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1` as one complete PowerShell script.

Do **not** copy individual `if {}` / `else {}` fragments into an interactive PowerShell prompt. PowerShell parses the tracked `.ps1` as a complete unit before it executes, so control-flow syntax defects fail before any bootstrap mutation instead of surfacing halfway through a pasted sequence.

## What Apply ascertains first

Before machine mutation, the script verifies the Windows/PowerShell execution floor, x64 architecture, administrator elevation, system paths, existing managed OpenCode config state, current official `anomalyco/opencode` release, exact `opencode-windows-x64.zip` asset, and the release-provided SHA-256 digest.

It deliberately does **not** assume Chocolatey, Scoop, winget, npm, Node, or any application-private runtime. The official release archive is the installation source.

## Machine-wide state

Apply converges these machine surfaces:

- executable: `%ProgramFiles%\OpenCode\opencode.exe`;
- PATH: `%ProgramFiles%\OpenCode` in the **Machine** PATH;
- managed config: `%ProgramData%\opencode\opencode.json`;
- required managed setting: `"lsp": true`.

Existing valid JSON properties are preserved. When an existing managed JSON file must change, the pre-change copy is stored with the local run receipt. Existing managed JSONC causes a fail-closed result rather than creating a competing config or stripping comments.

The bootstrap does not persist a model choice, change provider authentication, collect credentials, or use a user-profile npm installation.

## LSP proof boundary

`lsp=true` removes the configuration-level disabled state and allows OpenCode's supported built-in language servers to start when a matching file and that server's prerequisites are present. It **does not prove** that a language server is active.

Apply additionally runs `opencode debug config` from an empty temporary directory and requires the resolved config to show LSP enabled. That proves OpenCode itself loaded the managed setting; it still does not prove an active language server.

For active proof, launch OpenCode after bootstrap, open a supported source file in the target repository, and observe the OpenCode LSP/runtime diagnostics for that file. PowerShell source remains covered by repository PowerShell validators unless/until the active OpenCode runtime exposes a supported PowerShell language-server path.

After machine-wide Apply succeeds, optional per-launch free-model LSP launchers still come from the existing OpenCode LSP workstation Configure path. That harness now prefers `%ProgramFiles%\OpenCode\opencode.exe` when the native bootstrap installed a healthy machine-wide binary:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Configure -RepoPath .
```

## Inspect mode

The owner script supports a local, non-mutating inspection:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1 -Mode Inspect
```

Inspect reports the installed machine-wide version, Machine PATH presence, managed config location, whether managed `lsp=true` currently reads back, and when the machine-wide binary is present the result of `opencode debug config` for resolved LSP enablement. It does not query package managers and does not require network access.

## Dirty checkout behavior

`Pull-And-Run-AgentSwitchboard.cmd bootstrap-opencode` still prefers a clean fast-forward refresh. When the checkout is dirty, `bootstrap-opencode` warns and applies the local `Install-AgentSwitchboardOpenCode.ps1` from that worktree instead of failing closed on local changes. Machine mutation never rewrites Git state.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodeNativeSystemBootstrap.ps1 -RootPath .
python -m unittest tests.test_opencode_native_system_bootstrap -v
```

The focused validator parses every touched PowerShell source as a complete script before running the dependency-free contract. On Windows it also executes the non-mutating Inspect path.
