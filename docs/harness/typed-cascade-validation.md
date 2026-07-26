# Typed Cascade Validation Harness

## Purpose

This harness turns the useful engineering pattern behind “Pydantic at the door, ontology at the ledger” into an AgentSwitchboard repository contract.

Python's runtime is permissive unless an application enforces stronger contracts. A Pydantic-style layer catches structural mistakes before an operation runs: missing fields, wrong scalar/container types, invalid ranges, and values outside a closed enumeration. That is the **pre-action gate**.

A structurally valid result can still be wrong in the domain. An OWL/SHACL-style ontology layer can express rules prose is easy to violate: one-valued properties, disjoint roles/classes, closed enumerations, domain/range constraints, and references that must point to real entities. That is the **post-action gate**.

AgentSwitchboard's contract is implementation-library agnostic. Pydantic, OWL, or SHACL may later implement these roles, but their installation or execution is not assumed by this harness.

## Canonical cascade

```text
request.received
    |
    v
PRE-ACTION STRUCTURAL GATE
required fields / types / ranges / enums / authority prerequisites
    |
    +---- reject ----> cascade.input.rejected ----> final handoff
    |
    v
action.authorized
    |
    v
DETERMINISTIC ACTION BOUNDARY
(agent proposes/selects; owned code performs the side effect)
    |
    v
action.result.observed
    |
    v
POST-ACTION DOMAIN GATE
freshness / cardinality / disjointness / enumeration / domain-range / references
    |
    +---- reject ----> cascade.result.rejected ----> final handoff
    |
    v
result.validated
    |
    v
immutable successor event
new eventId + inherited correlationId + immediate-parent causationId
    |
    v
evidence sink / next predicate
```

This is the repository meaning of a **cascading event**: every successor exists because a deterministic predicate accepted the previous stage, and the event carries enough causality to prove that relationship.

## Why two gates

The two gates answer different questions.

| Gate | Question | Examples of defects caught |
|---|---|---|
| Pre-action | Is this request safe and structurally meaningful enough to attempt? | missing field, string where integer required, invalid mode, undeclared authority |
| Post-action | Is the observed result logically valid in the declared domain/world state? | two terminal states for one action, mutually exclusive classes both asserted, made-up proof level, wrong causation entity type, missing action/event reference |

A pre-gate pass is not a result pass. A post-gate pass is not live-runtime proof. Every proof level remains explicit.

## Pure-agent rule

The harness deliberately separates reasoning from side effects:

```text
agent = proposal / selection / interpretation
code = mutation / observation / validation / event emission
```

The agent may decide which registered operation to request, but it does not become an invisible mutation channel. Product code that eventually consumes this contract must own the deterministic action boundary and its receipts.

This sprint does **not** wire product dispatchers; doing so would cross the forbidden product-code boundary.

## Machine-readable surfaces

- `tooling/cascade/harness/typed-gates/codebase-map.json` — focused map and known traps.
- `tooling/cascade/harness/typed-gates/typed-cascade.registry.json` — two-gate and cascade policy.
- `tooling/cascade/harness/typed-gates/ontology.registry.json` — ontology-style semantic rule vocabulary and cascade rules.
- `tooling/cascade/harness/typed-gates/artifact-registry.json` — generated evidence names, locations, sensitivity, and proof ceilings.
- `tooling/cascade/harness/typed-gates/schemas/typed-cascade-harness.schema.json` — request, gate result, action observation, successor, and handoff shapes.
- `tooling/cascade/harness/typed-gates/fixtures/typed-cascade.cases.json` — synthetic pass/rejection suite.
- `tooling/cascade/harness/typed-gates/workflows/` — intake, pre-gate, post-gate, successor emission, and failure handoff.
- `.ai/skills/typed-cascade-validation/SKILL.md` — agent-facing procedure.
- `scripts/Test-TypedCascadeHarness.ps1` — tracked-file and semantic completeness gate.
- `tests/test_typed_cascade_harness.py` — dependency-free behavioral reducer.
- `tooling/cascade/Get-TypedCascadeHarnessStatus.ps1` — English/JSON repository status.
- `tooling/cascade/hooks/Invoke-TypedCascadeHarnessPreCommit.ps1` — opt-in local gate; never installed implicitly.
- `.github/workflows/typed-cascade-harness.yml` — Windows/Linux CI.

## Ontology-style rules

The initial registry includes five reusable rule classes:

1. **functional-property** — at most one value for a property, such as one terminal classification for one action;
2. **disjoint-classes** — an entity cannot be both a validated-success successor and a rejected terminal in the same result;
3. **one-of** — values such as proof level come from a fixed vocabulary rather than free text;
4. **domain-range** — relationships such as `causationId` connect the expected entity classes;
5. **required-reference** — an `actionId` or causation reference must resolve inside the current run ledger.

These intentionally mirror the strengths of OWL/SHACL-style graph constraints without claiming that an OWL reasoner is installed.

## Terminal classifications

The synthetic reducer distinguishes, among others:

```text
PASS_SYNTHETIC_CASCADE
REJECT_INPUT_SCHEMA
REJECT_INPUT_AUTHORITY
BLOCKED_ACTION_NOT_OBSERVED
REJECT_STALE_RESULT
REJECT_RESULT_CARDINALITY
REJECT_RESULT_DISJOINTNESS
REJECT_RESULT_ENUMERATION
REJECT_RESULT_DOMAIN_RANGE
REJECT_RESULT_REFERENCE
REJECT_CAUSALITY
```

Those states are not interchangeable. In particular:

- a rejected request was **not executed**;
- a missing observation is **not** an ontology failure;
- an observed action with an invalid result remains observed but may **not propagate success**;
- stale evidence never repairs a current-run gap;
- agent prose cannot rename a deterministic rejection as success.

## Artifacts

Generated run evidence belongs outside Git under:

```text
%TEMP%/AgentSwitchboard/TypedCascade/runs/<run-id>/
```

Canonical names are defined in `artifact-registry.json`. Generated runtime evidence is not repository authority and must not be committed unless deliberately minimized and reviewed as a public fixture.

## Operator commands

One-command offline proof:

```cmd
Test-TypedCascadeHarness.cmd
```

Focused commands:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-TypedCascadeHarness.ps1
python tests/test_typed_cascade_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-RuntimeEventContract.ps1
pwsh -NoLogo -NoProfile -File tooling/cascade/Get-TypedCascadeHarnessStatus.ps1
git diff --check
```

## Working

At repository-contract level this slice provides:

- explicit pre- and post-action gates;
- a reusable ontology-style rule vocabulary;
- immutable successor-event requirements compatible with the existing runtime-event contract;
- same-run/action/correlation freshness rules;
- deterministic terminal classifications;
- synthetic accepted and rejected cascades;
- generated-evidence hygiene;
- agent procedure, operator report, hook, validators, and CI.

## Missing / intentionally unproved

- no product dispatcher consumes the gate registry yet;
- no live side effect is executed by this harness;
- no Pydantic runtime adapter is installed or certified;
- no OWL reasoner or SHACL engine is installed or certified;
- no live runtime cascade is observed;
- no external world-state store is queried;
- no target mutation or deployment is authorized.

## Proof ceiling

A green harness proves the tracked structure and synthetic semantics of the two-gate cascade. It does **not** prove that AgentSwitchboard product execution already flows through the gates. That wiring belongs to a separate product implementation sprint after this contract lands.
