---
id: evidence-validation
version: 1.0.0
status: canonical
---

# Evidence and Validation

## Trigger

Use for failing checks, unresolved review findings, proof requests, contract drift, or claims that exceed available evidence.

## Inputs

- changed files and intended behavior;
- review findings or failing command output;
- repository validation surface;
- claimed and required proof levels.

## Procedure

1. Reproduce or validate each finding against current code.
2. Classify findings as valid, invalid, outdated, or unknown.
3. Add the smallest deterministic guard that prevents recurrence.
4. Run targeted validation.
5. Preserve exact results and skipped checks.
6. Resolve only findings actually fixed.
7. Update PR evidence and proof boundary.

## Outputs

- repaired tracked files;
- validator or regression test;
- finding disposition;
- evidence-backed PR description or report.

## Deterministic validation

Prefer executable checks and machine-readable artifacts. Re-read committed files from the remote branch when local state is unavailable.

## Forbidden scope

Do not resolve review threads without a committed fix or explicit evidence that the finding is invalid or outdated. Do not claim runtime proof from static inspection.

## Stop and escalate

Escalate security, data-loss, permission, or environment-dependent findings that cannot be safely reproduced.
