# Stale-Checkout Exact-Head Bootstrap

## Purpose

A field workstation may have a valid AgentSwitchboard checkout that is stale, dirty, or otherwise unsuitable as the candidate implementation. Preserve that checkout. Do not switch it, reset it, clean it, stash it, overwrite it, or pull over its local work just to reach a newer live-cert head.

The stale-checkout bootstrap uses the existing checkout only for canonical repository identity, Git object storage, and authentication. It fetches one explicit remote ref, requires the exact expected SHA, extracts the exact-head validator from that verified commit, delegates validation/readiness into the validator's isolated worktree, and then requires a fresh registered exact-head artifact before reporting success.

## Normal operator path

When the checkout already contains the bootstrap, use the tracked root entrypoint:

```powershell
& .\Bootstrap-Technician-ExactHead.cmd `
  -SourceRepository (Get-Location).Path `
  -RemoteRef 'refs/heads/main' `
  -ExpectedHead '<40-character-sha>' `
  -Mode ready `
  -OpenReport
```

This is the canonical recovery path. Do not reconstruct the bootstrap engine as an ad-hoc long command when the tracked CMD exists.

## Checkout predates the bootstrap itself

A truly old checkout may not contain `Bootstrap-Technician-ExactHead.cmd`. In that case, preserve it and use Git only to obtain the bootstrap engine from the exact fetched commit. Execute the extracted `.ps1` as one script invocation; do not paste separated `if`/`else` fragments or invent a competing launcher.

```powershell
& {
    $repo = (Get-Location).Path
    $ref = 'refs/heads/main'
    $sha = '<40-character-sha>'
    git -C $repo fetch --no-tags origin $ref
    if ($LASTEXITCODE -ne 0) { throw "fetch failed: $LASTEXITCODE" }
    $actual = (@(git -C $repo rev-parse FETCH_HEAD) | Select-Object -First 1)
    if (-not $actual -or $actual.Trim() -ne $sha) { throw "expected $sha; fetched $actual" }
    $runner = Join-Path $env:TEMP "AgentSwitchboard-StaleCheckout-$($sha.Substring(0,8)).ps1"
    $source = @(git -C $repo show "${sha}:scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1")
    if ($LASTEXITCODE -ne 0 -or $source.Count -eq 0) { throw 'bootstrap extraction failed' }
    [IO.File]::WriteAllLines($runner, [string[]]$source, [Text.UTF8Encoding]::new($false))
    pwsh -NoLogo -NoProfile -File $runner -SourceRepository $repo -RemoteRef $ref -ExpectedHead $sha -Mode ready -OpenReport
    if ($LASTEXITCODE -ne 0) { throw "bootstrap failed: $LASTEXITCODE" }
}
```

The command is intentionally one complete PowerShell submission. `operator-command-delivery` owns executable/operator command boundaries; `powershell-interactive-execution` owns the PowerShell paste/parse boundary. The bootstrap engine, not the outer recovery block, owns exact origin verification, immutable validator extraction, delegated validation, artifact freshness checks, evidence generation, and cleanup of its own temporary validator runner.

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
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1 -CandidatePath scripts/Invoke-StaleCheckoutExactHeadBootstrap.ps1
git --no-pager diff --check
```

## Proof ceiling

The bootstrap proves that a preserved stale checkout safely delegated to the exact fetched commit and read back its fresh exact-head artifact. Runtime and technician readiness proof remain bounded by the delegated artifact.
