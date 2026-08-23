---
id: exact-output-grounding
status: canonical
owner: tooling/harness/operational
---
# Exact Output Grounding

## Trigger
Use before generation or execution when exact repository/tool structure must not be recalled approximately: signatures, enum values, IDs, governed paths/hostnames, tool names/arguments, command syntax, schema fields, or versioned contracts.

## Inputs
- current authoritative machine-readable source;
- proposed protected action;
- exact fields that can cause an unsafe or invalid execution if wrong.

## Procedure
1. Retrieve the current source and its version/identity; never promote remembered structure to authority.
2. Build the compact packet with `tooling/harness/operational/exact-grounding/exact_grounding.py build-packet`.
3. Require source attribution for every proposed exact tool/argument field.
4. Immediately before the side effect, run the gate, which re-reads and hashes the source.
5. Execute only through a host-owned callback after `GROUNDED_PASS`.
6. On `UNSOURCED_BLOCK`, `CONTRADICTION_BLOCK`, `SCHEMA_MISMATCH`, or `GROUNDING_FAILURE`, repair/reground; never override deterministic failure with model judgment.

## Outputs
- compact grounding packet with path, SHA-256, schema ID, version, constraints, and JSON Pointer provenance;
- deterministic gate result;
- host execution proof only when the gate passes.

## Deterministic validation
Run `python3 tests/test_exact_grounding_gate.py` and the owning operational-harness validators.

## Forbidden scope
Do not dump whole repositories/API catalogs into prompts. Do not make this layer own context-budget strategy, eval design, retry/idempotency, provider credentials, or semantic decisions absent from the current authoritative structure. Do not execute an unsourced exact value.

## Stop and escalate
If the source is missing, malformed, stale, lacks a closed exact contract, or the checker cannot prove the critical field, stop at `GROUNDING_FAILURE` or the applicable block status and name the missing authority.
