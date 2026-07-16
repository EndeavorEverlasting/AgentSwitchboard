# Cost-aware agent and model routing

AgentSwitchboard selects the first **GNHF-compatible** route in this order:

1. limited-time free OpenCode routes;
2. other free routes, including AGY/Anti-Gravity, Gemini CLI, and Goose provider profiles;
3. paid routes, including direct DeepSeek API, Codex/OpenAI, Claude Code, GitHub Copilot CLI, and future Augment Code adapters.

The tracked policy contains no credentials and never performs provider login. Each agent owns its own authentication and model selection.

## Install the router

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Install-AgentModelRouter.ps1

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard-auto.cmd" `
  -ListRoutes
```

The installer preserves an existing customized `model-route-policy.json` unless `-ResetPolicy` is explicitly supplied.

## Run free DeepSeek through AGY and GNHF

The OpenCode Zen route `opencode/deepseek-v4-flash-free` is first in policy because it is limited-time free. It still requires a green GNHF compatibility proof: a normal `opencode run` response does not prove the OpenCode server-session and structured-output path used by GNHF.

Until that proof is green, use AGY's free DeepSeek profile through ACP:

```powershell
agy --version
agy acp --help
```

Open AGY once, select its free DeepSeek model in AGY's own model picker, complete AGY's own login if requested, and exit. Then run a bounded disposable proof from a clean Git repository:

```powershell
$Prompt = @'
Create agy-deepseek-gnhf-proof.txt containing exactly:

agent=agy
model=deepseek-free
orchestrator=gnhf
status=ready

Validate the exact contents, run git diff --check, commit the file, and stop.
Do not push or modify any other file.
'@

$Prompt | gnhf `
  --agent "acp:agy acp" `
  --worktree `
  --max-iterations 1 `
  --max-tokens 60000 `
  --prevent-sleep on `
  --stop-when "agy-deepseek-gnhf-proof.txt has exact validated contents and is committed."
```

A successful process start is not sufficient. The proof is green only when GNHF reports one good iteration and the generated branch contains the committed proof file.

If `agy acp --help` fails, AGY is CLI-only on that installation. Keep it available for interactive use, but do not label it GNHF-ready. Gemini remains available through GNHF's ACP registry as `acp:gemini` after Gemini CLI is installed and authenticated.

## DeepSeek pricing windows

The current official DeepSeek pricing page lists flat per-token pricing and does not publish an active time-of-day multiplier. The tracked `deepseek-api` policy is therefore `mode: flat` with no UTC windows.

The router supports a future verified `time-windows` policy. Add such windows only to the operator-local installed policy after checking the official provider page, including a source and verification time. Heavy paid work is deferred inside verified windows unless `-AllowPeakPaid` is explicitly supplied.

## Safety and fallback behavior

The router performs capability and inventory checks before launch. It does **not** automatically start a second agent after a GNHF run has begun or failed, because the first route may have created commits or preserved repair work. Post-run fallback requires operator review of the worktree and logs.

Augment Code is inventoried as paid and CLI-only until a native GNHF or ACP adapter is proven. It is never silently invoked as though it were compatible.
