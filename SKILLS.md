# Skills Catalog

Skills are versioned procedural knowledge for agents. They describe **when** and **how** to perform work. Executable behavior belongs in deterministic code.

Canonical skills live under `.ai/skills/<skill-id>/SKILL.md`.

## Skill contract

Every canonical skill must define:

- skill ID, version, and status;
- trigger conditions;
- required inputs;
- bounded procedure;
- expected outputs and artifacts;
- deterministic validation;
- stop and escalation conditions;
- forbidden scope.

## Lifecycle

- `proposed` — design exists but is not approved for routine use;
- `experimental` — bounded use is allowed with explicit review;
- `canonical` — approved baseline workflow;
- `deprecated` — retained for migration only;
- `retired` — must not be selected.

## Resolution order

1. A task explicitly names a valid skill.
2. `TRIGGERS.md` maps repository evidence to a skill.
3. The nearest nested `SKILLS.md` may specialize the catalog for a subtree.
4. When no skill fits, use `repo-intake` to collect evidence and propose a new bounded skill rather than improvising unlimited authority.

## Canonical skills

| Skill | Purpose | Primary triggers |
|---|---|---|
| [`repo-intake`](.ai/skills/repo-intake/SKILL.md) | Recover repository truth and select safe work | new repository, stale context, unknown branch state |
| [`bounded-sprint`](.ai/skills/bounded-sprint/SKILL.md) | Execute one scoped tracked change through commit/PR | explicit implementation request, ranked sprint selected |
| [`evidence-validation`](.ai/skills/evidence-validation/SKILL.md) | Build honest proof and repair validation gaps | failing checks, review findings, proof request |
| [`pr-integration`](.ai/skills/pr-integration/SKILL.md) | Reconcile stacked or parallel branches safely | merge request, stacked PRs, consumed upstream work |
| [`runtime-proof`](.ai/skills/runtime-proof/SKILL.md) | Move from static confidence to observed behavior | launcher, installer, harness, or live-runtime request |

## Authoring rules

- Skills must be small enough to select unambiguously.
- Skills may reference scripts and validators but must not paste their logic.
- Inputs and outputs should be machine-readable where practical.
- A skill must state what it cannot prove.
- A skill that can mutate live targets, deploy, merge, or access secrets requires an explicit escalation boundary.
- Changes to canonical skills require a version change and validation through `scripts/Test-AgentDocumentationContract.ps1`.
