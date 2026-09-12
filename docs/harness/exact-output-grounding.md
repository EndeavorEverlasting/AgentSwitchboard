# Exact Output Grounding Gate

Use this gate when an agent is about to emit or execute repository-owned exact details where a plausible-but-wrong value is unacceptable: tool names and arguments, function/type signatures, enum values, internal IDs, governed paths/hostnames, command syntax, database/OpenAPI fields, or other versioned structural facts.

## Authority boundary

The current implementation consumes a **closed JSON Schema draft 2020-12 protected-action contract**. The schema must carry a stable `$id`, an `x-source-version`, a `tool` string `const`, and an `arguments` object with `additionalProperties: false`. The source file itself remains authoritative; model memory and the grounding packet do not.

`exact_grounding.py build-packet` reads the source immediately before use, hashes the exact bytes, and creates a compact packet containing only the tool identity, required/allowed argument names, and constraints needed by the current proposal. The packet retains JSON Pointer attribution back to the source.

## Fail-closed gate

Before a protected side effect, the runtime must call the deterministic gate and re-read the authoritative source path. Outcomes are:

- `GROUNDED_PASS` — exact fields, attribution, constraints, and current source identity agree.
- `UNSOURCED_BLOCK` — a proposed tool/field or its attribution is absent from the packet.
- `CONTRADICTION_BLOCK` — a grounded value violates an encoded type/enum/const/pattern/bound constraint.
- `SCHEMA_MISMATCH` — the proposed action/provenance shape is malformed or a required argument is absent.
- `GROUNDING_FAILURE` — packet/source/checker data is malformed, unavailable, or stale.

Only `GROUNDED_PASS` may reach the host executor. The module intentionally does not execute arbitrary commands; `intercept_and_execute()` accepts a host-owned callback and invokes it exactly once after the deterministic pass.

## Example

```bash
python3 tooling/harness/operational/exact-grounding/exact_grounding.py build-packet \
  --schema tooling/harness/operational/exact-grounding/fixtures/protected-action.schema.json \
  --proposal proposal.json \
  --output exact-grounding-packet.json

python3 tooling/harness/operational/exact-grounding/exact_grounding.py gate \
  --packet exact-grounding-packet.json \
  --proposal proposal.json \
  --output exact-grounding-gate-result.json
```

Generated packets/results are runtime evidence and should remain outside the repository.

## Routing boundaries

Context-budget/attention engineering belongs to the context-engineering owner. Eval-suite design belongs to the eval owner. Retry/idempotency after a **valid** tool call belongs to agent reliability. This gate owns only exact structural grounding and pre-side-effect deterministic rejection.

## Proof ceiling

The tracked contract and fixture tests prove deterministic JSON-Schema-derived grounding, provenance/source-version checks, stale/checker failure behavior, and the host execution seam. They do **not** prove semantic truth that is absent from the authoritative schema, correctness of an upstream schema, model reasoning quality, or integration into every concrete provider/tool adapter.
