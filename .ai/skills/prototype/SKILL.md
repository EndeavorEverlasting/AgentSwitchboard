---
id: prototype
version: 1.0.0
status: experimental
---

# Prototype

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, `skills/engineering/prototype/SKILL.md`, blob `094571156140f5993cce8557dc31383c82817f3e`.

Exact imported source and referenced procedure companions:

- `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/SKILL.md`
- `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/LOGIC.md`
- `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/prototype/UI.md`

## Trigger

Use when prose is too low-fidelity to decide how something should look or behave. `wayfinder:prototype` is HITL and cannot resolve without a real human reaction/verdict.

## Inputs

- one explicit decision question;
- relevant existing code/runtime conventions;
- safe throwaway branch/evidence surface;
- exact run method;
- human reviewer/decision-maker availability.

## Procedure

1. Bind the prototype to one question.
2. Classify the uncertainty before building:
   - logic/state/data-shape uncertainty follows the donor `prototype/LOGIC.md` procedure: isolate liftable pure logic and expose state plus guided edge-case scenarios in a trivial shareable demo;
   - visual/layout/information-hierarchy uncertainty follows the donor `prototype/UI.md` procedure: prefer the real host surface, create structurally different variants, and make the active variant explicit/shareable.
3. Choose the cheapest concrete artifact that can answer the question, reusing project tooling rather than inventing infrastructure.
4. Mark it unmistakably throwaway and keep it outside production authority.
5. Make it trivial to run; avoid persistence unless persistence is the question; skip unrelated abstractions/polish.
6. Surface relevant state/variant after actions so behavior is inspectable rather than inferred.
7. Preserve prototype source on an isolated throwaway branch or equivalent non-main evidence surface and link it from the decision ticket.
8. Present the artifact to the human and capture their observed verdict. Running successfully is not approval.
9. Record the validated decision separately; later production code implements that decision through normal sprint/test/review gates.

## Outputs

- runnable throwaway artifact;
- exact run command;
- source branch/commit pointer;
- observed human verdict tied to the question;
- Wayfinder resolution/context pointer when applicable.

## Deterministic validation

A Wayfinder prototype ticket requires an artifact pointer, `prototype` invocation evidence, at least one human response, and `humanVerdictObserved=true`. The pinned donor snapshot must contain `prototype/LOGIC.md` and `prototype/UI.md`. Run `python tests/test_wayfinder_harness.py` and `pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderHarness.ps1` when this skill changes.

## Forbidden scope

- production promotion by copy/paste without a separate implementation sprint/tests;
- fake or inferred human approval;
- prototype without a precise decision question;
- broad framework/infrastructure work unrelated to answering the question;
- secrets/live production data in prototype artifacts.

## Stop and escalate

Stop if the prototype cannot be run safely, the question changes, the artifact has accidentally become production-critical, human verdict is unavailable, or the next step is implementation rather than decision validation.
