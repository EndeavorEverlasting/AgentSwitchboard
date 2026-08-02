---
id: machine-profile-bootstrap
version: 1.0.0
status: canonical
---

# Machine Profile Bootstrap

## Trigger

Use when AgentSwitchboard is being installed, repaired, or relocated on a Windows box whose username, corporate naming, hostname, known-folder redirection, OneDrive convention, or repository path may differ from prior machines.

## Required inputs

- repository and branch;
- optional explicit repository root or workspace directory;
- current Windows user context;
- expected AgentSwitchboard origin;
- machine-profile registry and schema;
- current bootstrap ordering and proof ceiling.

## Procedure

1. Read `tooling/profiles/windows/harness/machine-profile/codebase-map.json`.
2. Do not guess a repository path from remembered usernames, company names, hostnames, Desktop conventions, or OneDrive folder labels.
3. When the repository is absent and no explicit directory was requested, start with `AgentSwitchboard-Technician-Bootstrap.cmd`. It downloads an immutable commit-pinned detector using Windows PowerShell before repository acquisition.
4. When the operator supplies a workspace directory, use `Bootstrap-AgentSwitchboard-In-Directory.cmd "<workspace>"`; it creates or reuses `<workspace>\AgentSwitchBoard-Live` and delegates to the canonical technician bootstrap with an explicit repository root.
5. When the repository is present, run `Get-AgentSwitchboard-MachineProfile.cmd` or:

   `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1 -Mode Apply`

6. Read `%LOCALAPPDATA%\AgentSwitchboard\machine-profile\machine-profile.json`.
7. Use `repository.recommendedRoot` unless the operator supplied an explicit path or `AGENT_SWITCHBOARD_REPO`.
8. Preserve the precedence encoded by the registry: explicit path, environment override, verified machine binding, verified existing checkout, stable `%USERPROFILE%\dev\AgentSwitchBoard-Live` default.
9. Report `profileId`, confidence, reasons, selected repository root, detected blockers, and the local evidence path.
10. Continue through repository acquisition, PowerShell 7 gate, WSL repair, workstation setup, and live certification without reordering those gates.

## Expected outputs

Tracked:

- deterministic detector;
- generic chosen-directory bootstrap;
- machine-profile registry, codebase map, schema, and synthetic fixtures;
- focused PowerShell and Python validators;
- CI workflow;
- operator documentation.

Generated and untracked:

- `machine-profile.json`;
- `machine-profile.env.cmd`;
- `machine-profile.env.ps1`.

## Deterministic validation

```powershell
python -m unittest tests.test_machine_profile_bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-MachineProfileBootstrap.ps1
python -m unittest tests.test_technician_live_cert_surface
git diff --check
```

## Forbidden scope

- No guessing from prior usernames, company labels, hostname patterns, or OneDrive folder names.
- No replacement of an explicit operator path with an inferred path.
- No silent movement of an existing checkout.
- No reset, clean, stash, overwrite, or unexpected-origin acceptance to force acquisition.
- No committed real machine-profile output; usernames, hostnames, tenant names, and paths remain local-only.
- No package, authentication, provider, launcher, or live-runtime success claim from profile classification.

## Stop and escalate

Stop when Windows PowerShell or `curl.exe` is missing, an explicit path cannot be created, the existing target is nonempty but not a valid checkout, the origin is unexpected, the checkout is dirty or detached, or repository acquisition fails.

Escalate with the profile ID, confidence, selected repository root, exact blocking boundary, local evidence path, preserved checkout state, proof ceiling, and one safe next command.

The proof ceiling is machine observation, deterministic classification, repository-root recommendation, and bootstrap ordering. Live workstation success still requires the repository-owned certification stages.
