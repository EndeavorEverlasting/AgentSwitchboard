# Triggers

Triggers select a reviewed workflow and never grant destructive authority.

## Repository-specific trigger routes

`REPLACE_TRIGGER_TABLE`

Always stop or escalate for unowned dirty work, scope collisions, secrets, unauthorized live-target mutation, destructive Git, deployment, or exhausted repair limits.
