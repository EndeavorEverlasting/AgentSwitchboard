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

## Agent operating contract

AgentSwitchboard is the canonical policy source for the EndeavorEverlasting repository family.

Start with [`AGENTS.md`](AGENTS.md), then read the tool adapter and routing documents:

- [`CLAUDE.md`](CLAUDE.md)
- [`SKILLS.md`](SKILLS.md)
- [`CAPABILITIES.md`](CAPABILITIES.md)
- [`TRIGGERS.md`](TRIGGERS.md)
- [Repository-family governance](docs/governance/repository-family.md)
- [Machine-readable contract](.ai/agent-contract.json)

Reusable child-repository adoption files live under [`templates/repository-agent-contract/`](templates/repository-agent-contract/). Validate the contract with:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AgentDocumentationContract.ps1
```

## Architecture

- [Agentic Software Factory](docs/architecture/agentic-software-factory.md)
- [Canonical Mermaid source](diagrams/agentic-software-factory.mmd)
- [Repository-floor recovery](docs/repository-floor.md)

The current architecture keeps humans responsible for constraints, exceptions, and acceptance while progressively automating decomposition, coding, repair, testing, evidence generation, and workflow routing.
