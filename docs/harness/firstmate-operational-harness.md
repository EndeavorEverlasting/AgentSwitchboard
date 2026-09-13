# FirstMate Windows → WSL operational bridge

## Status

`FM-BRIDGE-10` establishes the tracked AgentSwitchboard bridge contract for reaching the audited FirstMate Linux runtime from a Windows host.

The bridge is **contract-integrated but runtime-unproved** until an authorized Windows Admin Box executes the physical-floor entrypoint successfully.

Architecture authority: [`docs/architecture/asb-firstmate-runtime-boundary.md`](../architecture/asb-firstmate-runtime-boundary.md).

Current audited FirstMate pin: `b182d0f908b78d08c7ccb8dce3775bdca8c5d657`.

## Ownership boundary

AgentSwitchboard owns:

- Windows/WSL substrate readiness;
- exact AgentSwitchboard source/head verification;
- explicit Ubuntu selection;
- Windows → WSL transport safety;
- prerequisite observation;
- bounded local evidence;
- bridge validation and escalation.

FirstMate owns, after the bridge floor:

- live crew dispatch;
- harness/model/effort/runtime choices;
- worktree and worker lifecycle;
- supervision/wake/recovery;
- live task completion and delivery.

`FM-BRIDGE-10` intentionally does **not** restore the historical AgentSwitchboard `firstmate-crew-orchestration` skill or the stale `Select-FirstMateWorkflow.py` runtime selector. There is no FirstMate-specific AgentSwitchboard skill, capability, or trigger registered by this bridge. The bridge proves the substrate and hands execution authority to FirstMate.

## Canonical entrypoints

Windows contract validation:

```powershell
$head = (git rev-parse HEAD).Trim()
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode contract `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

Windows physical WSL floor:

```powershell
$head = (git rev-parse HEAD).Trim()
pwsh -NoLogo -NoProfile -File .\Test-AgentSwitchboard-FirstMate-Harness.ps1 `
  -Mode physical-floor `
  -ExpectedHead $head `
  -WslDistribution Ubuntu
```

The physical floor delegates in order:

1. `Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1` — observes Ubuntu prerequisites and GitHub CLI authentication without installing or logging in;
2. `Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1` — creates a WSL-owned standalone clone at the exact AgentSwitchboard head and runs the tracked bridge contract;
3. `tooling/firstmate/Test-FirstMateInterop.sh` — performs the read-only FirstMate repository/toolchain compatibility probe.

Linux/WSL contract-only validation is also available through:

```bash
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
```

The lower read-only probe remains:

```bash
bash tooling/firstmate/Test-FirstMateInterop.sh
```

## Preserved Windows → WSL regression contracts

The bridge rebuilds the durable lessons from historical PRs #98, #99, #100, and #101 on the current mainline foundation instead of merging that stale stack.

### Explicit Ubuntu

Every bridge process selects the contract-defined `Ubuntu` distribution. No bridge success may depend on the operator's current default WSL distribution.

### Bounded WSL subprocesses

The lower bridge applies a finite timeout to every `wsl.exe` process. Timeout is exit `124` and is failure evidence, not readiness.

### CRLF-safe command transport

PowerShell-originated commands are normalized from CRLF/CR to LF immediately before `bash -lc` transport.

### Empty native streams

PowerShell helpers accept null and empty stdout/stderr. An empty diagnostic stream must not create a parameter-binding failure.

### WSLENV path transport

Reviewed Windows path variables cross the boundary through `WSLENV` `/p` translation. The bridge does not execute `wslpath`.

### Standalone Linux-owned exact-head clone

The bridge never asks Linux Git to operate on a Windows-created linked-worktree `.git` indirection. It resolves the committed Windows source repository, translates that source path through `WSLENV /p`, creates a standalone clone inside WSL, detaches it at the exact AgentSwitchboard SHA, and verifies the SHA before running validators.

### Interpreter continuity

The Windows contract front door resolves the active `python.exe`/`python` command and invokes repository Python tests through that exact interpreter. It does not spawn literal `python3` from Windows.

### Prerequisite gate

Before the physical bridge runs, the wrapper checks inside explicit Ubuntu for:

- `git`;
- `gh`;
- `tmux`;
- `python3`;
- `gh auth status --hostname github.com`.

A missing requirement produces a machine-readable `NEXT_ACTION`. The harness does not execute package installation or GitHub login on the operator's behalf.

## Local evidence

Each physical attempt gets a unique local evidence root below the operating-system temporary directory:

```text
AgentSwitchboard/firstmate-windows-wsl/<run-id>/
```

Registered evidence includes:

- `firstmate-wsl-prerequisites.txt`
- `firstmate-wsl-prerequisites-stderr.log`
- `wsl-stderr.log`
- `wsl-bootstrap-stdout.txt`
- `firstmate-floor.txt`
- `bridge-stdout.txt` / `bridge-stderr.txt` when launched through the prerequisite wrapper

These files are local operational evidence, not tracked repository authority. Do not commit credentials, provider tokens, raw authentication output, private workstation paths, or runtime receipts.

## Failure handling

If the prerequisite gate reports missing tools, follow the emitted Ubuntu package command manually after reviewing it. If it reports missing GitHub authentication, use the emitted `gh auth login` command manually.

Those are explicit operator recovery gates. AgentSwitchboard does not silently install packages, log in, modify credentials, unregister WSL distributions, or claim a repaired environment without re-running the proof.

If the lower bridge fails, preserve the evidence root. Do not print an unconditional success marker after a failed child process.

## Validation

Focused repository validation:

```bash
python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_asb_convergence_contract.py
python3 tests/test_firstmate_operational_harness.py
python3 tests/test_firstmate_windows_harness_portability.py
python3 tests/test_firstmate_windows_wsl_bridge.py
python3 tests/test_firstmate_windows_wsl_prerequisite_gate.py
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
```

Windows CI additionally runs the native PowerShell contract front door. That hosted contract path intentionally returns before requiring a live WSL distro.

## Proof ceiling

Repository and hosted CI proof may establish:

- the tracked bridge/harness structure;
- explicit Ubuntu selection;
- bounded WSL process behavior;
- CRLF normalization;
- empty-stream safety;
- `WSLENV` path-translation policy;
- WSL-owned exact-head clone construction contract;
- prerequisite-gate ordering and non-mutation rules;
- Windows current-Python interpreter continuity;
- local evidence routing;
- absence of a revived AgentSwitchboard crew-routing layer.

It does **not** establish:

- successful execution on the operator's physical WSL/Ubuntu instance;
- productive FirstMate crew dispatch or supervision;
- native-Windows FirstMate execution;
- provider/model behavior;
- remote writes, PR delivery, merge, or deployment;
- Herdr readiness.

The next proof owner is `FM-WSL-12`: run the prerequisite-gated physical floor on an authorized Windows Admin Box. A successful physical floor still remains below the later `FM-CREW-13` local-only crew pilot.
