# OpenCode Runtime Resolution Harness

This focused harness exists because AgentSwitchboard can legitimately expose more than one command named `opencode` on the same Windows workstation. A clean OpenCode configuration is not enough to prove that AgentSwitchboard, GNHF, or a child process later resolves the same executable.

## Working

The tracked harness now distinguishes three owned runtime surfaces:

- native Windows OpenCode installed through npm, normally under `%APPDATA%\npm\opencode.cmd` / `opencode.ps1`;
- the AgentSwitchboard Windows command shim under `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd`, which is a wrapper that delegates to WSL Ubuntu;
- the WSL Ubuntu OpenCode runtime under `$HOME/.opencode/bin/opencode`.

It also records `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json` as declared adapter state that must be compared with effective resolution rather than treated as runtime proof.

The synthetic contracts prove `native-consistent`, `declared-wsl-consistent`, and the newly exposed `shim-shadowing-native` failure mode. The completeness validator requires every map, registry, workflow, schema, fixture, skill, report surface, hook, test, and CI file to remain tracked.

## Broken

The repository currently contains overlapping setup surfaces that can produce a native Windows npm OpenCode and an AgentSwitchboard `opencode.cmd` shim targeting WSL. The technician readiness path can prepend `%LOCALAPPDATA%\AgentSwitchboard\bin` to the user PATH and rebuild a process PATH that also includes Hermes and npm locations.

That overlap is not repaired by this harness sprint because launcher/setup product code and workstation mutation are outside the owned scope. A native OpenCode request that later resolves through the WSL shim is now a named, fail-closed harness classification instead of an unexplained environment anomaly.

## Missing

The exact OpenCode child process that emitted the observed spawn failure has not been instrumented by this tracked harness. Parent-shell `Get-Command`, `where`, `opencode debug config`, file existence, and fleet `state.json` remain discovery evidence only.

A runtime completion claim still requires capture of the exact AgentSwitchboard -> GNHF -> OpenCode launch chain, effective child executable identity, PATH snapshot at the divergent boundary, bounded stdout/stderr/exit identity, and rerun after any repair. That proof belongs to `end-to-end-runtime-validation`.

## Known traps

- `opencode debug config` proves resolved configuration, not executable provenance.
- `Get-Command opencode` in one PowerShell proves only that process.
- `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd` is not another native npm installation; it is an AgentSwitchboard WSL shim.
- `%APPDATA%\npm\opencode.ps1` and `%APPDATA%\npm\opencode.cmd` may be two launch shims for the same native package family and should not be misclassified as separate runtimes.
- A healthy `$HOME/.opencode/bin/opencode` in WSL does not prove a native Windows launch is correct.
- A `state.json` commandPath is declared state, not effective child-process proof.
- `uv_spawn` must be attributed to the exact failing process/environment. A parent `uv --version` success is insufficient.
- Do not fix this by deleting shims or editing PATH during diagnosis. First prove the requested surface and the first divergent boundary.

## Workflow

1. Run repository-only status and the completeness validator.
2. Select `.ai/skills/opencode-runtime-resolution/SKILL.md` for any parent/child OpenCode identity disagreement or spawn/path failure.
3. Freeze the requested surface and exact launch chain.
4. Apply `runtime-resolution-intake.workflow.json`.
5. Classify evidence with `path-collision-diagnosis.workflow.json`.
6. Emit local untracked artifacts under the artifact registry.
7. Route repair to the owning runtime/product surface; do not mutate the machine from the harness.
8. After repair, rerun the exact operator path through `.ai/skills/end-to-end-runtime-validation/SKILL.md`.

## Artifacts

Default generated evidence root: `%TEMP%\AgentSwitchboard\OpenCodeRuntimeResolution\<run-id>`.

Expected artifacts are `opencode-runtime-run-context.json`, `opencode-runtime-resolution-snapshot.json`, `opencode-runtime-classification.json`, `opencode-runtime-operator-report.md`, and `opencode-runtime-final-handoff.json`. They are local-operational and untracked.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodeRuntimeResolutionHarness.ps1
python tests/test_opencode_runtime_resolution_harness.py
git diff --check
```

Optional read-only current-process observation:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-OpenCodeRuntimeResolutionStatus.ps1 -ObserveCurrentProcess
```

The opt-in pre-commit helper is `tooling/profiles/windows/hooks/Invoke-OpenCodeRuntimeResolutionPreCommit.ps1`. It is never installed implicitly.

## Proof ceiling

Passing CI proves tracked harness completeness and deterministic synthetic classification. It does **not** prove which OpenCode executable an operator workstation or failing GNHF child process actually launched, does not repair PATH, and does not establish live runtime success.
