---
id: opencode-prompt-handoff
status: canonical
owner: tooling/harness/operational/opencode-prompt-handoff
---

# OpenCode Prompt Handoff

## Trigger

Use this skill when an AgentSwitchboard OpenCode sprint requires a preflight or PlanOnly gate before execution and the prompt originates from the Windows clipboard, a transient chat surface, or another mutable transport.

Also use it when the operator would otherwise need to copy the same bounded prompt twice, when prompt identity across preflight and execution matters, or when a previous run reported `Prompt: clipboard` and then stopped before GNHF execution.

## Inputs

- verified clean attached repository path;
- bounded sprint prompt as a file or one clipboard snapshot;
- sprint name and iteration/token bounds;
- push preference;
- explicit stop condition.

## Preconditions

- Read `AGENTS.md` and the operational harness front door.
- Preserve unrelated dirty work; the delegated OpenCode/GNHF launcher owns its clean-base requirement.
- Do not put passwords, tokens, recovery codes, private keys, or other credentials in the bounded sprint prompt.
- Treat clipboard as an intake path only, never as continuation evidence.

## Procedure

1. Invoke `tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1` instead of running separate clipboard-backed PlanOnly and execution commands.
2. The runner reads the supplied prompt once and materializes `bounded-sprint-prompt.md` outside the repository.
3. Record the SHA-256 digest and character count; do not duplicate raw prompt text into JSON, reports, PR bodies, or CI logs.
4. Run the existing OpenCode launcher in PlanOnly mode with `-PromptPath` bound to that artifact.
5. Require exit code zero and recompute the digest after preflight.
6. If execution was requested, run the existing OpenCode launcher again with the exact same prompt path, bounds, name, and push preference.
7. Recompute the digest after execution and fail closed if it changed.
8. Preserve the run-local prompt, receipt, and report when a gate fails so recovery can retry the exact artifact without recopying.
9. Route product-launcher defects to the product owner. Do not patch product code from this harness lane.

## Outputs

- local untracked `bounded-sprint-prompt.md`;
- local untracked `prompt-handoff-receipt.json`;
- local untracked `prompt-handoff-operator-report.md`;
- downstream OpenCode/GNHF evidence printed by the delegated launcher.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OpenCodePromptHandoffHarness.ps1
python tests/test_opencode_prompt_handoff_harness.py
git diff --check
```

For a real operator run:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1 -RepoPath <repo-path> -PushBranch
```

## Forbidden scope

- Do not mutate `AGENTS.md` or governance policy from this skill.
- Do not modify `Start-AgentSwitchboard-OpenCode.cmd`, `tooling/gnhf/Start-AgentSwitchboardOpenCode.ps1`, or other product behavior from a harness-only sprint.
- Do not ask the operator to copy the same prompt again after a successful materialization step.
- Do not fall back to the current clipboard after the prompt artifact exists.
- Do not track generated prompt/evidence files.
- Do not use destructive Git, force push, or implicit hook installation.
- Do not claim provider/model response, coding quality, push, merge, deployment, or operator acceptance from prompt-continuity evidence.

## Stop and escalate

Stop mutation and name the exact owner when the delegated product launcher fails, provider authentication is required, the repository is dirty/detached, push/PR authority is unavailable, or another writer owns the necessary product fix. Preserve the prompt artifact and receipt so the next owner can continue without reconstructing the prompt.
