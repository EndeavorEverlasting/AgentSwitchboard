---
id: gnhf-prompt-compilation
version: 1.1.0
status: canonical
---

# Good Night, Have Fun Launch Artifact Compilation

## Trigger

Use when the repository owner explicitly asks for a **Good Night, Have Fun prompt**, **GNHF prompt**, or asks to **compile a sprint for Good Night, Have Fun**.

This literal trigger takes precedence over generic prompt writing. The requested deliverable is a copy-ready executable launch artifact. It is not an ordinary AI sprint prompt, sprint map, launch pack, plan, or prose-only objective.

## Distinct execution surfaces

Never collapse these surfaces:

1. **Regular AI prompt** — instructions pasted into an interactive coding-agent chat.
2. **GNHF runtime objective** — compact repository objective supplied to GNHF.
3. **GNHF launch artifact** — executable shell content that enters the repository, selects the runtime route, applies bounds, and supplies the runtime objective.

A request for a GNHF prompt means surface 3 unless the owner explicitly asks only for the inner objective.

## Required inputs

- one target repository and expected local path;
- one bounded sprint objective;
- execution domain and shell, normally PowerShell 7 on Windows;
- reviewed agent and model route;
- run profile: `SMOKE`, `NAP`, `OVERNIGHT`, or `EXTENDED`;
- exactly one Git execution mode;
- iteration and token caps;
- positive observable stop condition;
- owned scope, forbidden scope, deliverable, validation, and proof ceiling.

When exact agent launchability is unproven, run a bounded preflight instead of repository work.

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

A repository-owned launcher may derive the root from `$PSScriptRoot`. A CMD launcher must use `cd /d` with a variable-based path. Never hardcode `C:\Users\<username>` or rely on the terminal's inherited directory.

## Provider route contract

GNHF selects an agent adapter. A provider/model is selected inside that adapter or through GNHF's reviewed model option.

For DeepSeek the truthful route is:

```text
operator route: DeepSeek
GNHF adapter:   OpenCode
provider/model: deepseek/<exact-model-id>
```

Never invent `--agent deepseek` as a native GNHF adapter.

When AgentSwitchboard is available, use its provider-routed launcher rather than bypassing preflight:

```powershell
$Launcher = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\GnhfFleet\Start-ProviderRoutedGnhfSprint.ps1"

& $Launcher `
  -RepoPath $RepoPath `
  -PromptPath $PromptPath `
  -Model "deepseek/deepseek-v4-pro" `
  -MaxIterations 8 `
  -MaxTokens 800000 `
  -ProbeTimeoutSeconds 30 `
  -StopWhen "One bounded repair or exact blocker report is committed and the generated worktree is clean."
```

The reviewed provider launcher must verify Windows command-shim dispatch, GNHF model support, the exact model response, and local commit delivery. A failed preflight stops before GNHF; it must not consume three identical GNHF failures.

## Procedure

1. Identify the shell and execution domain.
2. Resolve and enter the repository before all other logic.
3. Verify the exact agent or AgentSwitchboard launch form.
4. Produce one executable launch artifact with bounded controls.
5. Default to worktree isolation and no push.
6. Supply one compact runtime objective, not the full source conversation.
7. Require a tracked local deliverable, normally a commit ahead of the base.
8. Preserve interrupted worktrees, branches, logs, notes, and review commands.
9. Return the copy-ready launch artifact directly.

## Runtime controls

A direct GNHF command requires:

```text
--agent
--model when provider/model selection is required
exactly one of --worktree or --current-branch
--max-iterations
--max-tokens
--prevent-sleep on
--stop-when
```

Profiles:

- `SMOKE`: 1-2 iterations;
- `NAP`: 3-5 iterations;
- `OVERNIGHT`: 6-10 iterations;
- `EXTENDED`: 10-15 iterations.

Never compile an unlimited run. Do not include push unless the owner authorizes it for that exact run.

## Runtime objective contract

The compact objective must contain:

- repository;
- sprint and lane;
- dependencies;
- owned and forbidden scope;
- one narrow objective;
- ordered execution loop;
- repeated no-progress rule;
- tracked deliverable or exact blocker report;
- validation commands;
- commit requirement;
- final report;
- proof ceiling;
- final `git status --short` review.

Run one repository per process. Process exit zero, stop text, or an uncommitted diff is not delivery proof.

## Outputs

- one copy-ready executable launch artifact;
- one compact runtime objective, embedded or referenced;
- explicit directory, route, caps, stop condition, deliverable, validation, proof ceiling, and recovery behavior;
- a preflight result instead of a repository sprint when the route is blocked.

## Deterministic validation

A valid launch artifact must:

- resolve and enter the intended repository before implementation logic;
- use `$HOME`, `$env:LOCALAPPDATA`, `$PSScriptRoot`, `%USERPROFILE%`, or equivalent variables;
- be executable in the stated shell;
- use a reviewed AgentSwitchboard route when provider/model selection is requested;
- use truthful agent/model routing;
- include exactly one Git execution mode;
- include iteration and token caps;
- include a positive stop condition;
- target one repository;
- include owned and forbidden scope in the objective;
- include no-progress and operational-failure handling;
- require a tracked deliverable or exact blocker report;
- include validation and a proof ceiling;
- disable push, merge, deployment, and live mutation by default;
- reject a regular AI prompt or prose-only objective masquerading as the launcher.

## Forbidden scope

- No regular AI prompt substituted for the launch artifact.
- No prose-only substitute.
- No hardcoded workstation username.
- No inherited-directory assumption.
- No unlimited command.
- No missing caps.
- No default push.
- No multiple repositories in one process.
- No fictional DeepSeek GNHF adapter.
- No direct-provider bypass when AgentSwitchboard is the control plane.
- No silent provider fallback.
- No success claim based only on configuration or process exit.

## Stop and escalate

Stop with the smallest exact blocker when the repository, objective, execution domain, or reviewed launch form is missing. Run only preflight when the route is unproven. Preserve evidence when the runtime is blocked.
