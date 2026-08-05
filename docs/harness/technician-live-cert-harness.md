# Technician Live-Cert Operational Harness

This scoped harness protects the Windows technician P00-P09 live-certification surface without replacing the repository-family harness or the product behavior owned by the stage and repair scripts.

## Mission

A fresh agent must be able to locate the live-cert implementation, choose the maintenance or field-failure workflow, identify generated evidence, run the correct validators in every required shell, avoid known Windows/PowerShell traps, produce an English status report, and hand the sprint off with an exact next command.

The canonical machine-readable entrypoint is:

`tooling/profiles/windows/harness/technician-live-cert/manifest.json`

## What is working

- P00-P08 remain the required core sequence; P09 Hermes remains optional.
- Repository-owned CMD files dispatch stages and repairs and propagate nonzero exit codes.
- WSL/Ubuntu repair owns machine-wide feature activation, one-time reboot continuation, Ubuntu registration, and initialization.
- P00 creates local evidence, verifies the current Windows identity, enumerates WSL distributions, and executes a non-interactive Ubuntu Bash probe.
- Generated run evidence remains under `%LOCALAPPDATA%\AgentSwitchboard\technician-live-cert` and is not tracked.
- The focused harness now has a codebase map, maintenance workflow, field-failure workflow, artifact registry, schema, validators, opt-in hook, status reporter, operator report template, skill routing, and CI.

## What is broken when a guard fails

A failure is not reduced to “the script does not work.” Classify the exact boundary:

- **Parameter-binding timing:** `$PSScriptRoot` or another automatic variable was evaluated in a parameter default before the script body established context.
- **Ambiguous .NET overload:** PowerShell selected a `char,char` overload where the code intended `string,string`; an empty string cannot become one character.
- **Skipped shell:** a validator passed in PowerShell 7 but was never executed in Windows PowerShell 5.1, or vice versa.
- **Unexecuted runtime branch:** hosted CI used `TECHNICIAN_LIVE_CERT_CI_SURFACE=1` and therefore did not prove real WSL/Ubuntu execution.
- **Interactive tooling:** `git diff` opened a pager and automation depended on terminal state.
- **False pass:** a parent process launched but child exit, effective-state readback, required observation, or repeatability was not proven.
- **Proof inflation:** static or fixture evidence was presented as workstation runtime evidence.

Observed field failure outranks static and CI success until the **exact operator command** is rerun successfully.

## What is missing until the live sequence completes

The harness and CI do not prove:

- real WSL feature activation on a specific workstation;
- initialized Ubuntu for the current Windows user;
- visible WezTerm behavior;
- tmux client attachment;
- AGY or OpenCode user-visible launch;
- repeatability;
- rollback;
- operator acceptance.

Those claims require the repository-owned live-cert sequence and local run artifacts.

## Repository map

- `tooling/profiles/windows/technician-live-cert/` — stage and repair implementation.
- `tooling/profiles/windows/harness/technician-live-cert/` — scoped harness contracts.
- `scripts/Test-TechnicianLiveCertSurface.ps1` — behavior and surface validator.
- `scripts/Test-TechnicianLiveCertHarness.ps1` — completeness and integration validator.
- `tests/test_technician_live_cert_surface.py` — existing structural contracts.
- `tests/test_technician_live_cert_harness.py` — harness and compatibility contracts.
- `tooling/profiles/windows/Get-TechnicianLiveCertHarnessStatus.ps1` — JSON and English status artifacts.
- `tooling/profiles/windows/hooks/Invoke-TechnicianLiveCertPreCommit.ps1` — opt-in local gate.
- `.github/workflows/technician-live-cert-surface.yml` — cross-shell CI.

## Workflow selection

Use `maintenance.workflow.json` for planned changes to stages, repairs, launchers, manifests, schemas, reports, or validators.

Use `field-failure-repair.workflow.json` when an operator supplies a failed or contradictory live command. Preserve the run evidence, classify the harness gap, repair the executable defect, add a guard that would have failed earlier, run the cross-shell matrix, and rerun the exact operator command.

## Validation order

From the repository root:

```powershell
python -m unittest tests.test_technician_live_cert_harness
python -m unittest tests.test_technician_live_cert_surface
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TechnicianLiveCertSurface.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-TechnicianLiveCertHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertSurface.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianLiveCertHarness.ps1
git --no-pager diff --check
```

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

under the local harness-status evidence root and reports component, guard, branch, HEAD, proof ceiling, and exact next command.

## Failure handling

1. Preserve the active run directory and the exact stage output.
2. Record the shell: Command Prompt, Windows PowerShell 5.1, PowerShell 7, WSL Bash, WezTerm, tmux, TUI, or browser.
3. Record the child exit identity and local evidence path.
4. Repair the same branch/evidence chain when the defect is owned and correctable.
5. Add a behavior-level or executable compatibility guard.
6. Run both Windows PowerShell 5.1 and PowerShell 7 validators.
7. Rerun the exact operator command.
8. Report the new run ID and honest proof ceiling.

## Handoff contract

A handoff includes repository, branch/worktree, exact HEAD, owned and forbidden paths, files changed, generated artifacts, validator results by shell, observed failures, skipped checks, proof ceiling, push/PR state, preserved local work, and one exact executable next command.

## Proof ceiling

This harness proves tracked structure, discoverability, cross-shell parser and contract compatibility, fixture-safe CMD dispatch, noninteractive Git hygiene, local artifact policy, and failure-boundary reporting. It does not prove workstation runtime behavior or operator acceptance.
