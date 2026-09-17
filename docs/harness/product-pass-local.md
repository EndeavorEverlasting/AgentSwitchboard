# Product pass local proof

`Prove-ProductPassLocal` is a thin orchestrator that combines floor and merge-gate-local validation into a single product-pass evaluation. It reports PROVEN/UNPROVEN/BLOCKED_HOST/FLAGGED posture.

## Authority model

`Prove-ProductPassLocal` provides **local static proof only**. It does not prove:
- GitHub mergeability or required-check satisfaction
- Branch protection rules or review requirements
- Live Admin Box, physical-floor, or provider delivery
- Merge, release, or deployment authority

Use this tool as a convenient pre-flight check during local development.

## Proof ceiling

Local static proof orchestrator. Delegates to floor (always-on) and merge-gate-local (path-selected). Does not prove runtime, live-target, GitHub mergeability, or grant merge/release/deploy authority.

## Usage

### Basic usage (changed files vs origin/main)

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1
```

This will:
1. Always run `Prove-AutomatedTestFloorLocal.ps1`
2. Run `Prove-MergeGateLocal.ps1` with path selection
3. Check flag hygiene (`git diff --check`)
4. Report product-pass posture

### List orchestrated steps

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1 -ListOnly
```

### Specify custom base reference

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1 -BaseRef origin/develop
```

### Specify output directory

```powershell
pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1 -OutputRoot C:\temp\proof
```

## Parameters

- **RootPath**: Repository root path (default: parent of scripts directory)
- **OutputRoot**: Output directory for proof packets (default: temp directory)
- **BaseRef**: Git reference to compare against (default: `origin/main`)
- **ListOnly**: List orchestrated steps without executing them

## Orchestrated steps

### 1. Automated test floor (always-on)

Calls `Prove-AutomatedTestFloorLocal.ps1` with no path selection. This step always runs.

### 2. Merge gate local (path-selected)

Calls `Prove-MergeGateLocal.ps1` with the specified `BaseRef`. This step runs path-activated gates based on changed files.

### 3. Flag checks

Runs `git diff --check` to detect trailing whitespace and other diff hygiene issues.

## Posture semantics

Product-pass posture is reported as one of:

- **PROVEN**: All steps passed, no flags
- **UNPROVEN**: One or more steps failed
- **BLOCKED_HOST**: One or more steps blocked on host capability (e.g., Windows-only gate on Linux)
- **FLAGGED**: All steps passed, but flags present (e.g., trailing whitespace)

## Fail-closed behavior

`Prove-ProductPassLocal` fails closed in the following cases:

1. **Missing pwsh**: Exits immediately with `FAIL_CLOSED` error
2. **Floor failure**: Posture becomes `UNPROVEN`
3. **Merge-gate failure**: Posture becomes `UNPROVEN` unless blocked on host capability
4. **Merge-gate blocked on host**: Posture becomes `BLOCKED_HOST`
5. **Flag hygiene issues**: Posture becomes `FLAGGED`

Exit code is non-zero when posture is not `PROVEN`.

## Output artifacts

### Proof packet JSON

`product-pass-local-proof-packet.json` contains:
- Schema version and metadata
- Candidate SHA and base ref
- Posture (`PROVEN`, `UNPROVEN`, `BLOCKED_HOST`, `FLAGGED`)
- Proof ceiling disclaimer
- Orchestrated steps with status and details
- Lists of failures, blocked steps, and flags
- Paths to delegated output directories

### Proof packet Markdown

`product-pass-local-proof-packet.md` provides a human-readable summary:
- Posture and candidate SHA
- Proof ceiling
- Orchestrated steps table
- Failures, blocked steps, and flags (when present)

## Relationship to other validators

- **Prove-AutomatedTestFloorLocal**: Always-on floor; called by product-pass-local
- **Prove-MergeGateLocal**: Path-selected merge gates; called by product-pass-local
- **Test-AutomatedTestFloor**: Floor implementation; called by floor prove script
- **Domain Test-\* scripts**: Owned validators called by merge-gate-local gates

This is a **thin orchestrator** that delegates to existing prove scripts without duplicating their logic.

## Meta contracts

`tests/test_product_pass_local.py` validates:
- Prove script exists and references orchestrated scripts
- Floor is always-on, merge-gate is path-selected
- Uses PROVEN/UNPROVEN/BLOCKED_HOST/FLAGGED posture semantics
- Proof ceiling forbids merge authority
- No logic duplication (delegates to existing scripts)
- Fail-closed on missing tools
- Detects BLOCKED_HOST from merge-gate
- Includes flag checks
- Exits non-zero when posture is not PROVEN
- Generates proof packet artifacts
- Does not claim Admin Box or handle secrets
- Zero-test detection (fail-closed)

## Acceptance gates

Before accepting changes to product-pass-local:
1. `python -m unittest tests.test_product_pass_local -v` must pass with multiple tests
2. `pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1 -ListOnly` must list steps
3. `pwsh -NoLogo -NoProfile -File scripts/Prove-ProductPassLocal.ps1` must exit non-zero on floor failure
4. Proof ceiling text must forbid merge authority
5. Must delegate to existing prove scripts (no logic duplication)

## References

- `scripts/Prove-ProductPassLocal.ps1`: Orchestrator implementation
- `scripts/Prove-AutomatedTestFloorLocal.ps1`: Always-on floor proof
- `scripts/Prove-MergeGateLocal.ps1`: Path-selected merge-gate proof
- `tests/test_product_pass_local.py`: Meta contracts
- `docs/harness/automated-test-floor.md`: Floor documentation
- `docs/harness/merge-gate-local.md`: Merge-gate documentation
- `AGENTS.md`: Agent operating contract
