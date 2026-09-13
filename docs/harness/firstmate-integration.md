# FirstMate interoperability floor (Linux/WSL)

## Scope

This integration establishes the safe interoperability boundary between AgentSwitchboard and [`kunchenguid/firstmate`](https://github.com/kunchenguid/firstmate). It does not vendor, modify, or fork FirstMate.

**Audited upstream commit:** `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` on FirstMate `main`.

Historical PR #96 audited `833a9a25bcf2ae522d6f93dbbd9911a6d8e7c409`. That SHA is provenance only. The interop probe and contract tests reject treating it as the current pin.

FirstMate's upstream README declares macOS and Linux, describes tmux as the reference backend, and lists Claude Code, Grok, Pi / `pi-signed`, Oh My Pi (`omp`), Codex, OpenCode, and Cursor Agent CLI as verified primary harnesses. WSL/Ubuntu remains an AgentSwitchboard integration inference from that Linux contract; AgentSwitchboard does **not** claim upstream explicitly certifies WSL or native Windows.

Architecture authority: [`docs/architecture/asb-firstmate-runtime-boundary.md`](../architecture/asb-firstmate-runtime-boundary.md). Convergence authority: [`docs/harness/firstmate-asb-convergence.md`](firstmate-asb-convergence.md) plus `tooling/firstmate/harness/convergence-contract.json`.

Windows hosts remain **bridge only**. The tracked bridge and operational proof surfaces are documented in [`firstmate-operational-harness.md`](firstmate-operational-harness.md). Physical Admin Box execution follows [`firstmate-wsl-physical-floor-runbook.md`](firstmate-wsl-physical-floor-runbook.md) (`FM-WSL-12`). Those surfaces validate/reach the WSL/Ubuntu substrate; FirstMate itself remains the live crew runtime.

## Why the first smoke is `local-only`

FirstMate's project-management contract defines delivery postures including `local-only`, which does not require remote/PR delivery.

For the first AgentSwitchboard interoperability proof, use `local-only`. That intentionally withholds remote-write authority while repository discovery, toolchain readiness, and the audited FirstMate contract floor are established.

The autonomy posture is also machine-readable: `tooling/firstmate/harness/integration-contract.json` requires `first_safe_sprint.yolo_enabled: false`. Documentation or model preference cannot silently enable `+yolo`.

## Linux/WSL read-only probe

Run from a Linux/WSL AgentSwitchboard checkout:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh
```

If the FirstMate clone is not in one of the probe's conservative default locations:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh --firstmate "$HOME/path/to/firstmate"
```

The probe requires:

1. Linux/WSL userland;
2. `git`, `gh`, `tmux`, and `python3`;
3. one supported primary harness: `claude`, `grok`, `pi`, `pi-signed`, `omp`, `codex`, `opencode`, or `cursor-agent`;
4. a clean FirstMate Git worktree whose normalized `origin` resolves to `kunchenguid/firstmate`;
5. exact FirstMate HEAD `b182d0f908b78d08c7ccb8dce3775bdca8c5d657`;
6. integration-contract SHA matching `tooling/firstmate/harness/upstream-pin.json`;
7. valid audited upstream contract paths;
8. `first_safe_sprint.project_delivery_mode == local-only` and `first_safe_sprint.yolo_enabled == false`; and
9. an authenticated GitHub CLI session.

It does **not** install dependencies, change credentials, alter either repository, dispatch a FirstMate task, push a branch, open a PR, or merge anything.

## Windows bridge host

`FM-BRIDGE-10` adds a Windows-native **contract front door**, not a native FirstMate runtime.

Contract-only validation:

```powershell
$head = (git rev-parse HEAD).Trim()
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode contract `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

Physical WSL floor:

```powershell
$head = (git rev-parse HEAD).Trim()
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode physical-floor `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

The physical path checks Ubuntu prerequisites first, then delegates to a bounded Windows→WSL bridge that creates a WSL-owned standalone exact-head AgentSwitchboard clone and runs this read-only interoperability probe inside that clone.

The bridge preserves the historical field lessons from PRs #98/#99/#100/#101: explicit Ubuntu rather than default WSL selection, bounded WSL subprocesses, CRLF→LF command transport, empty native stream safety, `WSLENV /p` path transport, standalone Linux-owned Git checkout, Windows current-interpreter continuity, prerequisite gating, and unique local evidence roots.

AgentSwitchboard does not revive the historical FirstMate crew-routing skill or route selector. Once the WSL substrate is proven, live dispatch and lifecycle belong to FirstMate.

## Evidence sources

Tracked machine-readable owners:

- `tooling/firstmate/harness/integration-contract.json`
- `tooling/firstmate/harness/upstream-pin.json`
- `tooling/firstmate/harness/upstream-verification.json`
- `tooling/firstmate/harness/convergence-contract.json`
- `tooling/firstmate/harness/operational/manifest.json`
- `tooling/firstmate/harness/operational/artifact-registry.json`
- `tooling/firstmate/harness/operational/validator-registry.json`
- `tooling/firstmate/harness/operational/codebase-map.json`

Focused deterministic contract tests:

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_asb_convergence_contract.py
python3 tests/test_firstmate_operational_harness.py
python3 tests/test_firstmate_windows_harness_portability.py
python3 tests/test_firstmate_windows_wsl_bridge.py
python3 tests/test_firstmate_windows_wsl_prerequisite_gate.py
```

## Proof ceiling

Passing repository/hosted checks proves the current pin and Linux/WSL compatibility contract plus the tracked Windows bridge invariants. It does **not** prove a physical Windows→Ubuntu/WSL run or productive FirstMate crew execution.

A successful physical-floor run additionally proves that one authorized Windows host can pass the prerequisite gate, create/use the WSL-owned exact-head AgentSwitchboard clone, and reach the read-only FirstMate compatibility floor in explicit Ubuntu.

Neither repository CI nor that physical bridge floor proves:

- live FirstMate crew dispatch or worker supervision;
- native Windows FirstMate runtime;
- provider/model behavior;
- project PR/merge/deployment delivery;
- Herdr runtime.

The later `FM-CREW-13` local-only pilot owns live crew proof. Herdr promotion is a separate gate.
