# Native Windows OpenCode reversible system bootstrap

AgentSwitchboard owns a complete-script Windows path for installing OpenCode machine-wide, enabling its stable LSP integration, **and reversing only the machine changes AgentSwitchboard owns**. It does not depend on a user-local Node/npm runtime or assume a package manager.

OpenCode is the reference adapter for the repository-wide reversible bootstrap lifecycle in `docs/harness/system-bootstrap-lifecycle.md`.

## Operator entrypoints

Apply from an elevated Windows shell:

```cmd
Bootstrap-OpenCode-SystemWide.cmd
```

Remove AgentSwitchboard-owned machine changes:

```cmd
Unbootstrap-OpenCode-SystemWide.cmd
```

Inspect without mutation:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1 -Mode Inspect
```

The Apply entrypoint routes through `Pull-And-Run-AgentSwitchboard.cmd bootstrap-opencode`. Remove calls the same canonical owner script directly with `-Mode Remove`; it does not fetch, pull, reset, clean, or otherwise rewrite repository state.

Do **not** copy individual `if {}` / `else {}` fragments into an interactive PowerShell prompt. PowerShell parses the tracked `.ps1` as a complete unit before execution.

## Lifecycle ownership

Durable machine ownership is recorded at:

```text
%ProgramData%\AgentSwitchboard\bootstrap-lifecycle\opencode\state.json
```

That machine-level state—not a user-local receipt—is the authority used by Remove. It records the original pre-ASB baseline and the exact deltas later owned by ASB.

A local human-readable/run receipt is still emitted under `%LOCALAPPDATA%\AgentSwitchboard\opencode-native-bootstrap\runs\...`, but local receipts are evidence, not deletion authority.

Inspect reports the lifecycle status, whether ownership is recorded, and whether `Remove` is currently safe. An installed resource without lifecycle ownership is treated as **present but unowned**, not something ASB is free to delete.

## What Apply ascertains first

Before machine payload mutation, Apply verifies the Windows/PowerShell execution floor, x64 architecture, administrator elevation, system paths, existing durable lifecycle state, existing managed OpenCode config state, current official `anomalyco/opencode` release, exact `opencode-windows-x64.zip` asset, and release-provided SHA-256 digest.

It deliberately does **not** assume Chocolatey, Scoop, winget, npm, Node, or an application-private runtime.

Before its first reversible machine payload mutation, Apply persists a lifecycle baseline. If a preexisting `opencode.exe` must be replaced, that exact binary is copied into the lifecycle backup root and SHA-256 verified **before** replacement.

## Machine-wide surfaces

Apply can own these deltas:

- executable: `%ProgramFiles%\OpenCode\opencode.exe`;
- exact Machine PATH entry: `%ProgramFiles%\OpenCode`;
- managed config properties in `%ProgramData%\opencode\opencode.json`;
- required managed setting: `"lsp": true`;
- `$schema` only when ASB had to add it.

The lifecycle does not imply ownership of the whole ProgramData config directory or the user's OpenCode state.

## Remove semantics

Remove means **undo AgentSwitchboard's changes**, not “purge OpenCode.”

Before performing any rollback mutation, it checks every ASB-owned surface for drift. If one has drifted, Remove stops before destructive rollback and records the lifecycle as drifted.

### Binary

If ASB originally created `opencode.exe`, Remove deletes it only when the current SHA-256 still equals the recorded post-Apply SHA-256. If ASB replaced a preexisting binary, Remove first verifies both the current installed binary and the pre-ASB backup, then restores that backup and verifies its original SHA-256.

The install directory is removed only when ASB created it and it is empty after owned-file rollback. There is no recursive directory wipe.

### Machine PATH

If `%ProgramFiles%\OpenCode` existed in Machine PATH before ASB, it survives Remove. ASB removes the entry only when lifecycle state says `addedByAsb=true`.

### Managed JSON

The shared config is rolled back at **property level**. If ASB changed `lsp` or `$schema`, lifecycle state records whether the property previously existed and its exact previous value.

Remove requires the current ASB-owned property to still equal the value ASB applied. Then it restores or removes only that property while preserving unrelated properties added or changed later. A newly appeared managed JSONC file, invalid JSON, or changed ASB-owned property blocks automated rollback.

### Explicitly not targeted

Remove never targets OpenCode provider authentication, API credentials, sessions, project state, model preferences, user settings, or unrelated caches/logs.

## Legacy/pre-lifecycle installations

An OpenCode installation that is present without `%ProgramData%\AgentSwitchboard\bootstrap-lifecycle\opencode\state.json` is **not automatically adopted as ASB-owned**. Even when its layout resembles a historical ASB install, Remove fails closed rather than guessing.

Running a lifecycle-aware Apply establishes ownership only for mutations made from that point forward. This conservative boundary prevents a new uninstaller from retroactively claiming and deleting machine state it cannot prove it created.

## LSP proof boundary

`lsp=true` removes the configuration-level disabled state and allows OpenCode's supported built-in language servers to start when a matching file and that server's prerequisites are present. It **does not prove** that a language server is active.

Apply runs `opencode debug config` from an empty temporary directory and requires resolved config to show LSP enabled. The probe clears inherited `OPENCODE_CONFIG`, `OPENCODE_CONFIG_CONTENT`, and `OPENCODE_CONFIG_DIR` so overrides cannot fake managed `%ProgramData%\opencode` proof.

For active proof, launch OpenCode after bootstrap, open a supported source file in the target repository, and observe OpenCode LSP/runtime diagnostics for that file.

Optional per-launch free-model LSP launchers still come from the existing OpenCode LSP workstation Configure path:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Configure -RepoPath .
```

## Dirty checkout behavior

`Pull-And-Run-AgentSwitchboard.cmd bootstrap-opencode` still prefers a clean fast-forward refresh. When the checkout is dirty, `bootstrap-opencode` warns and applies the local lifecycle owner from that worktree instead of rewriting local Git state.

`Unbootstrap-OpenCode-SystemWide.cmd` never performs repository synchronization at all; rollback authority comes from durable ProgramData lifecycle state.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-SystemBootstrapLifecycleContracts.ps1 -RootPath .
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodeNativeSystemBootstrap.ps1 -RootPath .
python -m unittest tests.test_system_bootstrap_lifecycle tests.test_opencode_native_system_bootstrap -v
```

The shared lifecycle validator tests atomic lifecycle-state persistence, history, SHA-256 helpers, and PATH delta behavior in temporary locations. The focused OpenCode validator also parses every touched PowerShell source as a complete script and, on Windows, runs non-mutating Inspect.

## Proof ceiling

Repository and CI proof establish lifecycle contracts, ownership-state mechanics, rollback guards, and non-mutating inspection. They do not prove physical Apply/Remove on Admin Box 1 until those operations are run there. Active LSP remains a still-higher runtime proof gate.
