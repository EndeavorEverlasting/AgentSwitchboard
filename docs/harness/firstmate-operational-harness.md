# First Mate operational harness

This harness turns the AgentSwitchboard / First Mate / session-backend relationship into a deterministic repository surface.

**Role map:** AgentSwitchboard is the control plane; First Mate is the crew chief; tmux is the current reference session backend; Herdr is an experimental session-backend candidate; supported coding agents are bounded workers.

Android readiness does **not** block productive laptop/WSL crew work. The laptop proof target is the canonical Ubuntu-on-WSL lane; an Android handoff is not a substitute.

## Fast entry

Linux/WSL repository contract:

```bash
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
bash Test-AgentSwitchboard-FirstMate-Harness.sh report
```

Windows-to-WSL physical floor:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 -ExpectedHead <exact-sha>
```

The Windows bridge does **not** run Linux Git inside the Windows linked worktree. It derives the clean committed source repository with Git, passes that Windows path through Microsoft WSL's `WSLENV /p` path translation, creates a WSL-owned standalone clone under the Linux temporary filesystem, detaches that clone at the exact expected SHA, and runs all Linux validators there.

The integration contract also declares `platform_contract.wsl_distribution: Ubuntu`. The bridge therefore invokes `wsl.exe -d Ubuntu ...` instead of inheriting whatever distro happens to be the WSL default. This matters because a service/default distro may not contain Bash even when Ubuntu is installed. The bridge proves `WSL_DISTRO_NAME=Ubuntu` before bootstrap and again inside the standalone clone.

Every WSL subprocess is bounded by `-WslTimeoutSeconds` (default 120 seconds). A timeout is recorded as exit 124 and cannot hold the operator terminal indefinitely. Each physical attempt gets a unique evidence directory so a later run cannot overwrite the failure that motivated the current repair.

If Ubuntu itself cannot execute Bash, an operator can explicitly reuse the already-reviewed repository repair rather than reconstructing WSL setup manually:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 -ExpectedHead <exact-sha> -RepairWslIfNeeded
```

That switch delegates only to `Repair-Technician-WSL-Ubuntu.cmd`. The canonical repair owns same-user UAC, Windows feature activation, Ubuntu registration, WSL 2 selection, first-run initialization, and non-interactive Bash verification. It does not unregister a distro or reboot automatically. Exit 3010 remains a real reboot boundary and the bridge stops rather than claiming runtime readiness.

## Harness components

- `tooling/firstmate/harness/integration-contract.json` — upstream pin, canonical Ubuntu-on-WSL target, local-only delivery posture, and `+yolo` policy.
- `tooling/firstmate/harness/operational/manifest.json` — component inventory, role boundaries, collision rules, proof ceiling.
- `codebase-map.json` — repository structure, entrypoints, commands, known traps.
- `workflow-registry.json` and `workflows/*.json` — task intake, local-only crew execution, validation, failure recovery, handoff.
- `artifact-registry.json` — operator report, route decision, Windows-to-WSL runtime-floor artifacts, and bounded diagnostics.
- `validator-registry.json` — focused, foundation, bridge, shell, and diff gates.
- `Select-FirstMateWorkflow.py` — deterministic direct-vs-crew/backend gate.
- `Build-FirstMateHarnessReport.py` — English operator report generator.
- `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` — Windows-to-Ubuntu-on-WSL proof bridge.
- `Repair-Technician-WSL-Ubuntu.cmd` — existing canonical Windows repair owner; reused, not duplicated, by this lane.
- optional pre-commit/pre-push hooks — never installed implicitly.
- `.ai/skills/firstmate-crew-orchestration/SKILL.md` — scoped repeatable procedure.
- `tests/test_firstmate_operational_harness.py` and `tests/test_firstmate_windows_wsl_bridge.py` — completeness and anti-regression gates.
- `docs/reports/firstmate-operational-harness-status.md` — tracked human snapshot.

## Known traps

1. A linked worktree has a `.git` file rather than necessarily a `.git` directory.
2. A **Windows-created linked worktree is not a portable Linux Git checkout**. Its `.git` file can point at Windows-owned worktree metadata that Linux Git cannot resolve correctly.
3. Do not pass Windows temporary paths through `wslpath` and assume stdout exists.
4. Do not hardcode `/mnt/c`; WSL automount roots are configurable.
5. Use `WSLENV /p` for Win32→WSL path translation and keep WSL stderr separate from stdout.
6. The bridge creates a WSL-owned standalone exact-head clone from committed source state. Dirty files in the Windows source checkout are not copied into that clone.
7. A WSL configuration warning on stderr is diagnostic evidence. It is only a gate failure if the WSL command itself fails.
8. Do not use bare `wsl.exe --exec bash` for the laptop proof. It uses the default WSL distro; bind the contract-owned Ubuntu distro explicitly.
9. Bound every WSL subprocess. A wedged WSL command is a failure artifact, not permission to wait forever.
10. Preserve every physical attempt in a unique evidence directory.
11. First Mate is the crew chief, not the AgentSwitchboard control plane.
12. Herdr is a session-backend candidate, not the project manager; tmux remains the reference backend.
13. Linux support does not prove Android/Termux or native-Windows First Mate behavior.

## Failure handling

Assign failures to one owner: harness contract, Windows-to-WSL bridge, First Mate compatibility, worker/project task, session backend, or external dependency. Preserve successful disjoint work and repair only the failing owner.

For Windows-to-WSL failures preserve:

```text
firstmate-harness-report.md
firstmate-floor.txt
firstmate-route.json
wsl-stderr.log
wsl-bootstrap-stdout.txt
WSL workspace path
canonical WSL distribution
exact AgentSwitchboard SHA
```

The bridge intentionally preserves the WSL clone instead of deleting it after a failure or success; cleanup is a separate explicit operator action and is not part of this harness sprint.

## Route policy

A parallel Linux/WSL route becomes eligible only after the read-only First Mate floor passes:

```bash
python3 tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py \
  --parallel-writers 3 \
  --firstmate-floor pass \
  --platform linux-wsl
```

The only eligible first crew route is `firstmate-local-only` on tmux with `yolo_enabled: false`. No remote-write, merge, deployment, or Herdr authority is implied.

## Runtime proof ladder

1. **contract/CI proof** — tracked harness, standalone-clone bridge, Ubuntu binding, timeout, and repair-delegation structure;
2. **physical Ubuntu-on-WSL floor** — `[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR`, canonical distro/head visibility, First Mate toolchain floor, and `firstmate-local-only` route artifact;
3. **productive laptop crew proof** — a real First Mate primary harness running in tmux, a bounded local-only task issued from the laptop, observable worker/session behavior, completion evidence, and no remote-write or `+yolo` promotion;
4. higher delivery/merge proof only when separately authorized.

A phone/Android transition is not on this laptop proof ladder.

## Validation

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_operational_harness.py
python3 tests/test_firstmate_windows_wsl_bridge.py
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
python3 tests/test_operational_harness.py
git diff --check <base>...HEAD
```

Windows static bridge contract:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 -ExpectedHead <exact-sha> -ContractOnly
```

## Proof ceiling

A green hosted harness proves tracked routing, component completeness, safe shell contracts, canonical Ubuntu binding, bounded WSL subprocess structure, unique evidence naming, report generation, and the Windows-to-WSL standalone-clone bridge structure. Physical-laptop WSL execution remains unproved until the bridge passes there. Live First Mate crew dispatch, Herdr runtime, merge, deployment, Android, and native-Windows First Mate execution remain outside this proof.
