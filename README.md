# AgentSwitchboard

Windows-first automation for installing, configuring, routing, smoke-testing, and validating coding agents across multiple hosted model providers.

AgentSwitchboard is being built as an **agentic engineering control plane**: engineers define intent and acceptance boundaries, agents perform contextual planning and implementation, and deterministic code supplies fast, repeatable guardrails. The goal is to move routine coding execution into evidence-backed AI Developer Workflows rather than placing a human inside every edit-test-repair loop.

## Architecture

- [Agentic Software Factory](docs/architecture/agentic-software-factory.md)
- [Canonical Mermaid source](diagrams/agentic-software-factory.mmd)
- [Repository-floor recovery](docs/repository-floor.md)

The current architecture keeps humans responsible for constraints, exceptions, and acceptance while progressively automating decomposition, coding, repair, testing, evidence generation, and workflow routing.
