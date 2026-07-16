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

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard-auto.ps1" `
  -ListRoutes
```

The installer normally preserves an existing customized `model-route-policy.json`. Schema version 2 changes the routing order and fallback contract, so review the generated backup and use `-ResetPolicy` once to adopt this policy.

Use `agent-switchboard-auto.ps1` from PowerShell when passing `-Prompt`, especially for multiline prompt text. The `.cmd` launcher is retained for double-click, `-ListRoutes`, and `-PromptPath` workflows; Windows command-shell argument flattening can consume arguments that follow a multiline `-Prompt` value.

## AGY through GNHF without ACP

AGY 1.1.2 does not expose an `acp` subcommand. Running `agy acp --help` can print AGY's top-level help and still exit successfully, so that command is not proof of ACP compatibility.

AgentSwitchboard instead installs a local **Pi-compatible JSONL bridge**:

```text
GNHF --agent pi
  -> temporary PATH-local pi.cmd shim
  -> Invoke-AgyPiBridge.ps1
  -> agy --mode accept-edits --dangerously-skip-permissions --print <prompt>
```

The shim is visible only to the routed GNHF child process. It does not require Pi to be installed, does not replace a real Pi installation globally, and does not modify `~/.gnhf/config.yml`. GNHF displays `pi` because its native Pi adapter is the compatibility surface; the subprocess behind that surface is AGY.

The bridge passes no `--model` argument by default. That is intentional: AGY retains control of its natural free-token behavior rather than being permanently pinned to a model.

## Fail-fast quota detection

Before opening GNHF, the sprint launcher performs one tiny read-only AGY plan-mode request. When AGY returns an explicit message such as `Individual quota reached`, the launcher records `quota-exhausted` and exits before GNHF can retry the same failed prompt.

The launch decision is an explicit Boolean gate and does not reuse a process exit code as control state. Preflight classifications use stable launcher exit codes: 75 for quota exhaustion, 76 for rate limiting, 77 for authentication required, and 78 for an unclassified agent response. This prevents an AGY exit code of 1 from being mistaken for "GNHF has not run yet."

The router then verifies that:

1. the base repository remains clean and at the same commit;
2. no new GNHF branch contains a commit;
3. no new worktree remains for review.

Only after those checks does it continue to the next route. Authentication failures, rate limits, network faults, validation errors, malformed output, and generic agent failures stop the run.

Run the deterministic Windows regression proof with:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\tests\Test-GnhfFailFastRuntime.ps1
```

The test uses temporary repositories and fake commands. It proves a quota response that exits 1 does not invoke GNHF or create a GNHF branch/worktree, then proves fallback occurs after the no-mutation gate and is accepted only with a commit ahead of the base.

## Run a bounded routed proof

```powershell
$Prompt = @'
Create routed-gnhf-proof.txt containing exactly:

router=agentswitchboard
orchestrator=gnhf
fallback=quota-only
status=ready

Validate the exact contents, run git diff --check, commit the file, and stop.
Do not push or modify any other file.
'@

& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard-auto.ps1" `
  -RepoPath (Get-Location).Path `
  -Prompt $Prompt `
  -Name "quota-preserving-proof" `
  -MaxIterations 1 `
  -MaxTokens 60000 `
  -StopWhen "routed-gnhf-proof.txt has exact validated contents and is committed."
```

A successful process start is not sufficient. The proof is green only when GNHF reports a good iteration and a generated GNHF branch contains a commit ahead of the base commit.

## Exit code is not success proof

GNHF 0.1.41 can print a stopped or aborted run and still return process exit code 0. AgentSwitchboard therefore requires commit proof. Exit code 0 without a new GNHF branch commit is converted into a failed route and cannot be reported as completed.

The token numbers shown during an AGY quota failure are bridge estimates based on prompt length. They are not proof that AGY accepted or billed those tokens; an explicit quota rejection with zero model output occurs before useful inference.

## OpenCode free route

After confirmed AGY exhaustion, the next route is OpenCode's limited-time free model. That route still requires a green GNHF compatibility proof because the observed `opencode/deepseek-v4-flash-free` server-session request returned HTTP 400 even though a simple `opencode run` request passed. Gemini and Goose follow, then paid routes.

## DeepSeek pricing windows

The current official DeepSeek pricing page lists flat per-token pricing and does not publish an active time-of-day multiplier. The tracked `deepseek-api` policy is therefore `mode: flat` with no UTC windows.

The router supports a future verified `time-windows` policy. Add windows only in the operator-local installed policy after checking the official provider page and recording the source and verification time. Heavy paid work is deferred inside verified windows unless `-AllowPeakPaid` is explicitly supplied.

## Safety boundary

The router never performs provider authentication, stores credentials, pushes a branch, or silently continues after a route that may have changed files. Augment Code remains inventoried as paid and CLI-only until a native GNHF or ACP adapter is proven.
