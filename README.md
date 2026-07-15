# AgentSwitchboard

AgentSwitchboard owns coding-agent installation and resolution across
`windows-native`, `windows-wsl`, and `linux-native` execution domains.

The v2 API reports installation domain, selected native/bridge backend, wrapper
type, command-path class, version, authentication readiness, bounded command
smoke, and action-required state. It never authenticates automatically or calls
a hosted provider in fixture mode.

```bash
python -m agentswitchboard fixtures/requests/v2-native.json --pretty
bash tooling/wsl/scripts/install-agent-wrappers.sh
```

Installed wrapper names are `opencode`, `opencode_native`, `opencode_win`, and
the equivalent AGY and Goose names. Canonical wrappers prefer a genuine native
executable, exclude their own managed directory to prevent loops, and use an
explicit Windows bridge only when `AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=1`.

See `docs/workstation/MULTIDOMAIN_CONVERGENCE.md` for preserved PR ownership and
the proof ceiling.
