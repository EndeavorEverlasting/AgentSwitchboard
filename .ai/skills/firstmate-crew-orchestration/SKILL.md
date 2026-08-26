---
id: firstmate-crew-orchestration
version: 1.3.0
status: experimental
---

# First Mate crew orchestration

## Trigger

Use when AgentSwitchboard must decide whether a task should stay with one direct repository writer or be decomposed into parallel crew work through First Mate, especially when laptop/WSL work should continue independently of Android profile or Herdr migration work. Also use when a Windows operator must cross into the Linux/WSL First Mate lane and path conversion, WSL diagnostics, exact-head continuity, delivery posture, autonomy posture, or cross-OS Git metadata could make the handoff ambiguous.

## Inputs

- repository, branch/worktree, desired outcome, acceptance criteria;
- number of concurrent writers actually needed;
- target platform (`linux-wsl`, `windows`, `android`, or other);
- First Mate read-only floor state (`pass`, `unproved`, or `fail`);
- canonical `first_safe_sprint` contract, including `project_delivery_mode` and `yolo_enabled`;
- exact AgentSwitchboard head for any Windows-to-WSL runtime proof;
- owned and forbidden paths for every worker;
- requested session backend, if any;
- required validators and evidence artifacts.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `HARNESS.md`, `tooling/firstmate/harness/integration-contract.json`, and `tooling/firstmate/harness/operational/manifest.json`.
2. Preserve active writers. Do not absorb the Android/Herdr migration lane or unrelated PR ownership.
3. Run `Select-FirstMateWorkflow.py`; do not replace its deterministic compatibility gates with model preference.
4. Keep one-writer work on direct AgentSwitchboard execution.
5. For parallel Linux/WSL work, require the read-only First Mate floor before routing to `firstmate-local-only`.
6. Before selecting `firstmate-local-only`, require `first_safe_sprint.project_delivery_mode: local-only` and `first_safe_sprint.yolo_enabled: false`.
7. When Windows launches the WSL lane, use `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1`. Do not manually feed paths through `wslpath`, do not hardcode `/mnt/c`, and do not use a Windows-created linked worktree as the Linux Git checkout.
8. The bridge must derive the committed source repository through Git, pass that Windows path with `WSLENV /p`, create a WSL-owned standalone clone on the Linux filesystem, detach it at the exact expected SHA, and prove that SHA before running any owning validator.
9. Capture WSL stdout and stderr separately. Preserve `wsl-stderr.log`, bootstrap stdout, the WSL clone path, and the exact head. `/etc/wsl.conf` warnings are diagnostics, not machine-readable values.
10. Keep tmux as the reference session backend. Herdr remains blocked while the operational manifest has `herdr_selection_enabled: false`.
11. If First Mate becomes ready, assign disjoint branches/worktrees, explicit owned/forbidden paths, validators, and one convergence owner.
12. Run focused validators before commit. Preserve successful disjoint worker evidence when one lane fails.
13. Generate the operator report and route artifact before handoff.
14. Never promote static harness success into live crew, Herdr, PR, merge, deployment, or target-runtime proof.

## Outputs

- deterministic route decision including delivery mode and `yolo_enabled` state;
- Windows-to-WSL runtime-floor evidence when that boundary is exercised;
- WSL-owned standalone clone identity and exact-head receipt;
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
- no implicit or inferred `+yolo` enablement;
- no native-Windows First Mate compatibility claim;
- no Android/Termux compatibility inference from Linux support;
- no concurrent writes to the same branch/worktree;
- no combined parsing of WSL stderr and machine-readable stdout;
- no `wslpath` dependency or hardcoded `/mnt/c` path transport;
- no Linux Git execution inside a Windows-created linked worktree;
- no credentials, device codes, tokens, private keys, or unbounded transcripts in evidence;
- no merge, deployment, or live-target authority inferred from this skill.

## Stop and escalate

Stop when the next action requires governance mutation, product behavior outside the assigned worker scope, credentials, protected runtime access, a branch owned by another writer, or a runtime promotion gate not proved by its owning lane. For Windows-to-WSL failures, preserve `wsl-stderr.log`, `wsl-bootstrap-stdout.txt`, the WSL workspace path, the exact head, and the failing stage before repair.
