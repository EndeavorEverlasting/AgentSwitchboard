# First Mate operational harness

This harness turns the AgentSwitchboard / First Mate / session-backend relationship into a deterministic repository surface.

**Role map:** AgentSwitchboard is the control plane; First Mate is the crew chief; tmux is the current reference session backend; Herdr is an experimental session-backend candidate; supported coding agents are bounded workers.

Android readiness does **not** block productive laptop/WSL crew work.

## Pick the front door by physical host

### Windows laptop

Contract validation is PowerShell-native and must not depend on Bash or WSL:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode contract
```

The clickable/CMD-equivalent front door is:

```cmd
Test-AgentSwitchboard-FirstMate-Harness.cmd contract
```

The Windows front door also owns report and route modes without crossing into WSL:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode report --stdout
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode route --parallel-writers 3 --firstmate-floor unproved --platform linux-wsl
```

Only `runtime-floor` may cross from Windows into WSL:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode runtime-floor -ExpectedHead <exact-sha>
```

Add `-RepairWslIfNeeded` only when the repository-owned WSL/Ubuntu repair is intended for that physical run.

### Linux / WSL

```bash
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
bash Test-AgentSwitchboard-FirstMate-Harness.sh report
```

## Why Windows has a separate harness front door

A physical laptop run exposed a concrete harness defect: `tests/test_firstmate_integration_contract.py` invoked `bash` through `subprocess.run(...)` while Python was running natively on Windows, and passed a `C:\...` repository path to that Bash process. The resulting nonzero Bash exit happened before the intended WSL runtime floor and therefore did **not** prove First Mate, Ubuntu, or WSL was broken.

The repair makes origin normalization a portable Python owner:

```text
tooling/firstmate/harness/operational/Normalize-FirstMateOrigin.py
```

The Linux probe delegates origin normalization to that owner. The portable Python contract invokes the normalizer with the current Python interpreter, so Windows validation no longer spawns Bash. The PowerShell front door then runs all Windows-safe contracts and the bridge `ContractOnly` gate without crossing into WSL.

**Rule:** never use a bare Bash subprocess from Windows contract validation merely because a Linux runtime exists later in the workflow. A Windows path is not a POSIX path.

## Preserve Python interpreter identity

A later physical Windows run exposed a second portability class. The PowerShell front door had already found and launched `python.exe`, but `tests/test_firstmate_operational_harness.py` then launched its own child Python tools using the literal executable name `python3`. That alias was not present on the Windows machine, so each child process returned exit `9009` even though Python itself was already running correctly.

Portable Python contracts must therefore launch another repository Python script with the interpreter that is already executing the parent process:

```python
subprocess.run([sys.executable, str(tool), ...])
```

Do **not** repair this failure by installing another Python, adding aliases, switching into WSL, or changing the operator shell. When the parent Python process is healthy and only a hardcoded `python3` child returns `9009`, the owner is the harness test/launcher.

## Windows-to-WSL runtime floor

The physical runtime bridge does **not** run Linux Git inside the Windows linked worktree. It derives the clean committed source repository with Git, passes that Windows path through Microsoft WSL's `WSLENV /p` path translation, creates a WSL-owned standalone clone under the Linux temporary filesystem, detaches that clone at the exact expected SHA, and runs all Linux validators there.

The bridge binds to the integration contract's canonical `Ubuntu` distribution, proves `WSL_DISTRO_NAME=Ubuntu` and Bash readiness, bounds WSL subprocesses, and keeps WSL stdout/stderr separate. `/etc/wsl.conf` warnings therefore remain diagnostics instead of corrupting machine-readable output.

## Harness components

- `tooling/firstmate/harness/operational/manifest.json` — component inventory, role boundaries, collision rules, proof ceiling.
- `codebase-map.json` — repository structure, platform entrypoints, commands, known traps.
- `workflow-registry.json` and `workflows/*.json` — task intake, Windows-laptop validation, local-only crew execution, validation, failure recovery, handoff.
- `artifact-registry.json` — operator report, route decision, and Windows-to-WSL runtime-floor artifacts.
- `validator-registry.json` — portable, Windows-native, Linux/WSL shell, foundation, bridge, interpreter-continuity, and diff gates.
- `Normalize-FirstMateOrigin.py` — portable origin-normalization owner shared by Windows contracts and the Linux probe.
- `Select-FirstMateWorkflow.py` — deterministic direct-vs-crew/backend gate.
- `Build-FirstMateHarnessReport.py` — English operator report generator.
- `Test-AgentSwitchboard-FirstMate-Harness.ps1` and `.cmd` — Windows-native operator front doors.
- `Test-AgentSwitchboard-FirstMate-Harness.sh` — Linux/WSL operator front door.
- `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` — physical Windows-to-Ubuntu proof bridge.
- optional pre-commit/pre-push hooks — never installed implicitly.
- `.ai/skills/firstmate-crew-orchestration/SKILL.md` — scoped repeatable procedure.
- `tests/test_firstmate_operational_harness.py`, `tests/test_firstmate_windows_harness_portability.py`, and `tests/test_firstmate_windows_wsl_bridge.py` — completeness and anti-regression gates.
- `docs/reports/firstmate-operational-harness-status.md` — tracked human snapshot.

## Known traps

1. A linked worktree has a `.git` file rather than necessarily a `.git` directory.
2. A **Windows-created linked worktree is not a portable Linux Git checkout**. Its `.git` file can point at Windows-owned worktree metadata that Linux Git cannot resolve correctly.
3. A native Windows Python process must not invoke bare Bash with a Windows repository path for a platform-neutral contract.
4. A Windows Python installation may expose `python.exe` without a `python3.exe` alias. Child Python tools in portable tests must use `sys.executable`; exit `9009` from hardcoded `python3` is an interpreter-routing defect.
5. Do not pass Windows temporary paths through `wslpath` and assume stdout exists.
6. Do not hardcode `/mnt/c`; WSL automount roots are configurable.
7. Use `WSLENV /p` for Win32→WSL path translation and keep WSL stderr separate from stdout.
8. The bridge creates a WSL-owned standalone exact-head clone from committed source state. Dirty files in the Windows source checkout are not copied into that clone.
9. A WSL configuration warning on stderr is diagnostic evidence. It is only a gate failure if the WSL command itself fails.
10. First Mate is the crew chief, not the AgentSwitchboard control plane.
11. Herdr is a session-backend candidate, not the project manager; tmux remains the reference backend.
12. Linux support does not prove Android/Termux or native-Windows First Mate runtime behavior.

## Failure handling

Assign failures to one owner: Windows-native harness, Windows-to-WSL bridge, First Mate compatibility, worker/project task, session backend, or external dependency. Preserve successful disjoint work and repair only the failing owner.

If Windows contract mode fails before `runtime-floor`, do **not** diagnose WSL from that failure. Preserve the native command, exit code, and bounded error. If the parent Python interpreter is already running and a child `python3` launch returns `9009`, repair the portable child launcher to use `sys.executable`.

If runtime-floor fails after crossing into WSL, preserve:

```text
firstmate-harness-report.md
firstmate-floor.txt
firstmate-route.json
wsl-stderr.log
wsl-bootstrap-stdout.txt
WSL workspace path
exact AgentSwitchboard SHA
```

The bridge intentionally preserves the WSL clone instead of deleting it after a failure or success; cleanup is a separate explicit operator action.

## Route policy

A parallel Linux/WSL route becomes eligible only after the read-only First Mate floor passes. The only eligible first crew route is `firstmate-local-only` on tmux with `yolo_enabled: false`. No remote-write, merge, deployment, or Herdr authority is implied.

## Validation

Windows:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode contract
python tests/test_operational_harness.py
git diff --check <base>...HEAD
```

Linux/WSL:

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_operational_harness.py
python3 tests/test_firstmate_windows_harness_portability.py
python3 tests/test_firstmate_windows_wsl_bridge.py
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
python3 tests/test_operational_harness.py
git diff --check <base>...HEAD
```

## Proof ceiling

A green hosted harness proves tracked routing, component completeness, portable origin normalization, Python interpreter continuity, platform-correct contract entrypoints, report generation, and the Windows-to-WSL standalone-clone bridge structure. Physical-laptop WSL execution remains unproved until `runtime-floor` passes there. Live First Mate crew dispatch and useful task completion are higher proof gates and are not claimed by contract validation.
