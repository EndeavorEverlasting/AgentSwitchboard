# FirstMate interoperability floor (Linux/WSL)

## Scope

This integration establishes the current safe interoperability boundary between AgentSwitchboard and [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate). It does not vendor, modify, or fork FirstMate. It records audited upstream behavior and provides a read-only compatibility probe for the Linux/WSL lane.

**Audited upstream commit:** `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` on FirstMate `main` (refreshed 2026-09-13 for `FM-REFRESH-06`).

Historical PR #96 audited `833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409`. That SHA is provenance only. The interop probe and contract tests reject treating it as the current pin.

FirstMate's upstream README declares macOS and Linux, describes tmux as the reference backend, and lists Claude Code, Grok, Pi / `pi-signed`, Oh My Pi (`omp`), Codex, OpenCode, and Cursor Agent CLI as verified primary harnesses. WSL/Ubuntu is therefore an AgentSwitchboard integration inference from the upstream Linux contract; this sprint does **not** claim that upstream explicitly certifies WSL or native Windows.

Architecture authority: [`docs/architecture/asb-firstmate-runtime-boundary.md`](../architecture/asb-firstmate-runtime-boundary.md). Convergence authority: [`docs/harness/firstmate-asb-convergence.md`](firstmate-asb-convergence.md) plus `tooling/firstmate/harness/convergence-contract.json`.

Windows hosts remain **bridge only**. The Windows operational harness, scoped skill, and bridge regressions belong to successor lane `FM-BRIDGE-10` and are intentionally absent from this foundation.

## Why the first smoke is `local-only`

FirstMate's project-management contract defines these delivery postures:

- `no-mistakes` — validation pipeline before a PR;
- `direct-PR` — push and PR without the no-mistakes pipeline;
- `local-only` — no required remote or PR and no no-mistakes initialization;
- `no-mistakes-prod-only` — conditional policy, and the default for newly added remote-backed projects when the captain does not specify a posture.

For the first AgentSwitchboard interoperability proof, use `local-only`. That intentionally withholds remote-write authority while we prove repository discovery, toolchain readiness, the FirstMate operating contract, and task isolation boundaries.

The autonomy posture is also machine-readable: `tooling/firstmate/harness/integration-contract.json` requires `first_safe_sprint.yolo_enabled: false`. Documentation or model preference cannot silently enable `+yolo`.

## Run the read-only probe

Run this from a Linux/WSL AgentSwitchboard checkout containing this integration:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh
```

If the FirstMate clone is not in one of the probe's conservative default locations, point to the existing clone without moving or modifying it:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh --firstmate "$HOME/path/to/firstmate"
```

The probe checks only local state plus `gh auth status`. It requires:

1. Linux/WSL userland;
2. `git`, `gh`, `tmux`, and `python3`;
3. one upstream-supported primary harness: `claude`, `grok`, `pi`, `pi-signed`, `omp`, `codex`, `opencode`, or `cursor-agent`;
4. a clean FirstMate Git worktree whose normalized `origin` resolves to `kunchenguid/firstmate`;
5. exact FirstMate HEAD `b182d0f908b78d08c7ccb8dce3775bdca8c5d657`;
6. integration-contract SHA matching `tooling/firstmate/harness/upstream-pin.json`;
7. a valid non-empty list of audited upstream contract paths;
8. `first_safe_sprint.project_delivery_mode == local-only` and `first_safe_sprint.yolo_enabled == false`; and
9. an authenticated GitHub CLI session.

The origin check accepts equivalent GitHub transport forms, including HTTPS, authenticated HTTPS, `git://`, SCP-style SSH, and `ssh://` after normalization. Linked Git worktrees are valid; `.git` is not required to be a directory. Contract parsing is fail-closed: malformed or traversal-bearing `required_upstream_paths`, a bad upstream SHA, pin mismatch, or a non-disabled `+yolo` posture stops the probe before a pass can be emitted.

It does **not** install dependencies, change credentials, alter either repository, dispatch a FirstMate task, push a branch, open a PR, or merge anything.

## Evidence sources

Repository-owned machine-readable evidence:

- `tooling/firstmate/harness/integration-contract.json`
- `tooling/firstmate/harness/upstream-pin.json`
- `tooling/firstmate/harness/upstream-verification.json`
- `tooling/firstmate/harness/convergence-contract.json`

Focused deterministic contract tests:

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_asb_convergence_contract.py
```

Shell surface syntax check:

```bash
bash -n tooling/firstmate/Test-FirstMateInterop.sh
```

## Proof ceiling

Passing the offline checks proves that AgentSwitchboard tracks a bounded FirstMate integration contract with an exact current upstream evidence pin, explicit `+yolo` disablement, local-only first posture, and a non-mutating Linux/WSL probe. Passing the probe additionally proves that one operator environment has the audited FirstMate clone and required local toolchain.

Neither level proves:

- physical WSL execution beyond the Linux userland probe;
- live FirstMate crew dispatch or worker supervision;
- GitHub authentication inside a specific operator WSL distro beyond `gh auth status`;
- Windows→WSL operational bridge behavior (`FM-BRIDGE-10`);
- native Windows FirstMate runtime;
- Herdr runtime;
- provider/model behavior.

Herdr promotion is a separate gate and is not a dependency for this foundation.
