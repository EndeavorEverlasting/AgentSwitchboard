# Android Herdr client-attach operator report

- Repository:
- Branch / exact head:
- Stacked base:
- Same-device server evidence:
- Client-attach review:
- Client-attach evidence:
- Decision:
- Migration decision: KEEP_TMUX

## Working

- exact v0.8.0 prebuilt execution identity:
- foreground server start/status/stop:
- read-only client protocol observer handshake/frame:

## Broken or blocked

- full-app bare Herdr TUI remains blocked until separately reviewed because auto-detect can spawn a daemon if the server disappears.

## Missing / unproved

- full-app TUI attach
- detach/reattach
- persistent/background survival
- agent-state detection
- bounded coding-agent sprint
- installation / tmux retirement

## Validation

- focused Python completeness:
- probe contract:
- pre-commit:
- parent Android/Herdr validators:
- PowerShell completeness:
- diff hygiene:

## Proof ceiling

Observer-frame PASS proves only compatible client Hello/Welcome transport plus one read-only terminal frame against an ephemeral foreground server.
