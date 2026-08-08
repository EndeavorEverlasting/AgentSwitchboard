# OpenCode Prompt Handoff Harness

## Purpose

This harness closes the operator gap between an AgentSwitchboard OpenCode preflight and the real bounded sprint. A preflight that reads the Windows clipboard and then exits does not bind a later execution to the same prompt. The clipboard can change while the operator moves between tmux, PowerShell, chat, or another application.

The harness therefore makes the prompt a durable local artifact before preflight. Preflight and execution both receive the same `-PromptPath`, and the harness records the same SHA-256 digest before, between, and after those gates.

## Field failure this prevents

A real operator run on 2026-08-08 showed:

- a clean `main` checkout;
- OpenCode adapter readiness;
- a 7094-character prompt sourced from the clipboard;
- `PlanOnly` success;
- the explicit message that no GNHF or provider process was started.

That preflight was useful as launch-surface validation, but it did not create a stable continuation contract. Requiring the operator to place the prompt back on the clipboard before the next invocation was brittle and unnecessary.

## Canonical operator command

From a PowerShell 7 shell in any location:

```powershell
$Repo = "$env:USERPROFILE\dev\AgentSwitchBoard-Live"
pwsh -NoLogo -NoProfile -File "$Repo\tooling\harness\operational\opencode-prompt-handoff\Invoke-OpenCodePromptHandoff.ps1" `
    -RepoPath $Repo `
    -Name 'tmux-verification-self-repair' `
    -MaxIterations 10 `
    -MaxTokens 600000 `
    -PushBranch
```

If `-PromptPath` is omitted, the wrapper snapshots the clipboard once at startup. Nothing later in that invocation reads the clipboard again.

To start from an existing prompt file instead:

```powershell
pwsh -NoLogo -NoProfile -File "$Repo\tooling\harness\operational\opencode-prompt-handoff\Invoke-OpenCodePromptHandoff.ps1" `
    -RepoPath $Repo `
    -PromptPath 'C:\path\to\bounded-sprint.md' `
    -PushBranch
```

## What the runner does

1. Resolves the repository-owned OpenCode PowerShell launcher.
2. Reads the prompt once from a supplied file or from one clipboard snapshot.
3. Writes a run-local `bounded-sprint-prompt.md` outside the repository.
4. Computes SHA-256 and character count.
5. Runs the existing OpenCode launcher with `-PlanOnly -PromptPath <materialized file>`.
6. Stops on any nonzero preflight result.
7. Recomputes the prompt digest and refuses execution if it changed.
8. Runs the existing OpenCode launcher again with the same `-PromptPath` unless `-PreflightOnly` was explicitly requested.
9. Recomputes the digest again and writes a receipt/report.

The wrapper does not replace GNHF, OpenCode, worktree isolation, push policy, or product launch behavior. It composes those existing owners safely.

## Artifacts

Default local evidence root:

```text
%LOCALAPPDATA%\AgentSwitchboard\prompt-handoff\runs\<run-id>\
```

Files:

- `bounded-sprint-prompt.md` — raw prompt used by both gates; local and untracked;
- `prompt-handoff-receipt.json` — digest, source class, gate status, and exit codes; no raw prompt;
- `prompt-handoff-operator-report.md` — human-readable rendering; no raw prompt.

Do not commit the run directory. If the prompt contains private operational context, delete the run directory after the sprint is accepted and no retry is needed. Never put credentials or recovery material in the prompt.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodePromptHandoffHarness.ps1
python tests/test_opencode_prompt_handoff_harness.py
git diff --check
```

Optional hooks are tracked helpers only; they are never installed implicitly:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPreCommit.ps1
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPrePush.ps1 -BaseRef origin/main
```

## Failure handling

If preflight fails, keep the run directory and repair the first failing owner. Do not copy the prompt again and do not launch against the current clipboard. If execution fails, the same prompt artifact and digest identify the exact prompt that crossed both gates.

A product-launcher defect is outside this harness-only sprint. Preserve the receipt and route the defect to the product owner rather than weakening the harness.

## Proof ceiling

This harness proves deterministic prompt materialization, prompt digest continuity, preflight-before-execution ordering, component registration, and static/hosted harness contracts. It does not prove provider authentication, model response, coding quality, branch push, pull-request integration, merge, deployment, or operator acceptance.
