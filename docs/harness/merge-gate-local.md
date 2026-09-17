# Merge gate local proof

`Prove-MergeGateLocal` orchestrates local execution of merge-relevant GitHub Actions gates, providing a single CLI to emanate the merge-adjacent CI surface while preserving real app/host validators and failing closed when the host cannot run a selected gate.

## Authority model

`Prove-MergeGateLocal` provides **local static/contract proof only**. It does not prove:
- GitHub mergeability or required-check satisfaction
- Branch protection rules or review requirements
- Live Admin Box, physical-floor, or provider delivery
- Merge, release, or deployment authority

Use this tool to substitute Actions minutes for runnable gates during local development and pre-flight validation.

## Proof ceiling

Local static/contract emulation of merge-relevant gates. Not GitHub mergeability, not required-check satisfaction, not live Admin Box / provider / deploy.

## Usage

### Basic usage (changed files vs origin/main)

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1
```

This will:
1. Compute changed files vs `origin/main`
2. Select path-activated gates matching changed files
3. Always run always-on gates (e.g., automated-test-floor)
4. Execute gate commands with captured exit codes
5. Write proof packet to temp directory

### List selected gates without execution

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1 -ListOnly
```

### Specify custom base reference

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1 -BaseRef origin/develop
```

### Include all path-activated gates (ignore path filtering)

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1 -IncludeAllPathGates
```

### Specify output directory

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1 -OutputRoot C:\temp\proof
```

## Parameters

- **RootPath**: Repository root path (default: parent of scripts directory)
- **OutputRoot**: Output directory for proof packets (default: temp directory)
- **BaseRef**: Git reference to compare against (default: `origin/main`)
- **ListOnly**: List selected gates without executing them
- **IncludeAllPathGates**: Include all path-activated gates regardless of changed files

## Gate selection

### Always-on gates

Always-on gates run on every invocation:
- **automated-test-floor**: Dependency-free static floor via `Prove-AutomatedTestFloorLocal.ps1`

### Path-activated gates

Path-activated gates run only when changed files match workflow `paths:` filters:
- **application-floor-windows-core**: GNHF fleet and Hermes setup contracts
- **application-floor-linux-hygiene**: JSON parse, shell syntax, diff hygiene
- **operational-merge-authority**: Merge-authority continuation and operational harness
- **opinion-ledger-tracer**: Opinion tracer and work ledger contracts
- **firstmate-interop-contract**: FirstMate contract-only mode (not physical-floor)

## Fail-closed behavior

`Prove-MergeGateLocal` fails closed in the following cases:

1. **Missing host capability**: When a selected gate requires a host (e.g., `windows`, `admin-box`) that the current environment cannot provide, the gate status is `BLOCKED_HOST_REQUIRED` with a `next` action, and the overall result is `FAIL` (exit code ≠ 0).

2. **Missing tools**: When `pwsh` or `python` is not found, the script exits immediately with `FAIL_CLOSED` error.

3. **Zero always-on gates**: If no always-on gates are executed, the script fails with `FAIL_CLOSED` error.

4. **Skip is never pass**: A gate that does not run is never counted as passed; it is either `BLOCKED` or the overall proof fails.

## Output artifacts

### Proof packet JSON

`merge-gate-local-proof-packet.json` contains:
- Schema version and metadata
- Candidate SHA and base ref
- Changed file count and current host
- Overall result (`PASS` or `FAIL`)
- Proof ceiling disclaimer
- Gate execution steps with status, exit codes, and details
- List of failures

### Proof packet Markdown

`merge-gate-local-proof-packet.md` provides a human-readable summary:
- Result and candidate SHA
- Proof ceiling
- Gate results table

## Manifest

Gate configuration is stored in `.ai/harness/merge-gate-local.manifest.json`:
- Schema version and manifest ID
- Proof level and ceiling
- Fail-closed rules
- Gate definitions with paths, commands, host requirements, and proof descriptions

## Meta contracts

`tests/test_merge_gate_local.py` validates:
- Manifest exists and is valid JSON
- Required schema fields are present
- Fail-closed rules are enforced
- Proof ceiling forbids merge authority
- At least one always-on gate exists
- All gates have required fields
- Gate commands reference existing scripts
- Zero-test detection (fail-closed)

## Relationship to other validators

- **Prove-AutomatedTestFloorLocal**: Always-on floor; called by merge-gate-local
- **Test-AutomatedTestFloor**: Floor implementation; called by Prove-AutomatedTestFloorLocal
- **Domain Test-\* scripts**: Owned validators called by path-activated gates
- **CI workflows**: GitHub Actions surface that merge-gate-local emulates locally

## Comparison to GitHub Actions

| Aspect | GitHub Actions | Prove-MergeGateLocal |
|--------|----------------|----------------------|
| Execution | Cloud runners | Local host |
| Mergeability | Yes (with branch protection) | No |
| Required checks | Yes | No |
| Host flexibility | Windows/Linux/macOS runners | Current host only |
| Path filtering | Native workflow `paths:` | Emulated glob matching |
| Actions minutes | Consumed | Zero |
| Authority | Can gate merges | Proof only, no authority |

## Acceptance gates

Before accepting changes to merge-gate-local:
1. `pwsh -NoLogo -NoProfile -File scripts/Prove-AutomatedTestFloorLocal.ps1` must pass
2. `pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1 -ListOnly` must list gates
3. `pwsh -NoLogo -NoProfile -File scripts/Prove-MergeGateLocal.ps1` must pass on clean tree
4. `python -m unittest tests.test_merge_gate_local -v` must pass with multiple tests
5. Packet must show always-on gates passed
6. Simulated Windows-only gate on Linux must exit non-zero (not pass)
7. Proof ceiling text must forbid merge authority

## References

- `.ai/harness/merge-gate-local.manifest.json`: Gate configuration
- `scripts/Prove-MergeGateLocal.ps1`: Orchestrator implementation
- `scripts/Prove-AutomatedTestFloorLocal.ps1`: Always-on floor proof
- `tests/test_merge_gate_local.py`: Meta contracts
- `docs/governance/agent-operating-details.md`: Broader governance context
- `AGENTS.md`: Agent operating contract
