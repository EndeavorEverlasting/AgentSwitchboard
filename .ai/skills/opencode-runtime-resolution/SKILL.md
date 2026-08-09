---
id: opencode-runtime-resolution
version: 1.0.0
status: canonical
---

# OpenCode Runtime Resolution

## Trigger

Use when OpenCode configuration looks correct in one shell but AgentSwitchboard, GNHF, WSL, a command shim, or another child-process boundary appears to launch a different OpenCode runtime or fails with a spawn/path error such as `uv_spawn`.

Select this skill before reinstalling OpenCode or editing PATH when more than one OpenCode surface may exist.

## Inputs

- repository branch and exact commit;
- requested runtime surface: `native-windows`, `wsl-ubuntu`, or `unknown`;
- exact operator or agent launch command;
- `Get-Command opencode -All` from the parent process when available;
- process PATH snapshot from each observed boundary;
- `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd` content when present;
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json` OpenCode adapter record when present;
- effective child launch resolution when instrumentation exists;
- bounded stdout, stderr, exit code, and first failing stage.

## Procedure

1. Load `tooling/profiles/windows/harness/opencode-runtime-resolution/codebase-map.json` and `runtime-resolution.registry.json`.
2. Freeze the requested surface and exact launch chain. Do not infer a native request merely because a parent PowerShell resolves the npm package.
3. Run the `runtime-resolution-intake.workflow.json` procedure.
4. Treat `opencode debug config` as configuration evidence only. It does not prove executable provenance.
5. Treat parent `Get-Command`, `where`, file existence, and fleet `state.json` as discovery only until compared with the effective child launch.
6. When `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd` exists, identify it explicitly as an AgentSwitchboard WSL shim rather than another native OpenCode installation.
7. Compare the requested surface, parent resolver, effective launch resolver, wrapper target, process PATH ordering, and fleet-state command identity with `path-collision-diagnosis.workflow.json`.
8. Fail closed as `shim-shadowing-native` when a native Windows request resolves through the AgentSwitchboard WSL shim or targets WSL Ubuntu.
9. Fail closed as `parent-child-divergence` when parent and child runtime families disagree without a declared platform transition.
10. Preserve the first divergent boundary and bounded child diagnostics. A parent-shell success probe never replaces the failing child evidence.
11. Emit the registered local artifacts and English report. Keep runtime evidence untracked.
12. Route repair to the owning product/runtime surface. Harness-only work does not edit PATH, delete shims, reinstall packages, or modify launchers.
13. For a completion claim across AgentSwitchboard -> GNHF -> OpenCode -> child tool boundaries, continue with `.ai/skills/end-to-end-runtime-validation/SKILL.md` and rerun the exact operator path after repair.

## Outputs

- selected resolution classification;
- `opencode-runtime-run-context.json`;
- `opencode-runtime-resolution-snapshot.json`;
- `opencode-runtime-classification.json`;
- `opencode-runtime-operator-report.md`;
- `opencode-runtime-final-handoff.json`.

Generated runtime evidence remains local-operational and untracked.

## Deterministic validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodeRuntimeResolutionHarness.ps1
python tests/test_opencode_runtime_resolution_harness.py
git diff --check
```

A contract pass proves tracked harness completeness and deterministic synthetic classification only. It does not prove which executable the failing OpenCode child process used on an operator workstation.

## Forbidden scope

- No user or machine PATH mutation from this harness.
- No deletion or rewrite of `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd`.
- No OpenCode, Hermes, uv, Node, npm, WSL, or package installation or removal.
- No launcher or setup product-code mutation in a harness-only sprint.
- No use of `opencode debug config`, parent `Get-Command`, or `state.json` alone as child executable proof.
- No tracked raw environment dumps, credentials, private hostnames, customer data, or secret-bearing process command lines.
- No runtime success claim from CI, configuration intent, file existence, or parent process exit alone.

## Stop and escalate

Stop proof promotion when the requested surface is unknown, the exact launch chain is missing, the effective child resolver cannot be observed, wrapper target identity is unavailable, PATH evidence is contradictory, or the failing process loses stdout/stderr/exit identity.

Escalate with the requested surface, exact command, parent resolver, effective resolver or unresolved boundary, wrapper target, fleet-state command identity, first divergent boundary, bounded diagnostics, proof ceiling, and one exact next command owned by the repair or end-to-end runtime lane.
