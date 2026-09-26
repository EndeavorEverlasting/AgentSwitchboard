# Execution Adapter Contract v2 — TC-FAC

## Purpose

TC-FAC adds an explicit versioned execution boundary for runtimes that need bounded fan-out and retry-safe authority binding. It does **not** widen v1 in place.

- v1 remains `agentswitchboard.execution-request/v1` + `execution-receipt/v1`.
- v2 is `agentswitchboard.execution-request/v2` + `execution-receipt/v2`.
- Existing v1 consumers remain valid, but v1 evidence cannot satisfy a TC-FAC-dependent runtime claim.

## New v2 authority binding

Every v2 request requires:

`actionFingerprint = sha256:<64 lowercase hex>`

The fingerprint is the immutable identity of the already-admitted action. The adapter does not derive permission from the fingerprint; it preserves the authority binding chosen upstream.

Every v2 receipt must echo the exact same fingerprint. Missing or mismatched fingerprints fail closed before runtime proof can be promoted.

## New v2 execution envelope

Every v2 request fixes four ceilings before dispatch:

- `maxWorkers`
- `maxParallelWorkers`
- `maxModelTokens`
- `maxWallClockSeconds`

Semantic constraints additionally require:

- `maxParallelWorkers <= maxWorkers`
- `maxWallClockSeconds <= timeoutSeconds`

Every v2 receipt records:

- `workersStarted`
- `peakParallelWorkers`
- `modelTokensUsed`
- `wallClockMs`

The measured usage may not exceed the admitted envelope. An over-budget receipt is contract-invalid; it is not successful runtime proof.

## Version transition

Schema identity is the transition gate.

- A v1 request is never interpreted as v2.
- A v2 request missing the fingerprint or execution envelope is invalid.
- A v2 receipt missing its fingerprint or execution usage is invalid.
- Adapters may continue accepting v1 while they are not TC-FAC-dependent.
- FrontierAgent FA-2 and other bounded fan-out runtimes must use v2 unless a later reviewed contract supersedes it.

## Fixtures and proof

Positive fixtures:

- `fixtures/execution-request.v2.valid.json`
- `fixtures/execution-receipt.v2.valid.json`

Negative fixtures:

- missing request fingerprint;
- mismatched receipt fingerprint;
- receipt usage over parallel/token/time ceilings.

Owning regression:

`python tests/test_execution_adapter_contract_v2.py`

Combined wrapper:

`pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionAdapterContract.ps1`

## Proof ceiling

This contract proves static/synthetic versioning, authority-binding, and budget semantics. It does not prove a runtime actually enforces worker spawning or token accounting. FrontierAgent FA-2 must separately map and observe these fields at runtime before that stronger claim is made.
