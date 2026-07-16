# ChatGPT Desktop to GNHF Sprint Runtime

This runtime turns a regular project request and a separately compiled GNHF prompt into bounded, visible local execution:

```text
regular request -> validated compiled prompt -> visible terminal -> existing GNHF launcher -> worktree -> artifact and commit proof
```

ChatGPT Desktop Codex is the initiating agent. The PowerShell launcher does not control the ChatGPT Desktop UI and does not depend on window focus, the clipboard, `SendKeys`, or simulated keystrokes.

## Authority boundaries

- AgentSwitchboard owns the request/result contracts, local route selection, workstation orchestration, GNHF launch, and local runtime evidence.
- Web Excel owns workbook presentation and generated Prompt Kit copies.
- SysAdminSuite owns its repository-specific workflow selection and validation.
- Prompts orchestrate the process; launchers, validators, Git checks, and application code remain the executable authority.

## Canonical entrypoint

The default is plan mode:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Invoke-ChatGPTDesktopGnhfSprint.ps1 `
  -RequestPath .\tooling\gnhf\fixtures\desktop-gnhf-proof.request.md `
  -CompiledPromptPath .\tooling\gnhf\fixtures\desktop-gnhf-proof.compiled.txt `
  -CreateDisposableProofRepo
```

Run the disposable proof only after reviewing the plan:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Invoke-ChatGPTDesktopGnhfSprint.ps1 -RequestPath .\tooling\gnhf\fixtures\desktop-gnhf-proof.request.md -CompiledPromptPath .\tooling\gnhf\fixtures\desktop-gnhf-proof.compiled.txt -CreateDisposableProofRepo -Run
```

`Run-ChatGPTDesktopGnhfSprint.cmd` exposes the same parameters for a double-click or Command Prompt workflow and preserves the PowerShell exit code.

The entrypoint requires a clean, attached target base. `-TargetRepo` selects an existing repository. `-CreateDisposableProofRepo` instead creates an evidence-local Git repository with no remote; the two options are mutually exclusive.

## Runtime composition

The launcher reuses two existing AgentSwitchboard authorities:

1. `tooling/wsl/Start-TmuxGnhfWorkspaceSetup.ps1 -Mode Plan` checks the existing Windows, WSL Ubuntu, WezTerm, tmux, Node, GNHF, OpenCode, and adapter configuration without replacing healthy or unmanaged setup.
2. `tooling/gnhf/Start-GnhfSprint.ps1` performs the bounded GNHF worktree launch, route readiness check, iteration/token caps, sleep-prevention setting, and commit-proof gate.

The desktop runtime does not install a second workstation stack, authenticate providers, read credentials, merge, deploy, or enable push for a disposable proof. Provider authentication remains an operator-owned action.

## Visible prompt and local evidence

The full rendered prompt is printed between `COMPILED GNHF PROMPT (EXACT)` markers before the GNHF start acknowledgement. A hash, filename, or summary is not accepted as prompt-emission proof.

Every run writes beneath `%LOCALAPPDATA%\AgentSwitchboard\GnhfDesktop\<run-id>\`:

```text
regular-request.txt
compiled-gnhf-prompt.txt
prompt-validation.json
terminal-transcript.txt
launch-result.json
worktree-proof.json
validation-summary.json
operator-handoff.txt
```

`%LOCALAPPDATA%\AgentSwitchboard\GnhfDesktop\latest-run.txt` points the root CMD launcher to the exact evidence directory after a failure. Evidence is outside the checkout and is not committed.

## Success gate and proof ceiling

A zero process exit is insufficient. Runtime success additionally requires:

- one new or advanced `gnhf/*` branch;
- a commit ahead of the base with the exact compiled commit message;
- exactly the declared artifact paths in the base-to-branch diff;
- the proof nonce in every required artifact;
- the exact worktree path and a clean worktree;
- a clean disposable base and unchanged AgentSwitchboard source checkout.

Failed worktrees remain available for review. A quota, rate-limit, or route-spawn failure is recorded as a blocker rather than retried indefinitely.

The highest proof is one observed ChatGPT Desktop-initiated local run on the current workstation. It does not prove every provider, future quota, model quality, unattended overnight completion, production deployment, or operator acceptance.
