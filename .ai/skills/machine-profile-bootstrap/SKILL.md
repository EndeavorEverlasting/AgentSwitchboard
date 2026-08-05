---
id: machine-profile-bootstrap
version: 1.1.0
status: canonical
---

# Machine Profile Bootstrap

## Trigger

Use when AgentSwitchboard is installed, repaired, relocated, or diagnosed on a Windows environment whose role, user profile, redirected folders, OneDrive convention, operator shell, or repository path can differ. Supported roles are `personal-windows-laptop`, `desktop-workstation`, `admin-box-1`, and `admin-box-2`.

## Required inputs

- repository and exact branch or ref;
- environment role ID, or explicit unresolved state;
- optional explicit workspace or repository root;
- operator shell;
- expected origin;
- local machine-profile evidence when present;
- focused harness manifest, registries, workflows, validators, and proof ceiling.

## Procedure

1. Read `tooling/profiles/windows/harness/machine-profile/codebase-map.json` and `manifest.json`.
2. Read `environment-role.registry.json`, `known-traps.registry.json`, and `workflow-specs.json`.
3. Declare repo, branch, lane, owned and forbidden scope, artifacts, validation, and proof ceiling.
4. Select the role explicitly. Never infer it from username, hostname, tenant label, or remembered path.
5. The personal-laptop role supports `%USERPROFILE%\Desktop\Dev`; the resolved path remains local-only.
6. Desktop and admin roles require explicit path, `AGENT_SWITCHBOARD_REPO`, verified binding, or verified checkout.
7. Verify origin, branch, HEAD, and dirty state before mutation; isolate separately owned work.
8. Run `Get-AgentSwitchboard-MachineProfile.cmd`, then read local evidence.
9. Use the intake, validation, failure-recovery, or handoff workflow matching the state.
10. In cmd.exe, capture `ERRORLEVEL` immediately before another command.
11. Failed WSL repair blocks setup; failed setup blocks live certification.
12. Convert deterministic failures into focused regression coverage and known-trap guidance.
13. Generate status with `Get-MachineProfileHarnessStatus.cmd`.

## Validation

```cmd
python -m unittest tests.test_machine_profile_harness_completeness
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-MachineProfileHarnessCompleteness.ps1
python -m unittest tests.test_machine_profile_bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-MachineProfileBootstrap.ps1
git diff --check
```

## Forbidden scope

- No product-code or governance-contract change in a harness-only sprint.
- No guessed or committed real machine identities or resolved paths.
- No destructive Git, silent checkout movement, stale exit reporting, or pull-over-local-patch.
- No downstream stage after a failed prerequisite.
- No runtime success claim from harness validation.

## Outputs and proof ceiling

Tracked output is the focused manifest, maps, registries, workflows, schema, report template, status reporter, hook, validators, CI, and docs. Generated machine-profile and status evidence stays untracked. The proof ceiling is harness completeness, explicit role routing, local-only path discipline, deterministic validation, and clean handoff rendering.
