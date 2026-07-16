# Cost-aware agent and model routing

AgentSwitchboard preserves each available token pool instead of pinning one provider permanently. The route order is:

1. AGY/Anti-Gravity's naturally free token pool;
2. limited-time free OpenCode routes;
3. other free routes, including Gemini CLI and Goose free-provider profiles;
4. paid routes, including direct DeepSeek API, Codex/OpenAI, Claude Code, GitHub Copilot CLI, and future Augment Code adapters.

The tracked policy contains no credentials and never performs provider login. Each agent owns its authentication. AGY is deliberately not assigned a permanent model by AgentSwitchboard; its own default account/session policy consumes AGY's naturally free allowance first.

## Install the router

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Install-AgentModelRouter.ps1 -ResetPolicy

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard-auto.cmd" `
  -ListRoutes
```

The installer normally preserves an existing customized `model-route-policy.json`. Schema version 2 changes the routing order and fallback contract, so review the generated backup and use `-ResetPolicy` once to adopt this policy.

## AGY through GNHF without ACP

AGY 1.1.2 does not expose an `acp` subcommand. Running `agy acp --help` can print AGY's top-level help and still exit successfully, so that command is not proof of ACP compatibility.

AgentSwitchboard instead installs a local **Pi-compatible JSONL bridge**:

```text
GNHF --agent pi
  -> temporary PATH-local pi.cmd shim
  -> Invoke-AgyPiBridge.ps1
  -> agy --mode accept-edits --dangerously-skip-permissions --print <prompt>
```

The shim is visible only to the routed GNHF child process. It does not replace a real Pi installation globally and does not modify `~/.gnhf/config.yml`.

The bridge passes no `--model` argument by default. That is intentional: AGY retains control of its natural free-token behavior rather than being permanently pinned to a model. An operator-local future policy may set an explicit AGY model only when there is a concrete reason to override AGY's default.

## Verify AGY before a routed run

List the models AGY currently knows about, then make a read-only one-shot request using AGY's normal default allocation:

```powershell
agy --version
agy models
agy --mode plan --print "Return exactly this text and nothing else: AGY_FREE_READY"
```

Do not select a permanent model merely to make routing work. The model list is inventory; the one-shot request proves that the current AGY session can answer.

Then install the router and launch a bounded disposable proof:

```powershell
$Prompt = @'
Create agy-gnhf-proof.txt containing exactly:

agent=agy
allocation=natural-free-first
orchestrator=gnhf
status=ready

Validate the exact contents, run git diff --check, commit the file, and stop.
Do not push or modify any other file.
'@

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard-auto.cmd" `
  -RepoPath (Get-Location).Path `
  -Prompt $Prompt `
  -Name "agy-natural-free-proof" `
  -MaxIterations 1 `
  -MaxTokens 60000 `
  -StopWhen "agy-gnhf-proof.txt has exact validated contents and is committed."
```

A successful process start is not sufficient. The proof is green only when GNHF reports a good iteration and the generated branch contains the committed proof file.

## Fallback means quota exhaustion, not preference replacement

The router does not move away from AGY because OpenCode is temporarily free or because another model is available. It switches from AGY only when all of these are true:

1. the AGY bridge classifies the response as `quota-exhausted`;
2. the base repository is still clean and unchanged;
3. no new GNHF branch contains a commit;
4. no new worktree remains for review.

Authentication failures, rate limits, network faults, validation errors, malformed output, and generic agent failures stop the run. They do not authorize a model switch.

After confirmed AGY exhaustion, the next route is OpenCode's limited-time free model. That route still requires a green GNHF compatibility proof because the observed `opencode/deepseek-v4-flash-free` server-session request returned HTTP 400 even though a simple `opencode run` request passed. Gemini and Goose follow, then paid routes.

## DeepSeek pricing windows

The current official DeepSeek pricing page lists flat per-token pricing and does not publish an active time-of-day multiplier. The tracked `deepseek-api` policy is therefore `mode: flat` with no UTC windows.

The router supports a future verified `time-windows` policy. Add such windows only to the operator-local installed policy after checking the official provider page, including a source and verification time. Heavy paid work is deferred inside verified windows unless `-AllowPeakPaid` is explicitly supplied.

## Safety boundary

The router never performs provider authentication, stores credentials, pushes a branch, or silently continues after a route that may have changed files. Augment Code remains inventoried as paid and CLI-only until a native GNHF or ACP adapter is proven.
