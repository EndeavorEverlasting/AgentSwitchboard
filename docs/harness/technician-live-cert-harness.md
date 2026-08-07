# Technician Live-Cert Operational Harness

This scoped harness protects the Windows technician P00-P09 live-certification surface without replacing the repository-family harness or the product behavior owned by the stage and repair scripts.

## Mission

A fresh agent must be able to locate the live-cert implementation, choose the maintenance or field-failure workflow, identify generated evidence, run the correct validators in every required shell, avoid known Windows/PowerShell traps, prove required executables can actually launch before repository mutation, produce an English status report, and hand the sprint off with an exact next command.

The canonical machine-readable entrypoint is:

`tooling/profiles/windows/harness/technician-live-cert/manifest.json`

## What is working

- P00-P08 remain the required core sequence; P09 Hermes remains optional.
- Repository-owned CMD files dispatch stages and repairs and propagate nonzero exit codes.
- `Test-Technician-Toolchain-Preflight.cmd` proves Windows can start a concrete `git.exe`, bounds `git --version`, records every candidate/error, and emits local JSON/Markdown before fetch/worktree/runtime work.
- WSL/Ubuntu repair owns machine-wide feature activation, one-time reboot continuation, Ubuntu registration, and initialization.
- P00 creates local evidence, verifies the current Windows identity, enumerates WSL distributions, and executes a non-interactive Ubuntu Bash probe.
- Generated run evidence remains under `%LOCALAPPDATA%\AgentSwitchboard\technician-live-cert` and is not tracked.
- The focused harness has a codebase map, maintenance workflow, field-failure workflow, artifact registry, schema, validators, opt-in hook, status reporter, operator report template, skill routing, and CI.

## What is broken when a guard fails

A failure is not reduced to “the script does not work.” Classify the exact boundary:

- **Executable launch boundary:** PATH or `Get-Command` finds `git.exe`, but Windows refuses to start it, returns access denied, resolves an App Execution Alias, times out, or produces no valid `git version` result.
- **Parameter-binding timing:** `$PSScriptRoot` or another automatic variable was evaluated in a parameter default before the script body established context.
- **Ambiguous .NET overload:** PowerShell selected a `char/char` overload where the code intended `string/string`; an empty string cannot become one character.
- **Skipped shell:** a validator passed in PowerShell 7 but was never executed in Windows PowerShell 5.1, or vice versa.
- **Unexecuted runtime branch:** hosted CI used `TECHNICIAN_LIVE_CERT_CI_SURFACE=1` and therefore did not prove real WSL/Ubuntu execution.
- **Interactive tooling:** `git diff` opened a pager and automation depended on terminal state.
- **False pass:** a parent process launched but child exit, effective-state readback, required observation, or repeatability was not proven.
- **Proof inflation:** static or fixture evidence was presented as workstation runtime evidence.

Observed field failure outranks static and CI success until the **exact operator command** is rerun successfully.

## What is missing until the live sequence completes

The harness and CI do not prove:

- that the affected workstation can launch Git until its local toolchain-preflight artifact passes;
- repository fetch or exact-head worktree creation merely because Git is installed;
- real WSL feature activation on a specific workstation;
- initialized Ubuntu for the current Windows user;
- visible WezTerm behavior;
- tmux client attachment;
- AGY or OpenCode user-visible launch;
- repeatability;
- rollback;
- operator acceptance.

Those claims require their repository-owned runtime sequence and local artifacts.

## Repository map

- `tooling/profiles/windows/technician-live-cert/` — stage and repair implementation.
- `tooling/profiles/windows/harness/technician-live-cert/` — scoped harness contracts.
- `Test-Technician-Toolchain-Preflight.cmd` — no-Git operator entrypoint for executable launch diagnosis.
- `scripts/Test-WindowsToolchainLaunch.ps1` — bounded Windows Git launch validator and diagnostic artifact generator.
- `scripts/Test-TechnicianLiveCertSurface.ps1` — behavior and surface validator.
- `scripts/Test-TechnicianLiveCertHarness.ps1` — completeness and integration validator.
- `tests/test_technician_live_cert_surface.py` — existing structural contracts.
- `tests/test_technician_live_cert_harness.py` — harness and compatibility contracts.
- `tests/test_windows_toolchain_launch_harness.py` — regression contract for executable launch proof.
- `tooling/profiles/windows/Get-TechnicianLiveCertHarnessStatus.ps1` — JSON and English status artifacts; degrades to a readable BLOCKED report when Git cannot launch.
- `tooling/profiles/windows/hooks/Invoke-TechnicianLiveCertPreCommit.ps1` — opt-in local gate.
- `.github/workflows/technician-live-cert-surface.yml` — cross-shell CI.

## Workflow selection

Use `maintenance.workflow.json` for planned changes to stages, repairs, launchers, manifests, schemas, reports, or validators.

Use `field-failure-repair.workflow.json` when an operator supplies a failed or contradictory live command. Preserve the run evidence, classify the harness gap, repair the executable defect, add a guard that would have failed earlier, run the cross-shell matrix, and rerun the exact operator command.

If failure occurs **before repository identity is proven** and the symptom is `Access is denied`, “This app can’t run on your PC,” bad executable format, App Execution Alias behavior, or failure to start `git.exe`, do not issue another fetch/pull/worktree command. Run:

```cmd
Test-Technician-Toolchain-Preflight.cmd
```

The preflight searches known Git-for-Windows locations plus `Get-Command git.exe -All`, starts candidates with `UseShellExecute = $false`, bounds the wait, captures exit/stdout/stderr/error, and succeeds only when a concrete executable returns `git version` with exit 0.

## Validation order

From the repository root:

```powershell
python -m unittest tests.test_technician_live_cert_harness
python -m unittest tests.test_windows_toolchain_launch_harness
python -m unittest tests.test_technician_live_cert_surface
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-WindowsToolchainLaunch.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-WindowsToolchainLaunch.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TechnicianLiveCertSurface.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TechnicianLiveCertHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertSurface.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertHarness.ps1
git --no-pager diff --check
```

The toolchain launch validator is Windows-only. On Linux CI, its Python contract runs while the live process-launch step is skipped.

Do not substitute `git diff` without `--no-pager` in an automated path.

The opt-in pre-commit gate is:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/hooks/Invoke-TechnicianLiveCertPreCommit.ps1
```

It is never installed implicitly.

## Operator report

Generate the current read-only report:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-TechnicianLiveCertHarnessStatus.ps1
```

The command writes:

- `technician-live-cert-harness-status.json`
- `technician-live-cert-harness-status.md`
- nested toolchain-preflight JSON/Markdown when running on Windows

under the local harness-status evidence root and reports component state, Git launch state, selected executable, guard state, branch, HEAD, proof ceiling, and exact next command. If no usable Git executable is proven, branch/HEAD may remain unavailable and the report stays honestly BLOCKED instead of crashing.

## Failure handling

1. Preserve the active run directory and the exact stage output. If no run directory exists because failure occurred before repo proof, preserve the terminal output/screenshots and create the toolchain-preflight artifact.
2. Record the shell: Command Prompt, Windows PowerShell 5.1, PowerShell 7, WSL Bash, WezTerm, tmux, TUI, or browser.
3. Record the child exit identity and local evidence path.
4. If an external executable is implicated, prove its concrete path and launchability before issuing repository mutation commands.
5. Repair the same branch/evidence chain when the defect is owned and correctable.
6. Add a behavior-level or executable compatibility guard.
7. Run both Windows PowerShell 5.1 and PowerShell 7 validators.
8. Rerun the exact operator command.
9. Report the new run ID and honest proof ceiling.

## Handoff contract

A handoff includes repository, branch/worktree, exact HEAD when Git is available, owned and forbidden paths, files changed, generated artifacts, toolchain launch state, validator results by shell, observed failures, skipped checks, proof ceiling, push/PR state, preserved local work, and one exact executable next command.

When Git itself is the blocker, the exact next command must advance the toolchain prerequisite without depending on Git. Do not hand back another fetch command until the preflight proves a working executable.

## Proof ceiling

This harness proves tracked structure, discoverability, cross-shell parser and contract compatibility, fixture-safe CMD dispatch, bounded Git executable launch proof, noninteractive Git hygiene, local artifact policy, and failure-boundary reporting. It does not prove repository fetch on the affected workstation, workstation runtime behavior, provider behavior, or operator acceptance until those exact stages run successfully.
