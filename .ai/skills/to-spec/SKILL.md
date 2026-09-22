---
id: to-spec
version: 1.1.0
status: experimental
---

# To Spec

## Source lineage

Salvaged from PR #94; adapted from the pinned donor `to-spec/SKILL.md`.

## Trigger

Use only after the required decisions are settled and the next artifact is an implementation-ready specification.

## Inputs

- settled map/conversation and decision links;
- domain context/ADRs;
- current code/testing seams;
- destination/out-of-scope boundary.

## Procedure

1. Prove the decision route is clear; otherwise return to Wayfinder.
2. Read settled decision sources and current implementation seams.
3. Synthesize rather than re-decide.
4. Specify stable behavior and test seams rather than fragile implementation detail.
5. Include problem, solution, user stories, implementation/testing decisions, out of scope, notes, and decision sources.
6. Mark lifecycle `temporary-until-implementation`.
7. Hand off to `to-tickets` or bounded implementation; retire the temporary spec after accepted implementation without deleting decision history.

## Outputs

- temporary implementation-ready specification;
- decision links;
- testing seams;
- out-of-scope boundary;
- execution handoff.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Forbidden scope

Invented decisions, permanent promotion of the spec over source decisions, or deleting decision history.

## Stop and escalate

Stop if readiness cannot be proven, source decisions conflict, or a new product/architecture choice is required.
