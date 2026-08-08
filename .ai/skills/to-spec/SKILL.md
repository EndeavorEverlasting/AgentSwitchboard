---
id: to-spec
version: 1.0.0
status: experimental
---

# To Spec

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, `skills/engineering/to-spec/SKILL.md`, blob `3fd64959895b7eb095a13d797e1c7544f1f08c8f`. Snapshot: `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/to-spec/SKILL.md`.

## Trigger

Use when a conversation or Wayfinder map has already made the required decisions and the next artifact is an implementation-ready specification. Do not use this skill to fill unresolved decisions with model guesses.

## Inputs

- source conversation/map and decision-ticket links;
- domain glossary/ADRs;
- current codebase/testing seams;
- destination/out-of-scope boundary;
- proof that required Wayfinder tickets are resolved and fog is empty when Wayfinder is the source.

## Procedure

1. Verify the decision route is clear. If a required decision/fog remains, return to Wayfinder and create/reopen the appropriate decision ticket.
2. Read linked decision sources only as needed, plus domain glossary/ADRs/current codebase seams.
3. Synthesize; do not re-interview merely to repeat settled decisions.
4. Prefer the highest stable existing test seam and specify external behavior rather than implementation detail.
5. Publish a spec containing Problem Statement, Solution, User Stories, Implementation Decisions, Testing Decisions, Out of Scope, Further Notes, and Decision Sources.
6. The spec may summarize decisions, but linked decision tickets remain the durable primary rationale.
7. Mark lifecycle `temporary-until-implementation`.
8. Hand off to `to-tickets` or bounded implementation. After implementation acceptance, retire/archive/remove the temporary spec according to tracker policy without deleting decision history.

## Outputs

- one implementation-ready temporary specification;
- source map/decision links;
- testing seams;
- explicit out-of-scope boundary;
- exact post-spec handoff.

## Deterministic validation

Validate against `tooling/harness/wayfinder/schemas/spec.schema.json`. Wayfinder readiness requires no unresolved required decision ticket and no `Not yet specified` fog. Run `python tests/test_wayfinder_harness.py` and `scripts/Test-WayfinderHarness.ps1` when this skill changes.

## Forbidden scope

- invented decision where the map remains foggy;
- permanent promotion of the spec above its decision sources;
- fragile file-path/code-snippet authority except a clearly identified decision-rich prototype excerpt;
- deleting decision-ticket history when retiring the spec.

## Stop and escalate

Stop if readiness cannot be proven, a source decision contradicts another, testing seams are unknown and require a new decision, or the requested synthesis would create a new product/architecture decision rather than summarize one.
