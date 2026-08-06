---
id: machine-profile-bootstrap
version: 1.2.0
status: canonical
---

# Machine Profile Bootstrap

## Trigger

Use when AgentSwitchboard is being installed, repaired, relocated, or diagnosed on a Windows box whose environment role, username, corporate naming, hostname, known-folder redirection, OneDrive convention, operator shell, or repository path may differ from prior machines. Supported operator roles are `personal-windows-laptop`, `desktop-workstation`, `admin-box-1`, and `admin-box-2`.

## Required inputs

- repository and branch or exact intended ref;
- environment role ID, or an explicit unresolved state;
- optional explicit repository root or workspace directory;
- current Windows user context and operator shell;
- expected AgentSwitchboard origin;
- machine-profile and environment-role registries;
- current bootstrap ordering and proof ceiling.

## Procedure

1. Read `tooling/profiles/windows/harness/machine-profile/codebase-map.json` and `manifest.json`.
2. Read `environment-role.registry.json`, `known-traps.registry.json`, and `workflow-specs.json`.
3. Do not guess a repository path or role from remembered usernames, company names, hostnames, Desktop conventions, OneDrive folder labels, or another machine's checkout.
4. Select the environment role explicitly or from a verified local machine binding. The personal-laptop role supports an explicit `%USERPROFILE%\Desktop\Dev` workspace; the resolved path remains local-only. Desktop and admin roles require an explicit path, `AGENT_SWITCHBOARD_REPO`, verified binding, or verified checkout.
5. When the repository is absent and no explicit directory was requested, start with `AgentSwitchboard-Technician-Bootstrap.cmd`. It downloads an immutable commit-pinned detector using Windows PowerShell before repository acquisition.
6. When the operator supplies a workspace directory, use `Bootstrap-AgentSwitchboard-In-Directory.cmd "<workspace>"`; it creates or reuses `<workspace>\AgentSwitchBoard-Live` and delegates to the canonical technician bootstrap with an explicit repository root.
7. When the repository is present, run `Get-AgentSwitchboard-MachineProfile.cmd` or:

   `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1 -Mode Apply`

8. Read `%LOCALAPPDATA%\AgentSwitchboard\machine-profile\machine-profile.json`.
9. Use `repository.recommendedRoot` unless the operator supplied an explicit path or `AGENT_SWITCHBOARD_REPO`.
10. Preserve registry precedence: explicit path, environment override, verified machine binding, verified existing checkout, stable `%USERPROFILE%\dev\AgentSwitchBoard-Live` default.
11. Verify origin, branch, HEAD, and dirty state before mutation. Use an isolated worktree or branch for separately owned work.
12. Select the intake, validation, failure-recovery, or handoff workflow matching the current state.
13. In cmd.exe, use repository wrappers that clear any caller-defined `ERRORLEVEL` variable and capture the dynamic exit immediately after the owned command.
14. A failed WSL repair blocks setup; a failed setup blocks live certification.
15. Convert reproduced deterministic failures into focused regression coverage and known-trap guidance.
16. Report `environmentRoleId`, `profileId`, confidence, reasons, repository-root source, selected root, blockers, branch, HEAD, local evidence path, and proof ceiling.
17. Generate the English and JSON harness report with `Get-MachineProfileHarnessStatus.cmd`. Every emitted command must be location-independent, name its owner and dependency, and remain executable when the caller is outside the repository.
18. For unmerged remote harness work, use `Validate-MachineProfileHarnessCandidate.cmd`; it fetches without force, verifies exact ancestry and head, preserves dirty source work in a detached isolated worktree, runs the owning validators, resolves status artifacts from tracked registries, prints the report, opens it, and propagates failures. Supply `-PullRequestNumber` when a PR exists so the successful report advances the review gate rather than rerunning completed proof.
19. Continue through repository acquisition, PowerShell 7 gate, WSL repair, workstation setup, and live certification without reordering those gates.

## Expected outputs

Tracked:

- deterministic detector and chosen-directory bootstrap;
- focused manifest, codebase map, machine-profile and environment-role registries;
- known-traps and artifact registries;
- intake, validation, failure-recovery, and handoff workflows;
- schemas and synthetic fixtures;
- operator report template, status reporter, hook, candidate validator, PowerShell and Python validators, CI, and operator documentation.

Generated and untracked:

- `machine-profile.json`;
- `machine-profile.env.cmd`;
- `machine-profile.env.ps1`;
- `machine-profile-harness-status.json`;
- `machine-profile-harness-status.md`;
- `machine-profile-harness-candidate-validation.json`.

## Deterministic validation

```cmd
Test-MachineProfileHarness.cmd
python -m unittest tests.test_machine_profile_harness_completeness
python -m unittest tests.test_machine_profile_bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-MachineProfileBootstrap.ps1
python -m unittest tests.test_technician_live_cert_surface
git diff --check
```

Candidate validation syntax:

```cmd
Validate-MachineProfileHarnessCandidate.cmd -SourceRepository "C:\path\to\existing-checkout" -WorktreeRoot "C:\path\to\isolated-worktree" -Branch "feature-branch" -ExpectedHead "40-character-sha" -BaseCommit "40-character-base-sha" -PullRequestNumber 64
```

When `-PullRequestNumber` is omitted, the report emits a location-independent command that opens the branch comparison page so a PR can be created or reviewed.

## Forbidden scope

- No product-code or governance-contract change in a harness-only sprint.
- No guessing from prior usernames, company labels, hostname patterns, OneDrive labels, or remembered paths.
- No replacement of an explicit operator path with an inferred path.
- No silent movement of an existing checkout.
- No reset, clean, stash, overwrite, force update, or unexpected-origin acceptance.
- No committed real machine-profile output or resolved path evidence.
- No stale or shadowed `ERRORLEVEL`, pull-over-local-patch, setup after failed WSL repair, or live certification after failed setup.
- No bare repository-relative next command when the caller may remain in another directory.
- No next command that merely reruns proof already completed when review, merge, protected runtime, or deployment is the actual blocker.
- No package, authentication, provider, launcher, or live-runtime success claim from profile classification or harness validation.

## Stop and escalate

Stop when Windows PowerShell or `curl.exe` is missing, an explicit path cannot be created, the existing target is nonempty but not a valid checkout, origin is unexpected, dirty ownership is unresolved, the checkout is detached unexpectedly, a prerequisite fails, a reboot is required, or repository acquisition fails.

Escalate with the environment role, profile ID, confidence, repository-root source, selected root, exact blocker, transcript and summary paths, preserved checkout state, branch, HEAD, proof ceiling, next-action owner, next-action dependency, and one location-independent executable next command.

The proof ceiling is machine observation, deterministic classification, explicit role routing, repository-root recommendation, harness completeness, candidate isolation, workflow selection, status rendering, and bootstrap ordering. Live workstation success still requires repository-owned repair, setup, and certification evidence.
