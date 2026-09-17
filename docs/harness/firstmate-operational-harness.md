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

The optional `.cmd` wrapper calls `pwsh -NoLogo -NoProfile -File` and respects the host PowerShell execution policy; it does not force `ExecutionPolicy Bypass`.

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

Reviewed Windows path variables cross the boundary through `WSLENV` `/p` translation. Before adding a bridge-owned variable, the bridge removes any inherited `WSLENV` entry for the same variable name so a stale unmodified entry cannot compete with the required `/p` mode. The bridge does not execute `wslpath`.

### Standalone Linux-owned exact-head clone

The bridge never asks Linux Git to operate on a Windows-created linked-worktree `.git` indirection. It resolves the committed Windows source repository, translates that source path through `WSLENV /p`, creates a standalone clone inside WSL, detaches it at the exact AgentSwitchboard SHA, and verifies the SHA before running validators.

The standalone clone is script-owned temporary state under `/tmp/agentswitchboard-firstmate-*`. It is removed after both successful and failed runs by default, with a guarded prefix check before deletion. Direct lower-bridge diagnostics may opt in to `-PreserveWslWorkspaceOnFailure`; preservation is never the default.

### Interpreter continuity

The Windows contract front door resolves the active `python.exe`/`python` command and invokes repository Python tests through that exact interpreter. It does not spawn literal `python3` from Windows. The Linux/WSL validator registry uses `python3`, matching the prerequisite floor.

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

If the lower bridge fails, preserve the Windows-side evidence root. Its script-owned WSL clone is cleaned by default so repeated proof attempts do not leak temporary repositories. Use `-PreserveWslWorkspaceOnFailure` only on a direct lower-bridge diagnostic run when the Linux clone itself must be inspected. Do not print an unconditional success marker after a failed child process.

## Validation

Focused repository validation:

```bash
bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
```

That canonical Linux entrypoint owns the focused integration/convergence/operational/portability/bridge/prerequisite tests, shell syntax, and working/staged diff hygiene. CI calls this entrypoint rather than duplicating its sequencing.

Windows CI runs the native PowerShell contract front door. That hosted contract path intentionally returns before requiring a live WSL distro.

### Optional validation hooks

Two optional pre-commit and pre-push validation hooks are registered in the operational manifest:

**Pre-commit hook:**
```bash
bash tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPreCommit.sh
```

Runs the integration contract, operational harness, and Windows WSL bridge tests plus shell syntax checks and `git diff --check`.

**Pre-push hook:**
```bash
bash tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPrePush.sh --base <exact-base-ref>
```

Runs the pre-commit suite plus `git diff --check` against the specified base branch.

These hooks are **optional operator/CI helper surfaces** registered in `tooling/firstmate/harness/operational/manifest.json` as `pre_commit_hook` and `pre_push_hook`. They are not automatically installed as Git hooks. Proof ceiling remains unchanged: contract validation only, not physical WSL execution or live crew dispatch.

## Proof ceiling

Repository and hosted CI proof may establish:

- the tracked bridge/harness structure;
- explicit Ubuntu selection;
- bounded WSL process behavior;
- CRLF normalization;
- empty-stream safety;
- deterministic `WSLENV` path-translation policy;
- WSL-owned exact-head clone construction and cleanup contract;
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

The next proof owner is `FM-WSL-12`: on an authorized Windows Admin Box, run harness `-Mode physical-floor-continue` (or `Invoke-FirstMatePhysicalFloorContinuation.ps1`) so allowlisted missing packages can be repaired and the floor rerun without another permission round-trip; stop only for GitHub auth or a non-package blocker. Operator checklist: [`docs/harness/firstmate-wsl-physical-floor-runbook.md`](firstmate-wsl-physical-floor-runbook.md). A successful physical floor still remains below the later `FM-CREW-13` local-only crew pilot.
