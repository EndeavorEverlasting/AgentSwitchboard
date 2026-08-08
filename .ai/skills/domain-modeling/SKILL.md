---
id: domain-modeling
version: 1.0.0
status: canonical
---

# Domain Modeling

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, `skills/engineering/domain-modeling/SKILL.md`, blob `d0f7e1a5ccb06a7184056ff9af02b67bc77f9dda`. Snapshot: `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/domain-modeling/SKILL.md`.

## Trigger

Use when planning/implementation changes ubiquitous language, domain boundaries, or a durable architectural trade-off. Wayfinder grilling invokes this as terms/decisions crystallize.

## Inputs

- nearest `CONTEXT.md`/`CONTEXT-MAP.md` when present;
- applicable ADRs;
- current code/repository evidence;
- human statements/answers that may change the model;
- owned branch/worktree for tracked context edits.

## Procedure

1. Read the nearest domain glossary/map and applicable ADRs.
2. Challenge overloaded/conflicting terms and test them with concrete edge-case scenarios.
3. Cross-check claims about current behavior against code/repository evidence.
4. When a domain term truly settles, update the appropriate `CONTEXT.md` immediately. It remains glossary/domain language, not an implementation spec.
5. Offer an ADR only when the choice is hard to reverse, surprising without context, and the result of a real trade-off.
6. In parallel Wayfinder worktrees, treat domain-context edits as separately owned tracked work; reconcile through normal Git/PR integration before other tickets assume they are shared authority.

## Outputs

- precise domain terminology;
- bounded `CONTEXT.md` updates where terms changed;
- ADR only when all three ADR gates pass;
- decision-ticket links to durable context changes where relevant.

## Deterministic validation

Validate that glossary changes contain domain language rather than transient implementation instructions, ADRs record a genuine trade-off, and concurrent context changes are reconciled before consumption. Wayfinder contract changes run `python tests/test_wayfinder_harness.py` and `scripts/Test-WayfinderHarness.ps1`.

## Forbidden scope

- `CONTEXT.md` as scratchpad/spec;
- speculative terminology presented as settled human decision;
- silent overwrite of another ticket/worktree's domain changes;
- ADR for reversible/unsurprising implementation detail.

## Stop and escalate

Stop when the domain owner has not resolved a terminology conflict, code and stated model contradict without a decision owner, parallel context edits conflict, or an architectural change requires authority/review outside the current ticket.
