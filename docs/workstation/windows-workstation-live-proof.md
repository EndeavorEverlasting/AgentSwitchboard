# Windows Workstation Deployment and Live Runtime Proof

This lane bridges the last gap between a repository-defined workstation and an **observed, reusable automation surface**. It deploys or reuses the Windows → WezTerm → WSL → tmux → OpenCode → GNHF chain, then proves it with disposable state.

## One-click deployment and proof

From a clean checkout of the runtime-proof branch, double-click:

```text
Run-WindowsWorkstationLiveProof.cmd
```

The launcher performs two phases:

1. calls the existing repository-owned `Setup-TmuxGnhfWorkspace.cmd apply` flow to install or reuse PowerShell 7, WSL Ubuntu, WezTerm, tmux, Node, OpenCode, and GNHF;
2. installs and runs the focus-independent runtime proof lane.

The setup remains resumable. It may return exit code `30` when Windows needs a reboot, Ubuntu needs first-run initialization, or the same setup must be resumed. Complete that step and double-click the same CMD again.

## Reboot and resume

A reboot requirement is not treated as failure and does not lower the safety gate. The root CMD exits with `30`, leaves the local setup evidence in `%LOCALAPPDATA%\AgentSwitchboard\tmux-gnhf\setup-runs`, and tells the operator to rerun the same file.

An unmanaged existing WezTerm configuration is preserved. Review the generated proposal before explicitly choosing replacement through the core setup flow.

## No terminal focus

The proof never types through Windows focus and never uses `SendKeys`.

It creates a dedicated disposable tmux session, opens it through `wezterm start --always-new-process`, issues a base64-encoded nonce with `tmux send-keys`, and verifies the decoded output with `tmux capture-pane`. Because the clear nonce does not appear in the command text, captured nonce output proves that the shell executed the command rather than merely echoing input.

The proof then:

- detaches the tmux client through `tmux detach-client`;
- confirms the same session, window, and captured marker remain alive;
- starts a new WezTerm process;
- confirms the same tmux surface reattaches with the original marker intact.

The user’s managed `dev` session is not detached, killed, or repurposed. The proof session is named `as-proof-<nonce>` and is removed at the end.

## GNHF behavior proof

After session persistence succeeds, the runner checks the WSL-local toolchain and requires OpenCode to report an authenticated DeepSeek provider without reading or printing credentials. It refreshes exact `provider/model` identifiers and prefers:

1. `deepseek/deepseek-v4-pro`
2. `deepseek/deepseek-chat`
3. `deepseek/deepseek-reasoner`
4. another discovered `deepseek/*` model

A runtime-only `OPENCODE_CONFIG_CONTENT` selects the exact model, selects the same small model, disables sharing, and never writes provider secrets.

The runner creates a disposable Git repository below the local artifact root. GNHF receives a bounded objective to create and commit exactly one file, `agent-runtime-proof.json`, with a unique nonce. Success requires all of the following:

- the exact start nonce appears in the GNHF log;
- the bounded GNHF process finishes before timeout with exit code zero;
- a new `gnhf/*` branch exists;
- the committed JSON contains the exact nonce and expected values;
- the branch differs from `main` by exactly that one file;
- the disposable base checkout remains clean;
- the AgentSwitchboard source checkout still passes `git diff --check` and `git status --short`.

No personal repository, account data, default branch, remote ref, or production machine state is used for the behavior proof.

## Proof levels

The result names the highest level actually reached:

| Proof level | Meaning |
|---|---|
| `preflight-only` | The proof stopped before targeted validation. |
| `targeted-static-validation` | Repository and installed-script contracts passed; no runtime ACK is claimed. |
| `launcher-and-command-ack` | The focus-independent command was issued and its exact decoded nonce was captured. |
| `live-wezterm-wsl-tmux-session-persistence` | A WezTerm client attached, detached, the same tmux state persisted, and a new WezTerm process reattached. |
| `live-windows-wsl-tmux-gnhf-behavior-observed` | The full chain passed and the selected hosted agent created and committed the exact disposable proof artifact. |

A process or tmux client proves the attach chain, not pixel-level GUI rendering. A route selection or command ACK does not prove hosted-model behavior. Only the exact committed disposable artifact promotes the result to the highest level.

## Exact artifacts

Each run writes beneath:

```text
%LOCALAPPDATA%\AgentSwitchboard\tmux-gnhf\runtime-proof\<timestamp>\
```

Expected artifacts:

```text
windows-workstation-live-proof.json
runtime-events.jsonl
gnhf-runtime.log
gnhf-objective.md
run-gnhf-proof.sh
disposable-repo\
```

`windows-workstation-live-proof.json` contains the exact proof level, each proof-chain boolean, source branch/SHA, selected agent/model, failure reason, artifact paths, and the machine-readable handoff.

Runtime evidence remains local and is never committed by the installer.

## SysAdminSuite handoff

The final result includes `agentswitchboard-workstation-runtime-handoff/v1` with:

- `readyForAutomatedAgents`
- `readyForSysAdminSuiteTandem`
- proof and event-log paths
- selected agent and model
- disposable GNHF proof branch and commit

Both readiness flags remain false until the full GNHF behavior proof succeeds. SysAdminSuite remains authoritative for its own host-mutation policy, validators, deployment doctrine, production proof, push, merge, and release decisions.

## Direct PowerShell use

Plan without launching:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\wsl\Install-WindowsWorkstationLiveProof.ps1 `
  -SourceRoot .\tooling\wsl `
  -ManifestPath .\tooling\wsl\tmux-gnhf-workstation.example.json
```

Install after the core workspace exists:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\wsl\Install-WindowsWorkstationLiveProof.ps1 `
  -SourceRoot .\tooling\wsl `
  -ManifestPath .\tooling\wsl\tmux-gnhf-workstation.example.json `
  -Apply -Confirm:$false
```

Run the installed proof:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\tmux-gnhf\Run-WindowsWorkstationLiveProof.cmd"
```

Use an exact discovered model only when needed:

```powershell
pwsh -NoLogo -NoProfile -File "$env:LOCALAPPDATA\AgentSwitchboard\tmux-gnhf\Invoke-WindowsWorkstationLiveProof.ps1" `
  -ManifestPath "$env:LOCALAPPDATA\AgentSwitchboard\tmux-gnhf\tmux-gnhf-workstation.json" `
  -ModelId "deepseek/deepseek-v4-pro"
```

## Runtime implementation boundary

The installed proof launcher is intentionally modular: the main orchestrator imports a bounded process/WSL/tmux helper module, a disposable WezTerm/tmux session proof, and a disposable GNHF behavior proof. The installer copies and validates all four files as one versioned proof lane.
