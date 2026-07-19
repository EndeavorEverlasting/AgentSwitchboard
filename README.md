# AgentSwitchboard

Windows-first automation for installing, configuring, routing, smoke-testing, and validating coding agents across multiple hosted model providers.

AgentSwitchboard is being built as an **agentic engineering control plane**: engineers define intent and acceptance boundaries, agents perform contextual planning and implementation, and deterministic code supplies fast, repeatable guardrails. The goal is to move routine coding execution into evidence-backed AI Developer Workflows rather than placing a human inside every edit-test-repair loop.

## Readiness-first startup

Double-click [`AgentSwitchboard.cmd`](AgentSwitchboard.cmd) from the repository root.

With no arguments it performs read-only startup orientation:

- lists OpenCode, DeepSeek, Goose, Anti-Gravity, GitHub Copilot CLI, and Hermes;
- identifies adapter-ready, verification-required, blocked, unknown, and not-configured states;
- gives actionable setup guidance based on the local fleet state;
- writes local JSON and English reports under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports\startup`;
- does not install agents, authenticate providers, call hosted models, mutate a repository, push, merge, or deploy.

When bounded sprint arguments are supplied, the same launcher displays readiness first and then delegates to the existing sprint authority.

See [Agent startup readiness](docs/workstation/agent-startup-readiness.md).

## One-click Windows setup

Double-click [`Setup-AgentSwitchboard.cmd`](Setup-AgentSwitchboard.cmd) from the repository root.

The setup window stays open and:

- installs or repairs Hermes, GNHF, OpenCode, and Copilot CLI while reusing healthy tools;
- probes OpenCode, Goose, AGY, Copilot, and Hermes;
- registers Hermes through `acp:hermes acp` only after version and ACP checks succeed;
- runs deterministic PowerShell contract validators;
- records failures without discarding healthy fleet state;
- writes a transcript and JSON summary under `%LOCALAPPDATA%\AgentSwitchboard\setup-logs`.

After setup, start with `AgentSwitchboard.cmd` or list the raw installed fleet state:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

See the [GNHF fleet guide](tooling/gnhf/README.md) for bounded sprint and parallel-fleet commands.

For DeepSeek-first runs, use the [DeepSeek GNHF route](tooling/gnhf/DEEPSEEK.md). AgentSwitchboard keeps `opencode` as the truthful native GNHF adapter, pins the selected `deepseek/provider-model` at runtime, and fails before repository work unless the exact model passes a bounded spawnability probe.

## Public plans

Repository coordination that must survive a chat, span agents, or cross waves, branches, or pull requests belongs under [`plans/`](plans/README.md).

- `plans/plan-registry.json` is the public machine-readable index.
- Active work lives under `plans/active/`.
- The schema records ownership, dependencies, safe parallel work, collision boundaries, tasks, expected artifacts, validation, proof, and handoff.
- A plan is not a pull request. The plan coordinates work; branches and PRs transport and review implementation.
- Material coordination changes should update the plan in the same branch or PR as the implementation.
- Secrets, local runtime evidence, customer data, provider state, and private machine paths are forbidden in public plans.

Validate the surface with:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-PublicPlanContracts.ps1
```

Reusable child-repository adoption files live under [`templates/repository-agent-contract/plans/`](templates/repository-agent-contract/plans/).

## Agent operating contract

AgentSwitchboard is the canonical policy source for the EndeavorEverlasting repository family.

Start with [`AGENTS.md`](AGENTS.md), use [`CODEBASE_MAP.md`](CODEBASE_MAP.md) to load the smallest relevant surface, then read the tool adapter and routing documents:

- [`CLAUDE.md`](CLAUDE.md)
- [`SKILLS.md`](SKILLS.md)
- [`CAPABILITIES.md`](CAPABILITIES.md)
- [`TRIGGERS.md`](TRIGGERS.md)
- [`plans/plan-registry.json`](plans/plan-registry.json)
- [Repository-family governance](docs/governance/repository-family.md)
- [Repository-family harness](docs/governance/repository-family-harness.md)
- [Machine-readable contract](.ai/agent-contract.json)

Reusable child-repository adoption files live under [`templates/repository-agent-contract/`](templates/repository-agent-contract/).

## Supported repository family

AgentSwitchboard must be able to inspect and coordinate work for:

- `EndeavorEverlasting/AgentSwitchboard`
- `EndeavorEverlasting/BlacksmithGuild`
- `EndeavorEverlasting/web-excel-repair-triage`
- `EndeavorEverlasting/SysAdminSuite`

The machine-readable profiles live in [`.ai/harness/repository-family.registry.json`](.ai/harness/repository-family.registry.json). Each profile identifies the child's local rules, codebase map, skills, workflows, run-context authority, artifact registry, validators, reports, handoff contract, output policy, and proof ceiling.

Run the read-only local readiness probe:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1
```

It does not clone, fetch, switch branches, execute child validators, invoke providers, mutate targets, push, merge, or deploy. It emits an untracked JSON status packet, English report, and compressed handoff under the operating-system temporary directory by default.

A `ready` result proves only local clone identity and required-path presence. Each child repository retains authority for its product behavior, validation, generated artifacts, runtime, and acceptance.

## Validation

Validate the canonical documentation contract, public plans, and family harness with:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AgentDocumentationContract.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-PublicPlanContracts.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-RepositoryFamilyHarness.ps1
```

## Architecture

- [Agentic Software Factory](docs/architecture/agentic-software-factory.md)
- [Canonical Mermaid source](diagrams/agentic-software-factory.mmd)
- [Repository-floor recovery](docs/repository-floor.md)

The current architecture keeps humans responsible for constraints, exceptions, and acceptance while progressively automating decomposition, coding, repair, testing, evidence generation, and workflow routing.
