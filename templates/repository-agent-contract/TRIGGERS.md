# Triggers

Triggers select a reviewed workflow and never grant destructive authority.

## Canonical coordination trigger

| Trigger | Evidence | Route |
|---|---|---|
| `plan.coordination-request` | multi-agent, multi-session, multi-wave, cross-PR, sprint-map, launch-pack, or material plan-state request | `public-plan-coordination`; read or update `plans/` and keep coordination distinct from PR delivery |

## Repository-specific trigger routes

`REPLACE_TRIGGER_TABLE`

Always stop or escalate for unowned dirty work, scope collisions, conflicting public-plan ownership, secrets, unauthorized live-target mutation, destructive Git, deployment, or exhausted repair limits.
