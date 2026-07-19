# AgentSwitchboard

Windows-first automation for installing, configuring, routing, smoke-testing, and validating coding agents across multiple hosted model providers.

AgentSwitchboard is being built as an **agentic engineering control plane**: engineers define intent and acceptance boundaries, agents perform contextual planning and implementation, and deterministic code supplies fast, repeatable guardrails. The goal is to move routine coding execution into evidence-backed AI Developer Workflows rather than placing a human inside every edit-test-repair loop.

## Persistent tmux + GNHF workstation

For a new personal or technician Windows workstation, clone the repository and then double-click:

```text
Setup-TmuxGnhfWorkspace.cmd
```

The click-ready launcher creates a local manifest from safe defaults, checks WSL and Ubuntu, handles reboot boundaries honestly, runs a read-only plan, requires an explicit `INSTALL` confirmation, installs Linux packages through a root-only package phase, applies the persistent WezTerm → tmux → GNHF workspace, validates the command-level result, and preserves timestamped local logs.

Start with the [technician quick start](docs/workstation/tmux-gnhf-technician-quickstart.md). The detailed [other-computer guide](docs/workstation/tmux-gnhf-other-computer.md) remains the advanced reference.

The setup does not authenticate providers, collect tokens, call paid models during validation, push Git branches, unregister WSL, or claim live agent/runtime proof without observation.

## ChatGPT Desktop to GNHF runtime

The canonical desktop runtime keeps an operator's regular request separate from the compiled GNHF prompt, validates both contracts, prints the complete rendered prompt in the terminal, and delegates bounded worktree execution to the existing GNHF launcher. Plan mode is the default; the disposable proof requires an explicit `-Run`:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Invoke-ChatGPTDesktopGnhfSprint.ps1 -RequestPath .\tooling\gnhf\fixtures\desktop-gnhf-proof.request.md -CompiledPromptPath .\tooling\gnhf\fixtures\desktop-gnhf-proof.compiled.txt -CreateDisposableProofRepo -Run
```

See the [ChatGPT Desktop to GNHF runtime guide](docs/workstation/chatgpt-desktop-gnhf-sprint.md) for evidence, safety, and proof contracts.

## One-click Windows agent-fleet setup

Double-click [`Setup-AgentSwitchboard.cmd`](Setup-AgentSwitchboard.cmd) from the repository root.

The setup window stays open and:

- installs or repairs Hermes, GNHF, OpenCode, and Copilot CLI while reusing healthy tools;
- probes OpenCode, Goose, AGY, Copilot, and Hermes;
- registers Hermes through `acp:hermes acp` only after version and ACP checks succeed;
- runs deterministic PowerShell contract validators;
- records failures without discarding healthy fleet state;
- writes a transcript and JSON summary under `%LOCALAPPDATA%\AgentSwitchboard\setup-logs`.

After setup, list READY and BLOCKED agents:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

See the [GNHF fleet guide](tooling/gnhf/README.md) for bounded sprint and parallel-fleet commands.

## Architecture

- [Agentic Software Factory](docs/architecture/agentic-software-factory.md)
- [Canonical Mermaid source](diagrams/agentic-software-factory.mmd)
- [Repository-floor recovery](docs/repository-floor.md)

The current architecture keeps humans responsible for constraints, exceptions, and acceptance while progressively automating decomposition, coding, repair, testing, evidence generation, and workflow routing.
