# Start OpenCode through AgentSwitchboard

The normal Windows operator path is intentionally click-first. Do not reconstruct the long `agent-switchboard.cmd -RepoPath ... -Agent opencode ...` invocation by hand.

## First use

1. Run `Setup-AgentSwitchboard.cmd` once if AgentSwitchboard startup readiness does not report OpenCode as adapter-ready.
2. Authenticate OpenCode interactively with the provider you intend to use. Provider credentials stay in the provider/OpenCode surface; do not put them in AgentSwitchboard prompts, state, reports, or Git.
3. Copy the complete bounded sprint prompt to the Windows clipboard.
4. Double-click `Start-AgentSwitchboard-OpenCode.cmd` from a clean, attached AgentSwitchboard checkout.
5. Review the repository, branch, prompt character count, iteration limit, token cap, push state, and launch-evidence path printed before the child sprint starts.
6. After the child returns, inspect the generated GNHF worktree, launcher summary, validation output, commit state, and diff before accepting delivery.

Push remains off by default.

## Target another repository without rebuilding the command

The zero-argument click target is the checkout that contains `Start-AgentSwitchboard-OpenCode.cmd`.

To target another repository without typing the full sprint command, drag that repository folder onto `Start-AgentSwitchboard-OpenCode.cmd`. Windows passes the dropped folder as the first `RepoPath` argument; the sprint prompt still comes from the clipboard.

Advanced automation may pass `-RepoPath`, `-PromptPath`, `-MaxIterations`, `-MaxTokens`, `-StopWhen`, `-PushBranch`, or `-PlanOnly`, but those are implementation controls rather than the normal technician workflow.

## Detached verification worktrees

Exact-head verification worktrees are often detached. They are valid for read-only proof, but they are not valid unattended sprint bases.

The launcher fails before OpenCode or GNHF is started and prints:

```text
Detached HEAD is not a valid sprint base. This is commonly a verification worktree.
```

Use a clean attached checkout instead, or drag that checkout folder onto the CMD launcher. `Start-GnhfSprint.ps1` independently enforces the same boundary and must report `Detached HEAD is not allowed for an unattended sprint.` rather than throwing a null-method exception.

## Evidence and failure recovery

Every click attempt writes a bounded launch summary under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\opencode-click\<run-id>\opencode-click-launch.json
```

The summary records the resolved repo, branch, prompt source and character count, limits, child launcher, child exit code, status, and proof ceiling. It does not copy the raw prompt.

The temporary clipboard prompt file is removed after the child returns or fails. The underlying GNHF sprint writes its own launcher summary and transcript under the normal fleet log root.

The CMD wrapper proves the concrete PowerShell 7 child executable using `scripts/Test-OperatorChildExecutableLaunch.ps1` before starting the repository-owned PowerShell launcher. A discovered but unlaunchable `pwsh.exe` is rejected before sprint work.

The click window pauses at completion so diagnostics do not vanish. Automation can set `AGENT_SWITCHBOARD_NO_PAUSE=1` to suppress the pause.

## Proof ceiling

A green click-launch preflight proves only a clean attached target checkout, local OpenCode adapter readiness, the repo-owned bounded sprint entrypoint, and the concrete PowerShell child boundary. A zero child exit proves only bounded child-process completion. Provider authentication, model response, repository delivery, validation quality, push, merge, deployment, and operator acceptance require their owning runtime and repository evidence.
