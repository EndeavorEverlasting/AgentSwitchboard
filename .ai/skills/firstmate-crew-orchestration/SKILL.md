---
id: firstmate-crew-orchestration
version: 1.1.0
status: experimental
---

# First Mate crew orchestration

## Trigger

Use when AgentSwitchboard must decide whether a task should stay with one direct repository writer or be decomposed into parallel crew work through First Mate, especially when laptop/WSL work should continue independently of Android profile or Herdr migration work. Also use when a Windows operator must cross into the Linux/WSL First Mate lane and path conversion, WSL diagnostics, or exact-head continuity could make the handoff ambiguous.

## Inputs

- repository, branch/worktree, desired outcome, acceptance criteria;
- number of concurrent writers actually needed;
- target platform (`linux-wsl`, `windows`, `android`, or other);
- First Mate read-only floor state (`pass`, `unproved`, or `fail`);
- exact AgentSwitchboard head for any Windows-to-WSL runtime proof;
- owned and forbidden paths for every worker;
- requested session backend, if any;
- required validators and evidence artifacts.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `HARNESS.md`, and `tooling/firstmate/harness/operational/manifest.json`.
2. Preserve active writers. Do not absorb the Android/Herdr migration lane or unrelated PR ownership.
3. Run `Select-FirstMateWorkflow.py`; do not replace its deterministic compatibility gates with model preference.
4. Keep one-writer work on direct AgentSwitchboard execution.
5. For parallel Linux/WSL work, require the read-only First Mate floor before routing to `firstmate-local-only`.
6. When Windows launches the WSL lane, use `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1`. Do not manually feed the isolated Windows worktree through `wslpath`.
7. The Windows bridge must run `wsl.exe` with the exact Windows worktree as `ProcessStartInfo.WorkingDirectory`, capture stdout/stderr separately, and prove WSL resolves the same exact Git HEAD before parsing any report or route data.
8. Preserve WSL stderr as bounded diagnostics. A `/etc/wsl.conf` warning is not machine-readable output and must never be concatenated into a path or JSON value.
9. Keep tmux as the reference session backend. Herdr remains blocked while the operational manifest has `herdr_selection_enabled: false`.
10. If First Mate becomes ready, assign disjoint branches/worktrees, explicit owned/forbidden paths, validators, and one convergence owner.
11. Run focused validators before commit. Preserve successful disjoint worker evidence when one lane fails.
12. Generate the operator report and route artifact before handoff.
13. Never promote static harness success into live crew, Herdr, PR, merge, deployment, or target-runtime proof.

## Outputs

- deterministic route decision;
- Windows-to-WSL runtime-floor evidence when that boundary is exercised;
- crew/worktree boundary map when parallel work is selected;
- validator receipts;
- operator report path;
- exact next command and named blocker when execution cannot advance.

## Deterministic validation

- `python3 tests/test_firstmate_integration_contract.py`
- `python3 tests/test_firstmate_operational_harness.py`
- `python3 tests/test_firstmate_windows_wsl_bridge.py`
- `bash Test-AgentSwitchboard-FirstMate-Harness.sh contract`
- `pwsh -NoLogo -NoProfile -File Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 -ExpectedHead <exact-sha> -ContractOnly`
- `python3 tests/test_operational_harness.py`
- `git diff --check <base>...HEAD`

## Forbidden scope

- no edits to `AGENTS.md` or governance policy in this harness lane;
- no First Mate upstream mutation or dependency installation;
- no automatic Herdr promotion;
- no native-Windows First Mate compatibility claim;
- no Android/Termux compatibility inference from Linux support;
- no concurrent writes to the same branch/worktree;
- no combined parsing of WSL stderr and machine-readable stdout;
- no `wslpath` dependency for the Windows exact-head worktree transport;
- no credentials, device codes, tokens, private keys, or unbounded transcripts in evidence;
- no merge, deployment, or live-target authority inferred from this skill.

## Stop and escalate

Stop when the next action requires governance mutation, product behavior outside the assigned worker scope, credentials, protected runtime access, a branch owned by another writer, or a runtime promotion gate not proved by its owning lane. For Windows-to-WSL failures, preserve `wsl-stderr.log`, the exact head, and the failing stage before repair. Preserve the exact artifact and route the dependency to that owner.
