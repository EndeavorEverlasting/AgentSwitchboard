# Skills

Canonical skill semantics are pinned from `EndeavorEverlasting/AgentSwitchboard`.

Repository-local skills live under `.ai/skills/<skill-id>/SKILL.md` and must define trigger, inputs, procedure, outputs, validation, forbidden scope, and stop conditions.

## Required canonical skills

| Skill | Purpose | Trigger |
|---|---|---|
| `environment-capability-routing` | Separate frontend, transport, workspace host, orchestration runtime, and agent runtime; select one supported topology and role ceiling before mutation | any environment, new platform, phone access, cross-device continuity, auto-configure, SSH, remote tmux, Termux, WSL/Linux/Windows ambiguity |
| `public-plan-coordination` | Coordinate public machine-readable work across agents, sessions, waves, branches, and PRs | multi-agent, multi-session, sprint-map, launch-pack, or material plan-state request |

Environment classification precedes platform installation, launch, profile, and end-to-end runtime work. A lower-role topology must not be silently substituted for the requested outcome.

The plan coordinates ownership, dependencies, artifacts, proof, and handoff. The branch and pull request deliver and review tracked changes. Product behavior remains in deterministic code and contracts.

## Local catalog

`REPLACE_LOCAL_SKILL_TABLE`
