# First Mate operational harness

This harness turns the AgentSwitchboard / First Mate / session-backend relationship into a deterministic repository surface.

**Role map:** AgentSwitchboard is the control plane; First Mate is the crew chief; tmux is the current reference session backend; Herdr is an experimental session-backend candidate; Codex, Pi, OpenCode, Claude Code, and other supported coding agents are bounded workers.

The important operational consequence is that **Android readiness does not block productive laptop/WSL crew work**.

## Fast entry

From the AgentSwitchboard repository root on Linux/WSL:

```bash
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
bash Test-AgentSwitchboard-FirstMate-Harness.sh report
```

From Windows, do not manually convert the exact-head worktree with `wslpath`. Use the tracked bridge:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 -ExpectedHead <exact-sha>
```

The bridge starts `wsl.exe` with the exact Windows worktree as its process working directory, proves WSL sees the same Git HEAD, and keeps WSL stderr separate from stdout. This prevents `/etc/wsl.conf` warnings or other WSL diagnostics from corrupting machine-readable paths or JSON. It writes bounded evidence outside the worktree and does not close the terminal.

Choose the route without relying on model judgment:

```bash
python3 tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py \
  --parallel-writers 3 \
  --firstmate-floor unproved \
  --platform linux-wsl
```

If the result is `blocked:firstmate-readiness`, run the exact read-only floor:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh --firstmate "$HOME/path/to/firstmate"
```

After that floor actually passes, rerun the selector with `--firstmate-floor pass`. The eligible crew route is deliberately `firstmate-local-only` on **tmux**. It does not grant remote writes, PR creation, merge, deployment, or Herdr promotion.

## Harness components

- `tooling/firstmate/harness/operational/manifest.json` — component inventory, role boundaries, collision rules, proof ceiling.
- `codebase-map.json` — repository structure, entrypoints, commands, known traps.
- `workflow-registry.json` and `workflows/*.json` — task intake, local-only crew execution, pre-commit validation, failure recovery, handoff.
- `artifact-registry.json` — operator report, route decision, and Windows-to-WSL runtime-floor artifacts.
- `validator-registry.json` — focused, foundation, bridge, shell, and diff gates.
- `Select-FirstMateWorkflow.py` — deterministic direct-vs-crew/backend gate.
- `Build-FirstMateHarnessReport.py` — English operator report generator; `--stdout` supports cross-shell transport without a path conversion.
- `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` — tracked Windows-to-WSL proof bridge.
- `hooks/Invoke-FirstMateHarnessPreCommit.sh` and `Invoke-FirstMateHarnessPrePush.sh` — optional hooks; never installed implicitly.
- `.ai/skills/firstmate-crew-orchestration/SKILL.md` — scoped repeatable procedure.
- `tests/test_firstmate_operational_harness.py` and `tests/test_firstmate_windows_wsl_bridge.py` — completeness and anti-regression gates.
- `docs/reports/firstmate-operational-harness-status.md` — tracked human snapshot.

## Known traps

1. A First Mate linked worktree has a `.git` **file**, not necessarily a `.git` directory. The compatibility probe uses Git itself to verify worktree identity.
2. Equivalent GitHub remotes may use HTTPS, authenticated HTTPS, `git://`, SCP-style SSH, or `ssh://`. Normalize transport before repository-identity comparison.
3. First Mate is not AgentSwitchboard. First Mate supervises a crew; AgentSwitchboard owns machine/provider/workflow policy, validation, evidence, and escalation.
4. Herdr is not First Mate. Herdr is a session backend candidate. Do not make Herdr own task decomposition or repository policy.
5. tmux failure does not authorize a Herdr promotion. Repair the failing lane or satisfy the Herdr promotion gates.
6. Linux support does not prove Android/Termux or native-Windows behavior.
7. Do not wait for the Android lane before doing safe laptop/WSL work.
8. **Do not pass a Windows temporary path to `wslpath` and then call `.Trim()` on assumed output.** WSL can emit configuration warnings on stderr, and Windows short-path/backslash transport can fail before `wslpath` returns anything.
9. For Windows-to-WSL proof, set the exact Windows worktree as `wsl.exe`'s process working directory, execute only repository-relative Linux commands, capture stdout and stderr separately, and prove the same exact Git HEAD is visible inside WSL before continuing.

## Failure handling

A failure is assigned to one of six owners: harness contract, Windows-to-WSL bridge, First Mate compatibility, worker/project task, session backend, or external dependency. Preserve successful disjoint branches/worktrees. Repair only the failing owner and rerun its focused gate. Repeated no-progress, governance changes, credentials, or protected runtime access are escalation boundaries.

For the Windows bridge, always preserve `wsl-stderr.log`. A warning such as an unknown `/etc/wsl.conf` key is diagnostic evidence. It is not itself a failure if WSL still executes successfully and resolves the exact worktree HEAD. A nonzero WSL process, wrong visible HEAD, or failed First Mate floor is a real gate failure.

## Artifacts and handoff

The report generator writes by default below the operating-system temporary directory:

```text
<temp>/agentswitchboard/firstmate-harness/firstmate-harness-report.md
```

The Windows bridge creates a bounded evidence directory containing:

```text
firstmate-harness-report.md
firstmate-floor.txt
firstmate-route.json
wsl-stderr.log
```

The selector can also write a machine-readable route artifact with `--output`. None of these artifacts may contain credentials or unbounded model transcripts.

A handoff must carry repository, branch, exact head, worker/worktree ownership, validators actually run, artifact paths, runtime backend actually observed, unresolved blockers, proof ceiling, and one exact next command.

## Validation

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_operational_harness.py
python3 tests/test_firstmate_windows_wsl_bridge.py
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
python3 tests/test_operational_harness.py
git diff --check <base>...HEAD
```

On PowerShell 7:

```powershell
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 -ExpectedHead <exact-sha> -ContractOnly
```

## Proof ceiling

A green harness proves tracked routing, component completeness, safe shell contracts, report generation, Windows-to-WSL bridge structure, and static compatibility rules. It does **not** prove physical-laptop WSL execution until that bridge runs there, and it does not prove live First Mate crew dispatch, worktree supervision, worker success, Herdr runtime, PR delivery, merge, deployment, Android, or native-Windows First Mate behavior.
