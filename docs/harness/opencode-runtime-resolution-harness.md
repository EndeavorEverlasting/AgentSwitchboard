# OpenCode Runtime Resolution Harness

This focused leaf harness distinguishes **executable provenance** from configuration intent when Windows, AgentSwitchboard, GNHF, WSL, or a child process can all resolve a command named `opencode`. It is a semantic salvage of closed PR #113, reconciled onto current `main` without restoring the August shared routing surfaces.

## Working

The harness models native Windows OpenCode under `%APPDATA%\npm`, the AgentSwitchboard WSL-delegating shim at `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd`, and WSL Ubuntu OpenCode under `$HOME/.opencode/bin/opencode`. Fleet `state.json` is declared adapter state only until compared with effective launch identity.

Synthetic fixtures prove positive native/declared-WSL cases and fail closed on shim shadowing, missing wrapper target, and state-command drift. Stable repository-only status:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-OpenCodeRuntimeResolutionStatus.ps1
```

## Broken

This harness does not repair PATH, reinstall OpenCode, remove shims, or rewrite current OpenCode/GNHF launchers. `shim-shadowing-native`, `parent-child-divergence`, and `state-command-drift` are diagnostic classifications, not repair actions.

## Missing

Repository/CI proof cannot establish which executable an operator workstation or failing child process actually launched. Parent `Get-Command`, `where`, `opencode debug config`, file existence, and fleet `state.json` remain discovery evidence only. Live completion requires the exact launch chain and existing end-to-end runtime validation.

## Known traps

- `opencode debug config` proves configuration, not executable provenance.
- `Get-Command opencode` proves only the current process resolver.
- `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd` is a WSL-delegating AgentSwitchboard shim, not a native npm install.
- `%APPDATA%\npm\opencode.ps1` and `opencode.cmd` may be the same native package family.
- A healthy WSL runtime does not prove a native Windows launch used it correctly.
- A `state.json` commandPath is declared state, not effective launch evidence.
- A `uv_spawn` failure belongs to the exact failing process/environment.

## Workflow

1. Run repository-only status and the focused validator.
2. Freeze requested surface and exact launch chain.
3. Apply `runtime-resolution-intake.workflow.json`.
4. Classify supplied evidence with `path-collision-diagnosis.workflow.json`.
5. Emit local/untracked evidence only.
6. Route repair to the current owning runtime/product surface.
7. Use existing end-to-end runtime validation for live completion.

**Shared routing is deferred.** This lane intentionally does not restore the historical skill registration, `SKILLS.md`, `TRIGGERS.md`, root `CODEBASE_MAP.md`, or pre-commit hook. TRIAGE-01 convergence owns any later shared registration decision.

## Salvage disposition

**Preserve:** runtime registry/schema, artifact registry, synthetic fixtures, intake/collision workflows, status reporter, leaf codebase map/composition graph, validator/tests, guide, and leaf Windows/Ubuntu CI.

**Merge into current owners:** source-authority references continue to use current technician readiness, GNHF, OpenCode launcher, WSL repair, and setup surfaces; live proof remains with existing end-to-end runtime validation.

**Retire/defer:** historical global skill registration, `SKILLS.md`/`TRIGGERS.md` edits, root `CODEBASE_MAP.md` edit, and pre-commit hook.

Source: PR #113 / `feat/harness-opencode-runtime-resolution-20260809@2ff3d81ab806b54dceccf593cd0f39b2c17e8bc9`. Salvage integration floor: `main@a2169702905ddcc3a527e74ee8a04e9df271b74d`.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodeRuntimeResolutionHarness.ps1
python tests/test_opencode_runtime_resolution_harness.py
git diff --check
```

Optional Windows-only observation:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-OpenCodeRuntimeResolutionStatus.ps1 -ObserveCurrentProcess
```

The dedicated CI adapter also runs the existing OpenCode LSP and execution-adapter contract validators so this leaf cannot silently collide with those current owners.

## Proof ceiling

Passing repository/CI checks proves tracked leaf completeness and deterministic synthetic classification only. It does not prove a workstation's effective OpenCode child identity, repair PATH, provider delivery, or live runtime success.
