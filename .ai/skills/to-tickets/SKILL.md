---
id: to-tickets
version: 1.1.0
status: experimental
---

# To Tickets

## Source lineage

Salvaged from PR #94; adapted from the pinned donor `to-tickets/SKILL.md`.

## Trigger

Use after a plan/spec/Wayfinder destination is clear and implementation must be decomposed into bounded build tickets.

## Inputs

- approved settled source and decision links;
- domain context/ADRs;
- current code/test seams;
- tracker convention and delivery constraints.

## Procedure

1. Verify decisions are settled; route new uncertainty back to Wayfinder.
2. Prefer tracer-bullet vertical slices that fit one fresh context window.
3. Reuse current seams; prefactor only when required for independent safe slices.
4. Encode blockers and acceptance criteria.
5. Preserve human-approved granularity when the human is actively driving decomposition.
6. Link each implementation ticket to source decisions/spec.
7. Keep Wayfinder decision history intact.

## Outputs

- implementation tickets;
- dependency frontier;
- acceptance criteria;
- source links;
- execution owner/handoff.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Forbidden scope

Horizontal layer-only work when a vertical slice can stay green, unresolved decisions disguised as build tickets, or duplicate implementation truth.

## Stop and escalate

Stop when the route is unclear, blockers cannot be stated safely, ownership is crossed, or a new decision appears.
