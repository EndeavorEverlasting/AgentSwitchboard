# Triggers

Triggers select a reviewed workflow and never grant destructive authority.

## Canonical routing triggers

| Trigger | Evidence | Route |
|---|---|---|
| `environment.capability-request` | any environment, new platform, phone access, cross-device continuity, auto-configure, SSH, remote tmux, Termux, WSL/Linux/Windows ambiguity, or uncertain runtime host | `environment-capability-routing`; classify five layers and select one supported topology before installation, launch, profile, or runtime claims |
| `environment.remote-request` | SSH target, remote repository, remote tmux, or another machine should host or continue work | read-only remote preflight; classify OS/shell, tmux, repository, orchestration, agent/provider, and persistence before mutation |
| `environment.false-equivalence` | repository/package presence is treated as runtime readiness; same-named tmux sessions as one workspace; SSH reachability as shell compatibility; terminal client as runtime host | reject the promotion and repair the owning contract or implementation |
| `plan.coordination-request` | multi-agent, multi-session, multi-wave, cross-PR, sprint-map, launch-pack, or material plan-state request | `public-plan-coordination`; read or update `plans/` and keep coordination distinct from PR delivery |

## Repository-specific trigger routes

`REPLACE_TRIGGER_TABLE`

Always stop or escalate for unowned dirty work, scope collisions, conflicting public-plan ownership, unknown environment topology, lower-role topology mismatch, secrets, unauthorized live-target mutation, destructive Git, deployment, or exhausted repair limits.
