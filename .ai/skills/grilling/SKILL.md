---
id: grilling
version: 1.0.0
status: canonical
---

# Grilling

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, `skills/productivity/grilling/SKILL.md`, blob `95bd01ee9049a7e08120d54af9cd6ceeef282335`. Snapshot: `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/grilling/SKILL.md`.

## Trigger

Use to stress-test a destination, plan, or decision through human-owned answers. `wayfinder:grilling` always pairs this skill with `domain-modeling`.

## Inputs

- decision/topic to resolve;
- settled prerequisites and unresolved branches;
- available repository/tool evidence;
- human decision-maker;
- Wayfinder ticket/map pointer when applicable.

## Procedure

1. Build a dependency-aware design tree.
2. Compute the current question frontier: decisions whose prerequisites are settled.
3. Resolve discoverable facts with tools/research instead of asking the human to perform lookup work.
4. Ask only frontier questions. Give a recommended answer and evidence/rationale, clearly separated from the human's choice.
5. Wait for the human's actual answer before marking a decision settled.
6. Recompute the frontier after each answer bundle until the in-scope tree is clear or the human stops.
7. In Wayfinder, record the ticket answer only from observed human input; the map receives a linked gist, never a duplicate transcript.

## Outputs

- observed human decision answers;
- newly exposed dependent questions/fog;
- domain-model updates through `domain-modeling` where terms/trade-offs settle;
- Wayfinder resolution/context pointer when applicable.

## Deterministic validation

A Wayfinder grilling ticket requires both `grilling` and `domain-modeling` invocation evidence plus at least one relevant human response. Agent-only recommendations fail. Run `python tests/test_wayfinder_harness.py` and `scripts/Test-WayfinderHarness.ps1` when this skill changes.

## Forbidden scope

- self-answering the human side;
- implementation merely because a recommendation emerged;
- asking the human for facts available to safe tools;
- hidden assumptions marked settled;
- inferring consent from silence or lack of objection.

## Stop and escalate

Stop when a prerequisite fact is unavailable, a decision belongs to a different authorized human, the user pauses/refuses the interview, scope crosses a forbidden boundary, or the next work is implementation rather than decision-making.
