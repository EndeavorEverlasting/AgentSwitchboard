---
id: gnhf-prompt-compilation
version: 1.3.0
status: canonical
---

# Good Night, Have Fun Launch Artifact Compilation

## Trigger

Use when the repository owner explicitly asks for a **Good Night, Have Fun prompt**, **GNHF prompt**, or asks to **compile a sprint for Good Night, Have Fun**.

This literal trigger takes precedence over generic prompt writing. The requested deliverable is a copy-ready executable launch artifact. It is not a sprint map, launch pack, plan, or ordinary AI prompt.

## Inputs

- one target repository and expected local path;
- one bounded sprint objective;
- execution domain and shell, normally PowerShell 7 on Windows;
- reviewed agent and model route;
- run profile: `TEST`, `SMOKE`, `NAP`, `OVERNIGHT`, or `EXTENDED`;
- exactly one Git execution mode;
- iteration and token caps;
- wall-clock and per-iteration time caps for test-only work;
- positive, observable stop condition;
- owned scope, forbidden scope, deliverable, validation, and proof ceiling.

When exact agent launchability is unproven, run a bounded preflight instead of repository work.

## Execution-surface contract

Never collapse these surfaces:

1. **Regular AI prompt** — instructions pasted into an interactive coding-agent chat.
2. **GNHF runtime objective** — compact repository objective supplied to GNHF.
3. **GNHF launch artifact** — executable shell content that enters the repository, selects the runtime route, applies bounds, and supplies the runtime objective.

A literal request for a GNHF prompt means surface 3 unless the owner explicitly requests only the inner objective.

## Directory-first contract

Every PowerShell launch artifact must resolve and enter the intended repository before Git, installation, validation, provider, or GNHF logic.

```powershell
$DevRoot = Join-Path $HOME "Desktop\dev"
$RepoPath = Join-Path $DevRoot "xyz_repo_directory"

if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "Repository directory not found: $RepoPath"
}

Set-Location -LiteralPath $RepoPath
```

A repository-owned launcher may derive the root from `$PSScriptRoot`. A CMD launcher must use `cd /d` with a variable-based path. Never hardcode a workstation username or rely on the inherited current directory.

## Provider route contract

GNHF selects an agent adapter. Provider/model selection belongs to that adapter (OpenCode) or another proven surface. Do not invent GNHF CLI flags or npm package versions.

For DeepSeek the truthful route is:

```text
operator route: DeepSeek
GNHF adapter:   OpenCode
provider/model: deepseek/<exact-model-id> via OpenCode
control plane:  AgentSwitchboard installed capability document
```

Never invent `--agent deepseek` as a native GNHF adapter. Never require `gnhf --model` unless the exact installed GNHF binary independently exposes that flag. Never treat an unpublished source `package.json` version as an npm publication fact.

When AgentSwitchboard is available, use its provider-routed launcher rather than bypassing preflight:

```powershell
$Capability = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\GnhfFleet\gnhf-runtime-capability.json"
$Launcher = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\GnhfFleet\Start-ProviderRoutedGnhfSprint.ps1"

if (-not (Test-Path -LiteralPath $Capability -PathType Leaf)) {
    throw "Provider-route capability document missing. Repair AgentSwitchboard with Repair-ProviderRoutedGnhf.cmd first."
}

& $Launcher `
  -RepoPath $RepoPath `
  -PromptPath $PromptPath `
  -Model "deepseek/deepseek-v4-pro" `
  -MaxIterations 8 `
  -MaxTokens 800000 `
  -ProbeTimeoutSeconds 30 `
  -StopWhen "One bounded repair or exact blocker report is committed and the generated worktree is clean."
```

The reviewed provider launcher must verify Windows command-shim dispatch, the installed capability document, OpenCode model selection (`OPENCODE_CONFIG_CONTENT` and a bounded `opencode run --model` marker), and local commit delivery. A failed preflight stops before GNHF; it must not consume three identical GNHF failures. Process exit zero with zero new commits is not delivery.

## Test-only timing contract

A `TEST`, smoke check, provider probe, fixture, or contract-only GNHF launch must be bounded to **30 seconds wall clock** and **30 seconds per iteration**. Use one iteration by default.

When the installed GNHF binary cannot enforce both time bounds, the launch artifact must use a repository-owned wrapper that terminates the full process tree at 30 seconds and records timeout evidence. Token and iteration-count caps do not replace time bounds. A test-only launch that can run longer than 30 seconds is invalid.

## DeepSeek rate-window contract

Before selecting DeepSeek, load the verified operator schedule from `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\deepseek-usage-windows.json` or the repository-reviewed platform equivalent.

DeepSeek is eligible only during a verified `standard` or `discounted` rate class with an effective multiplier no greater than `1.0`. Block `double-usage`, premium-multiplier, missing, expired, unverified, or stale schedules. **An unknown or stale schedule state blocks DeepSeek.** Do not infer current operating hours from remembered or historical promotions.

The schedule gate controls launch eligibility. It does not authenticate the provider, inspect credential values, or prove model availability.

## Procedure

1. Identify the shell and execution domain.
2. Resolve and enter the repository before all other logic.
3. Verify the exact agent or AgentSwitchboard launch form.
4. Apply the DeepSeek rate-window gate before a DeepSeek provider probe or sprint.
5. Apply 30-second wall-clock and per-iteration limits before test-only work.
6. Produce one executable launch artifact with bounded controls.
7. Default to `--worktree` isolation and no push.
8. Supply one compact runtime objective, not the full source conversation.
9. Require a tracked local deliverable, normally a commit ahead of the base.
10. Preserve interrupted worktrees, branches, logs, notes, and review commands.
11. Return the copy-ready launch artifact directly.

Canonical command shape:

```powershell
gnhf `
  --agent opencode `
  --worktree `
  --max-iterations 8 `
  --max-tokens 800000 `
  --prevent-sleep on `
  --stop-when "One bounded repair or exact blocker report is committed and the worktree is clean." `
  "Repo: EndeavorEverlasting/example

Sprint: one bounded repair
Lane: one implementation lane

Owned scope:
- the smallest files required for the repair

Forbidden scope:
- push, merge, deployment, and unrelated work

Objective:
Repair one evidence-backed root cause, validate it, commit it, and stop."
```

Use the direct canonical shape only when no reviewed provider route is required. Provider-backed runs use AgentSwitchboard's provider-routed launcher.

Run one repository per GNHF process.

## Runtime objective contract

The compact objective must contain repository, sprint, lane, dependencies, owned and forbidden scope, one narrow objective, ordered execution loop, repeated no-progress handling, tracked deliverable or exact blocker report, validation, commit requirement, final report, proof ceiling, and final `git status --short` review.

Process exit code zero alone is not delivery proof. Stop text and an uncommitted diff are also insufficient.

## Outputs

- one copy-ready executable launch artifact;
- one compact runtime objective, embedded or referenced;
- explicit directory, route, time and usage gates, caps, stop condition, deliverable, validation, proof ceiling, and recovery behavior;
- a preflight result instead of repository work when the route is blocked.

## Deterministic validation

A valid launch artifact must:

- resolve and enter the repository before implementation logic;
- use variable-based paths;
- be executable in the stated shell;
- use a reviewed AgentSwitchboard route when provider/model selection is requested;
- use truthful agent/model routing;
- include exactly one Git execution mode;
- include `--agent`, `--worktree`, `--max-iterations`, `--max-tokens`, `--prevent-sleep on`, and `--stop-when` in a direct GNHF shape;
- include a positive, observable stop condition;
- target one repository;
- include owned and forbidden scope;
- include no-progress and operational-failure handling;
- require a tracked deliverable or exact blocker report;
- include validation and a proof ceiling;
- enforce 30-second wall-clock and per-iteration limits for test-only runs;
- reject DeepSeek when the verified rate class is not standard or discounted;
- disable push, merge, deployment, and live mutation by default;
- reject a regular AI prompt or prose-only objective masquerading as the launcher.

## Forbidden scope

- No regular AI prompt substituted for the launch artifact.
- No prose-only substitute.
- No hardcoded workstation username.
- No inherited-directory assumption.
- No unlimited command or missing caps.
- No test-only GNHF run over 30 seconds.
- No DeepSeek launch during double-usage or unknown schedule state.
- No default push.
- No multiple repositories in one process.
- No fictional DeepSeek GNHF adapter.
- No invented GNHF `--model` requirement or unpublished npm version pin.
- No direct-provider bypass when AgentSwitchboard is the control plane.
- No silent provider fallback.
- No success claim based only on configuration, provider marker, or process exit.

## Stop and escalate

Stop with the smallest exact blocker when the repository, objective, execution domain, reviewed launch form, required test timeout, or verified DeepSeek schedule is missing. Run only preflight when the route is unproven. Preserve evidence when the runtime is blocked.
