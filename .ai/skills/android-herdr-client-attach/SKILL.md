---
id: android-herdr-client-attach
version: 1.0.0
status: experimental
---

# Android Herdr bounded client attach

## Trigger

Use only after same-device evidence proves the pinned Herdr v0.8.0 foreground server starts, reports compatible protocol, stops cleanly, and required no forced cleanup.

## Inputs

- exact AgentSwitchboard branch/head;
- `herdr-server-start-*.env` with schema `agentswitchboard.android-herdr-server-start.v1`;
- tracked client-attach manifest and upstream source;
- tmux available as canonical fallback.

## Procedure

1. Read `AGENTS.md`, the parent Herdr manifest, and `client-attach/manifest.json`.
2. Run the source-bound review builder. Require `BOUNDED_CLIENT_PROTOCOL_OBSERVER_PROBE_APPROVED_NO_INSTALL`.
3. Keep `BLOCKED_AUTODETECT_DAEMON_RACE` for full-app bare `herdr`.
4. Run focused contract/completeness validation before evidence mode.
5. Evidence mode may start only explicit foreground `herdr server`, use read-only `pane list`, and attach only with `terminal session observe <terminal_id>`.
6. Accept one JSON `terminal.frame`; never save or print decoded terminal bytes.
7. Stop the foreground server, require clean observer/server exits and not-running status, then remove the sandbox.
8. A PASS advances only to `bounded-full-tui-attach-review`. It is not detach/reattach or migration proof.

## Forbidden

- bare `herdr` auto-detect launch;
- persistent installation or detached daemon;
- workspace/tab/pane mutation;
- terminal control, takeover, input or prompts;
- Android process/battery-policy mutation;
- tmux removal.

## Outputs

- source-bound client-attach review;
- sanitized local client-attach evidence;
- exact next gate and proof ceiling.

## Validation

`bash tooling/profiles/android/harness/herdr/client-attach/hooks/Invoke-HerdrClientAttachHarnessPrePush.sh`
