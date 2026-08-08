---
id: to-tickets
version: 1.0.0
status: experimental
---

# To Tickets

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, `skills/engineering/to-tickets/SKILL.md`, blob `96deac51d4391a3f691478d48f85f43261516c08`. Snapshot: `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/to-tickets/SKILL.md`.

## Trigger

Use after a plan/spec/Wayfinder destination is clear and implementation work must be split into agent-grabbable build tickets. These are **implementation tickets**, not Wayfinder decision tickets.

## Inputs

- approved spec/settled source and decision links;
- domain glossary/ADRs;
- current codebase/test seams;
- repository tracker/triage convention;
- delivery constraints and safe blockers.

## Procedure

1. Verify required decisions are settled. If a build ticket would need to decide product/architecture behavior, return that uncertainty to Wayfinder instead of guessing.
2. Draft tracer-bullet vertical slices: each ticket makes a narrow but complete user-visible/verifiable path work within one fresh context window.
3. Prefer existing seams; prefactor only where it makes later slices independently safe.
4. Add explicit blockers. Use expand–migrate–contract for wide mechanical refactors that cannot stay green as vertical slices.
5. Present the decomposition for human review when the human is actively driving ticket granularity; do not silently reinterpret the approved spec.
6. Publish one implementation ticket per tracker item/file with acceptance criteria and native blockers where supported.
7. Link each implementation ticket to the source spec/map and any non-obvious decision/prototype constraint.
8. Leave Wayfinder decision tickets/history intact.

## Outputs

- one tracker item per implementation slice;
- dependency graph/frontier;
- acceptance criteria;
- source spec/map/decision links;
- explicit execution owner/handoff.

## Deterministic validation

Each implementation ticket must be independently demoable/verifiable unless it is an explicitly declared expand–migrate–contract batch. No ticket may carry a Wayfinder decision type as a substitute for unresolved planning. Wayfinder contract changes run `python tests/test_wayfinder_harness.py` and `scripts/Test-WayfinderHarness.ps1`.

## Forbidden scope

- horizontal layer-only ticket when a vertical slice can stay green;
- decision question mislabeled as implementation work;
- build ticket created while a required Wayfinder decision remains unresolved;
- duplicate implementation truth split between a mega-ticket and child tickets;
- rewriting/closing decision tickets merely because implementation tickets exist.

## Stop and escalate

Stop if the spec/route is not actually clear, ticket blockers cannot be stated safely, decomposition would cross forbidden ownership, or a slice reveals a new decision that belongs back in Wayfinder.
