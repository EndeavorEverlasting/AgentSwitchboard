# Android Herdr client-attach harness

This tracked harness advances the Android Herdr migration from **foreground server lifecycle proof** to one bounded **read-only client protocol observer** experiment.

## Current authority

The exact-device server proof showed v0.8.0 / protocol 19 running on Termux and stopping without forced cleanup. This harness does not install Herdr and does not replace tmux.

Pinned upstream source gives two materially different client paths:

- bare `herdr` is the full app path, but its auto-detect logic may spawn a detached server if the client socket disappears;
- `herdr terminal session observe <terminal_id>` is a CLI subcommand that connects directly to the existing client socket, performs the real Hello/Welcome handshake, requests read-only terminal observation, and emits JSON `terminal.frame` envelopes.

Therefore only the observer path is approved here. Full-app TUI attach remains `BLOCKED_AUTODETECT_DAEMON_RACE` until separately reviewed.

## One-command workflow

```sh
python tooling/profiles/android/harness/herdr/client-attach/Build-HerdrClientAttachReview.py --write
bash tooling/profiles/android/harness/herdr/client-attach/hooks/Invoke-HerdrClientAttachHarnessPrePush.sh
python tooling/profiles/android/harness/herdr/client-attach/Probe-HerdrClientAttach.py evidence
```

Evidence mode validates the prior same-device server PASS before download or process launch. It re-verifies the exact release asset, starts only a foreground server in isolated HOME/XDG/TMPDIR state, runs `pane list` without mutation, observes one existing `terminal_id`, records only frame metadata, stops the server, and cleans the sandbox.

## Expected PASS

- `SERVER_EVIDENCE_VERIFIED=yes`
- `SERVER_STATUS_RUNNING=yes`
- `DISCOVERY_EXIT_CODE=0`
- `OBSERVER_FRAME_RECEIVED=yes`
- `OBSERVER_FRAME_ENCODING=ansi`
- `OBSERVER_EXIT_CODE=0`
- `STOP_EXIT_CODE=0`
- `POST_STOP_RUNNING=no`
- `SERVER_EXIT_CODE=0`
- `FORCED_CLEANUP=no`
- `CLIENT_PROTOCOL_OBSERVER=PASS`
- `NEXT_GATE=bounded-full-tui-attach-review`

## Known traps

Do not interpret an observer frame as proof of the full app TUI. Do not run bare `herdr` merely because the foreground server was healthy a moment earlier; the upstream auto-detect path has a server-spawn fallback. Do not retain decoded terminal frame bytes in evidence.

## Proof ceiling

A live PASS proves the pinned binary can perform a compatible client Hello/Welcome handshake and deliver one read-only terminal frame over Herdr's client transport on the exact Android/Termux device. It does not prove full TUI attach, detach/reattach, persistence, agent state, Android background survival, coding-agent work, installation, or tmux retirement.
