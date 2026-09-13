# First Mate interoperability floor

## Scope

This integration establishes the first safe interoperability boundary between AgentSwitchboard and [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate). It does not vendor, modify, or fork First Mate. It records audited upstream behavior and provides a read-only compatibility probe for the Linux/WSL lane.

**Audited upstream commit:** `833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409` on First Mate `main`.

First Mate's upstream README declares macOS and Linux, describes tmux as the reference backend, and lists Claude Code, Grok, Pi / `pi-signed`, Codex, and OpenCode as verified primary harnesses. WSL is therefore an AgentSwitchboard integration inference from the upstream Linux contract; this sprint does **not** claim that upstream explicitly certifies WSL or native Windows.

The broader operational routing surface is documented in `docs/harness/firstmate-operational-harness.md`. That harness makes the ownership split explicit: AgentSwitchboard is the control plane, First Mate is the crew chief, tmux is the reference session backend, Herdr is experimental, and coding agents are workers.

## Why the first smoke is `local-only`

First Mate's project-management contract defines these delivery postures:

- `no-mistakes` — validation pipeline before a PR;
- `direct-PR` — push and PR without the no-mistakes pipeline;
- `local-only` — no required remote or PR and no no-mistakes initialization;
- `no-mistakes-prod-only` — conditional policy, and the default for newly added remote-backed projects when the captain does not specify a posture.

For the first AgentSwitchboard interoperability proof, use `local-only`. That intentionally withholds remote-write authority while we prove repository discovery, toolchain readiness, the First Mate operating contract, and task isolation boundaries. A later sprint can promote the standing posture after a real local-only task has produced evidence.

The autonomy posture is also machine-readable: `tooling/firstmate/harness/integration-contract.json` requires `first_safe_sprint.yolo_enabled: false`. The deterministic route selector refuses `firstmate-local-only` unless that canonical field is present and false. Documentation or model preference cannot silently enable `+yolo`.

## Run the read-only probe

Run this from a Linux/WSL AgentSwitchboard checkout containing this integration branch:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh
```

If the First Mate clone is not in one of the probe's conservative default locations, point to the existing clone without moving or modifying it:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh --firstmate "$HOME/path/to/firstmate"
```

The probe checks only local state plus `gh auth status`. It requires:

1. Linux/WSL userland;
2. `git`, `gh`, `tmux`, and `python3`;
3. one upstream-supported primary harness: `claude`, `grok`, `pi`, `pi-signed`, `codex`, or `opencode`;
4. a clean First Mate Git worktree whose normalized `origin` resolves to `kunchenguid/firstmate`;
5. exact First Mate HEAD `833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409`;
6. a valid non-empty list of audited upstream contract paths;
7. `first_safe_sprint.project_delivery_mode == local-only` and `first_safe_sprint.yolo_enabled == false`; and
8. an authenticated GitHub CLI session.

The origin check accepts equivalent GitHub transport forms, including HTTPS, authenticated HTTPS, `git://`, SCP-style SSH, and `ssh://` after normalization. Linked Git worktrees are valid; `.git` is not required to be a directory. Contract parsing is fail-closed: malformed or traversal-bearing `required_upstream_paths`, a bad upstream SHA, or a non-disabled `+yolo` posture stops the probe before a pass can be emitted.

It does **not** install dependencies, change credentials, alter either repository, dispatch a First Mate task, push a branch, open a PR, or merge anything.

## First live follow-up after the probe passes

The next sprint should exercise one small AgentSwitchboard task through First Mate with the project explicitly registered in `local-only` mode and `+yolo` disabled. Choose a task that can be proved with repository-local validation and does not touch secrets, protected runtimes, deployment targets, or shared governance files already owned by another PR.

Record at minimum:

- First Mate and AgentSwitchboard commit SHAs;
- selected primary harness and tmux version;
- project delivery mode and autonomy posture;
- task brief and owned/forbidden paths;
- isolated worktree path or identifier;
- validator output and produced artifact;
- whether the task landed locally, was rejected, or remained unmerged; and
- exact proof ceiling.

Only after that local-only runtime evidence exists should a sprint consider `direct-PR` or another remote-writing delivery posture. Herdr promotion is a separate gate and is not a dependency for this laptop/WSL smoke.

## Evidence sources

The repository-owned machine-readable evidence lives at:

- `tooling/firstmate/harness/integration-contract.json`
- `tooling/firstmate/harness/upstream-verification.json`
- `tooling/firstmate/harness/operational/manifest.json`

The deterministic contract tests are:

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_operational_harness.py
python3 tests/test_firstmate_windows_wsl_bridge.py
```

The shell surface syntax checks are:

```bash
bash -n tooling/firstmate/Test-FirstMateInterop.sh
bash -n Test-AgentSwitchboard-FirstMate-Harness.sh
```

## Proof ceiling

Passing the offline checks proves that AgentSwitchboard tracks a bounded First Mate integration contract with an exact upstream evidence pin, deterministic crew routing, explicit `+yolo` disablement, and a non-mutating Linux/WSL probe. Passing the probe additionally proves that one operator environment has the audited First Mate clone and required local toolchain. Neither level proves live First Mate dispatch, worker supervision, treehouse worktree behavior, task completion, PR delivery, merge behavior, Herdr runtime, native Windows support, or Android/Termux support.
