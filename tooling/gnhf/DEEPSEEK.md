# DeepSeek-first GNHF routing

AgentSwitchboard exposes `deepseek` as an operator-facing route while keeping the underlying GNHF adapter truthful:

```text
operator route: deepseek
gnhf adapter:   opencode
provider/model: deepseek/<model-id>
```

GNHF does not have a native `deepseek` adapter. OpenCode is the coding agent; DeepSeek is the provider/model selected inside OpenCode.

## One-time provider setup

Use OpenCode's interactive provider flow. Do not place provider keys in this repository, prompts, fleet manifests, setup summaries, or command history.

```powershell
opencode
```

Inside OpenCode:

1. Run `/connect`.
2. Select `deepseek`.
3. Enter the DeepSeek API key in OpenCode's provider flow.
4. Run `/models` and select the intended DeepSeek model.

OpenCode `1.14.24` or newer is required by the AgentSwitchboard route.

## Readiness

Refresh the installed fleet, then list agents:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Setup-AgentSwitchboard.ps1 `
  -InstallOpenCodeAndCopilot

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

`deepseek READY` means the OpenCode adapter is ready. It does not claim provider authentication. The exact provider/model is proven at launch.

## Launch contract

A DeepSeek launch performs these checks before GNHF receives the repository prompt:

1. Resolve the exact OpenCode command recorded by AgentSwitchboard.
2. Require OpenCode `1.14.24` or newer.
3. Run `opencode models deepseek` and require the exact `provider/model` ID.
4. Start a bounded, 20-second `opencode run --model ...` probe in a temporary directory.
5. Require the positive marker `AGENT_SWITCHBOARD_MODEL_READY`.
6. Set an in-process `OPENCODE_CONFIG_CONTENT` model override for the GNHF child only.
7. Restore the prior inline configuration after the run.

Authentication, quota, network, model discovery, timeout, or marker failures stop before the repository sprint starts.

## AxTask overnight example

Run from a clean AxTask checkout after the AxTask prompt artifact is present:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" `
  -RepoPath (Get-Location).Path `
  -Agent deepseek `
  -DeepSeekModel "deepseek/deepseek-v4-pro" `
  -PromptPath (Join-Path (Get-Location).Path "docs\ops\gnhf\axtask-night-sprint.md") `
  -Name "axtask-deepseek-night" `
  -MaxIterations 8 `
  -MaxTokens 800000 `
  -ProbeTimeoutSeconds 20 `
  -StopWhen "One non-colliding AxTask failure cluster is repaired and committed with targeted validation plus the night report, or a committed evidence-backed blocker report proves why no safe patch can be made."
```

Push remains off by default. Review the isolated GNHF worktree and launcher summary before any push, PR, merge, deployment, or live operation.

## Evidence

The launcher summary records:

- requested agent and resolved GNHF adapter;
- pinned provider/model route;
- OpenCode command and version;
- spawnability success marker and timeout;
- base branch and recent commits;
- iteration and token caps;
- exit code and transcript path.

A successful spawn probe proves only that the selected OpenCode model responded in the local execution domain. It does not prove that repository work, tests, push, merge, deployment, or live behavior succeeded.
