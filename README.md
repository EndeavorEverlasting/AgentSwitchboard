# AgentSwitchboard

Windows-first automation for installing, configuring, routing, smoke-testing, and validating coding agents across multiple hosted model providers.

AgentSwitchboard is being built as an **agentic engineering control plane**: engineers define intent and acceptance boundaries, agents perform contextual planning and implementation, and deterministic code supplies fast, repeatable guardrails. The goal is to move routine coding execution into evidence-backed AI Developer Workflows rather than placing a human inside every edit-test-repair loop.

## One-click Windows setup

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

## WSL tmux + GNHF workstation

For the persistent Windows workflow:

```text
WezTerm -> tmux -> coding agent -> bounded GNHF worktree run
```

start with the [other-computer tmux and GNHF guide](docs/workstation/tmux-gnhf-other-computer.md). The integration is plan-only by default, installs GNHF into WSL without automatic authentication, creates a capped `gnhf-safe` wrapper, and generates a persistent tmux launcher with explicit Status and destructive Stop operations.

## Architecture

- [Agentic Software Factory](docs/architecture/agentic-software-factory.md)
- [Canonical Mermaid source](diagrams/agentic-software-factory.mmd)
- [Repository-floor recovery](docs/repository-floor.md)

The current architecture keeps humans responsible for constraints, exceptions, and acceptance while progressively automating decomposition, coding, repair, testing, evidence generation, and workflow routing.
