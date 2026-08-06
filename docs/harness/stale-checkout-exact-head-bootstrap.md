# Stale-Checkout Exact-Head Bootstrap

## Purpose

A field workstation may contain a valid AgentSwitchboard checkout that predates `Validate-Technician-ExactHead.cmd`. The source checkout can still provide Git object storage and authentication, but it must not be switched, reset, cleaned, stashed, overwritten, or treated as the candidate implementation.

The focused bootstrap fetches an explicit remote ref, verifies the exact SHA, extracts the validator from the exact commit, and delegates to that repository-owned validator. It then requires a fresh registered exact-head artifact before reporting success.

## Current-checkout entrypoint

```powershell
& '.\Bootstrap-Technician-ExactHead.cmd' -SourceRepository '<repo-path>' -RemoteRef 'refs/heads/<branch>' -ExpectedHead '<40-character-sha>' -Mode ready -OpenReport
```

## Checkout predates the bootstrap itself

Use Git to extract the bootstrap engine from the exact fetched commit into a temporary file. Keep the command on one physical line when pasting into an interactive PowerShell prompt.

```powershell
$repo='<repo-path>'; $ref='refs/heads/<branch>'; $sha='<40-character-sha>'; & git.exe -C $repo fetch --no-tags origin $ref; if($LASTEXITCODE -ne 0){throw 'Fetch failed.'}; $actual=(& git.exe -C $repo rev-parse FETCH_HEAD).Trim().ToLowerInvariant(); if($actual -ne $sha.ToLowerInvariant()){throw "Head mismatch: expected $sha; fetched $actual"}; $runner=Join-Path $env:TEMP ('AgentSwitchboard-StaleCheckout-'+$sha.Substring(0,8)+'.ps1'); $source=@(& git.exe -C $repo show ($sha+':scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1')); if($LASTEXITCODE -ne 0 -or $source.Count -eq 0){throw 'Could not extract the exact bootstrap engine.'}; [IO.File]::WriteAllLines($runner,[string[]]$source,[Text.UTF8Encoding]::new($false)); & pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runner -SourceRepository $repo -RemoteRef $ref -ExpectedHead $sha -Mode ready -OpenReport; if($LASTEXITCODE -ne 0){throw "Bootstrap failed with exit code $LASTEXITCODE"}
```

The inline command performs only immutable extraction and dispatch. The tracked bootstrap engine owns origin verification, exact-head comparison, worktree isolation, delegated validation, artifact freshness checks, reporting, and clean bootstrap-worktree removal.

## Generated artifacts

Under `%LOCALAPPDATA%\AgentSwitchboard`:

- `stale-checkout-exact-head\runs\<runId>\stale-checkout-bootstrap.json`
- `stale-checkout-exact-head\runs\<runId>\stale-checkout-bootstrap.md`
- `stale-checkout-exact-head\harness-status\stale-checkout-exact-head-harness-status.json`
- `stale-checkout-exact-head\harness-status\stale-checkout-exact-head-harness-status.md`

The delegated validator separately owns:

- `exact-head-validation\runs\<runId>\exact-head-validation.json`
- `exact-head-validation\runs\<runId>\exact-head-validation.md`

Generated evidence is local operational data and must not be committed.

## Failure classifications

- `BLOCKED_UNEXPECTED_ORIGIN`
- `BLOCKED_HEAD_MISMATCH`
- `BLOCKED_BOOTSTRAP_WORKTREE`
- `BLOCKED_DELEGATED_VALIDATOR`
- `BLOCKED_ARTIFACT_MISSING`
- `PASS_EXACT_HEAD_DELEGATED`

## Validation

```powershell
python -m unittest tests.test_stale_checkout_exact_head_bootstrap
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-StaleCheckoutExactHeadBootstrap.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-StaleCheckoutExactHeadBootstrap.ps1
git --no-pager diff --check
```

## Proof ceiling

The bootstrap proves that a preserved stale checkout safely delegated to the exact fetched commit and read back its fresh exact-head artifact. Runtime proof remains bounded by the delegated artifact.
