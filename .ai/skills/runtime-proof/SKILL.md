---
id: runtime-proof
version: 1.0.0
status: canonical
---

# Runtime Proof

## Trigger

Use when static or build proof is insufficient and the requested behavior involves launchers, installers, harnesses, integrations, deployments, or live targets.

## Inputs

- exact runtime environment;
- authorized target and mutation limits;
- rollback and cleanup rules;
- expected observable behavior;
- existing lower-level proof.

## Procedure

1. Confirm contract, static, and build floors first.
2. Choose the lowest-risk environment that can prove the behavior.
3. Create bounded run context and evidence paths.
4. Execute once with explicit caps and no blind retries.
5. Capture process ACK, behavior, artifacts, and final state.
6. Clean up only owned temporary assets.
7. Escalate before any broader or live-target expansion.

## Outputs

- runtime command and environment record;
- logs and machine-readable summary;
- observed behavior and proof level;
- cleanup and remaining-risk report.

## Deterministic validation

Compare expected artifacts and behavior to the run contract. Distinguish process start, command ACK, behavior observed, and live-target success.

## Forbidden scope

No unauthorized deployment, customer-target mutation, save or account mutation, credential persistence, destructive cleanup, or repeated blind execution.

## Stop and escalate

Stop on unexpected mutation, missing rollback, ambiguous target, repeated failure, or evidence that the environment differs from the approved runtime.
