# Agent startup readiness

Start AgentSwitchboard from the repository root with:

```text
AgentSwitchboard.cmd
```

With no arguments, the launcher performs read-only orientation:

- reads the local fleet `state.json` when present;
- lists OpenCode, DeepSeek, Goose, Anti-Gravity, Copilot CLI, and Hermes;
- separates local adapter readiness from provider configuration;
- gives bounded next steps for blocked or unconfigured entries;
- writes local JSON and English reports under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports\startup`;
- does not install tools, authenticate providers, contact a hosted model, mutate a repository, push, merge, or deploy.

## OpenCode operator path

When OpenCode is adapter-ready, the normal Windows workflow is click-first:

1. copy the complete bounded sprint prompt to the Windows clipboard;
2. double-click `Start-AgentSwitchboard-OpenCode.cmd`;
3. review the repo, branch, limits, push state, and evidence path printed before launch;
4. inspect the generated GNHF worktree and validation evidence before accepting delivery.

Do not reconstruct the long `agent-switchboard.cmd -RepoPath ... -Agent opencode ...` command for routine use. To target another repository without rebuilding that command, drag the repository folder onto `Start-AgentSwitchboard-OpenCode.cmd`. See [`opencode-click-launcher.md`](opencode-click-launcher.md).

When advanced bounded sprint arguments are explicitly supplied to `AgentSwitchboard.cmd`, it continues to delegate to the existing `Start-AgentSwitchboard.ps1` authority for automation and non-OpenCode lanes.

## Status meanings

- `adapter-ready` — the local command and required adapter interface were recorded as ready.
- `verification-required` — the truthful local adapter exists, but authentication, model availability, quota, or hosted response was not probed at startup.
- `blocked` — the recorded command or interface is missing or unhealthy.
- `not-configured` — no local fleet state exists.
- `unknown` — state exists but lacks the expected record.

## Proof boundary

Startup readiness is local command and adapter evidence only. Provider authentication and hosted behavior remain bounded launch-time proof.
