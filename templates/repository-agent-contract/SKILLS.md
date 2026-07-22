# Skills

Canonical skill semantics are pinned from `EndeavorEverlasting/AgentSwitchboard`.

Repository-local skills live under `.ai/skills/<skill-id>/SKILL.md` and must define trigger, inputs, procedure, outputs, validation, forbidden scope, and stop conditions.

## Required coordination skill

| Skill | Purpose | Trigger |
|---|---|---|
| `public-plan-coordination` | Coordinate public machine-readable work across agents, sessions, waves, branches, and PRs | multi-agent, multi-session, sprint-map, launch-pack, or material plan-state request |

The plan coordinates ownership, dependencies, artifacts, proof, and handoff. The branch and pull request deliver and review tracked changes. Product behavior remains in deterministic code and contracts.

## Local catalog

`REPLACE_LOCAL_SKILL_TABLE`
