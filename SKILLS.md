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
2. A literal request for a **Good Night, Have Fun prompt**, **GNHF prompt**, or to **compile a sprint for Good Night, Have Fun** selects `gnhf-prompt-compilation`. It must not fall through to generic sprint prose.
3. A request to browse, select, show, generate, or render a prompt from the **AI Harness Prompt Kit** selects `prompt-kit-selection`. It must preserve the registry execution surface and does not execute the selected prompt.
4. `TRIGGERS.md` maps repository evidence to a skill.
5. The nearest nested `SKILLS.md` may specialize the catalog for a subtree.
6. When no skill fits, use `repo-intake` to collect evidence and propose a new bounded skill rather than improvising unlimited authority.

## Canonical skills

| Skill | Purpose | Primary triggers |
|---|---|---|
| [`repo-intake`](.ai/skills/repo-intake/SKILL.md) | Recover repository truth and select safe work | new repository, stale context, unknown branch state |
| [`bounded-sprint`](.ai/skills/bounded-sprint/SKILL.md) | Execute one scoped tracked change through commit/PR | explicit implementation request, ranked sprint selected |
| [`gnhf-prompt-compilation`](.ai/skills/gnhf-prompt-compilation/SKILL.md) | Compile one copy-ready bounded `gnhf` PowerShell launch command | “GNHF prompt,” “Good Night, Have Fun prompt,” compile sprint for GNHF |
| [`prompt-kit-selection`](.ai/skills/prompt-kit-selection/SKILL.md) | Search and render the pinned AI Harness Prompt Kit without rewriting its contracts | prompt-kit request, prompt ID, deterministic prompt selection |
| [`evidence-validation`](.ai/skills/evidence-validation/SKILL.md) | Build honest proof and repair validation gaps | failing checks, review findings, proof request |
| [`pr-integration`](.ai/skills/pr-integration/SKILL.md) | Reconcile stacked or parallel branches safely | merge request, stacked PRs, consumed upstream work |
| [`runtime-proof`](.ai/skills/runtime-proof/SKILL.md) | Move from static confidence to observed behavior | launcher, installer, harness, or live-runtime request |

## GNHF artifact distinction

A GNHF prompt is an executable launch command beginning with `gnhf`, including a verified agent, one Git execution mode, iteration and token caps, sleep prevention, a positive observable stop condition, and one quoted bounded objective block.

It is not:

- a sprint map;
- a multi-chat launch pack;
- a plan-only response;
- a generic repo-agent prompt;
- a description of how GNHF works.

The detailed canonical format and validation rules live in `.ai/skills/gnhf-prompt-compilation/SKILL.md`.

The V38 prompt registry records this distinction as `regular_ai_prompt` versus `gnhf_launch_artifact`. Prompt-kit selection must validate the requested surface before returning content.

## Authoring rules

- Skills must be small enough to select unambiguously.
- Skills may reference scripts and validators but must not paste their logic.
- Inputs and outputs should be machine-readable where practical.
- A skill must state what it cannot prove.
- A skill that can mutate live targets, deploy, merge, or access secrets requires an explicit escalation boundary.
- Changes to canonical skills require a version change and validation through `scripts/Test-AgentDocumentationContract.ps1`.
