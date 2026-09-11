# Native Windows OpenCode system bootstrap

AgentSwitchboard owns a complete-script Windows path for installing OpenCode machine-wide and enabling its stable LSP integration without depending on a user-local Node/npm runtime or assuming a package manager.

## Operator entrypoint

Canonical Windows technician checkout / use path:

```text
%USERPROFILE%\dev\AgentSwitchBoard-Live
```

PowerShell does not run bare `.cmd` names from the current directory. From that checkout:

```powershell
Set-Location -LiteralPath "$env:USERPROFILE\dev\AgentSwitchBoard-Live"
.\Bootstrap-OpenCode-SystemWide.cmd
```

From cmd.exe:

```cmd
cd /d "%USERPROFILE%\dev\AgentSwitchBoard-Live"
Bootstrap-OpenCode-SystemWide.cmd
```

If the canonical checkout is missing, acquire it with `AgentSwitchboard-Technician-Bootstrap.cmd` first. Do not invent Desktop, OneDrive, or backup clone paths. `Bootstrap-OpenCode-SystemWide.cmd` refuses to mutate from a noncanonical script location when a different target checkout is required.

The entrypoint routes through `Pull-And-Run-AgentSwitchboard.cmd bootstrap-opencode`, refreshes the selected repository ref through the existing safe dispatcher when the checkout is clean, and executes `tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1` as one complete PowerShell script.

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

For active proof, launch OpenCode after bootstrap, open a supported source file in the target repository, and observe the OpenCode LSP/runtime diagnostics for that file. PowerShell source remains covered by repository PowerShell validators unless/until the active OpenCode runtime exposes a supported PowerShell language-server path.

## Inspect mode

The owner script supports a local, non-mutating inspection:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1 -Mode Inspect
```

Inspect reports the installed machine-wide version, Machine PATH presence, managed config location, and whether managed `lsp=true` currently reads back. It does not query package managers and does not require network access.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodeNativeSystemBootstrap.ps1 -RootPath .
python -m unittest tests.test_opencode_native_system_bootstrap -v
```

The focused validator parses every touched PowerShell source as a complete script before running the dependency-free contract. On Windows it also executes the non-mutating Inspect path.
