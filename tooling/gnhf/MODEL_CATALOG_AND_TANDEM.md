# Runtime Model Catalog and Tandem Repository Orchestration

AgentSwitchboard separates **agents**, **providers**, **models**, **repositories**, and **handoffs**. Buying or authenticating one provider does not collapse those layers; it makes that provider eligible when runtime discovery reports its models.

## Model expansion strategy

OpenCode is the broad model adapter. Its official documentation states that Models.dev backs 75+ providers, and `opencode models --refresh` returns currently available models as exact `provider/model` identifiers. The tracked provider directory contains every provider named on OpenCode's provider page plus OpenCode Go, while the generated catalog remains authoritative for exact models.

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Get-GnhfModelCatalog.ps1 -PlanOnly
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Get-GnhfModelCatalog.ps1
```

The generated catalog:

- never reads or writes API keys;
- records only provider names reported by `opencode auth list`;
- refreshes the exact model list;
- groups every returned model by provider;
- records OpenCode as the executable adapter;
- writes atomically beneath the local fleet root by default.

DeepSeek remains the first SysAdminSuite preference. The plan tries `deepseek/deepseek-v4-pro`, `deepseek/deepseek-chat`, and `deepseek/deepseek-reasoner` when those exact IDs are present, then falls through to discovered models by provider preference.

## Agent adapters

The tandem runner can assign any agent already understood by `Start-GnhfSprint.ps1` and fleet readiness state:

- native GNHF names: OpenCode, Claude, Codex, Copilot, Pi, RovoDev;
- readiness-backed or ACP adapters: Goose, AGY/Anti-Gravity, Hermes;
- custom `acp:<command>` adapters when explicitly governed by fleet state.

The model catalog is intentionally OpenCode-centered because OpenCode is the provider/model multiplexing layer. A model is not treated as a new executable agent.

## Linked repository manifest

Copy and edit the example outside tracked source or create a machine-local derivative:

```powershell
Copy-Item .\tooling\gnhf\linked-repositories.example.json `
  "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\linked-repositories.json"
```

SysAdminSuite is enabled in the example. AgentSwitchboard, Continum, Foundry, BlacksmithGuild, and Web Excel Repair Triage are registered but disabled until their local paths and bounded objectives are supplied.

One enabled entry equals one repository lane. Two lanes may not target the same canonical path. Each lane receives its own GNHF worktree through the existing repo-owned launcher.

## Build the tandem plan

```powershell
$fleet = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"

pwsh -NoLogo -NoProfile -File .\tooling\gnhf\New-GnhfTandemPlan.ps1 `
  -CatalogPath "$fleet\model-catalog.json" `
  -RepositoriesPath "$fleet\linked-repositories.json" `
  -OutputPath "$fleet\tandem\plan.json"
```

Planning fails closed for:

- placeholder paths;
- missing objectives;
- dirty or detached repositories;
- duplicate repository paths;
- unknown dependencies;
- stale or future-dated model catalogs;
- no authenticated or local-capable model candidates;
- empty model catalogs.

The planner distributes distinct discovered models across independent repositories when possible. It does not run two agents against one repository path. By default it only schedules providers reported by `opencode auth list` plus local-capable providers; `-AllowUnauthenticatedModels` exists only for plan exploration.

For every lane, the planner generates an execution objective that prepends the exact repository, model, scope, forbidden scope, input packet, expected result packet, and proof boundary before the repository's original objective.

## Review before execution

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Invoke-GnhfTandem.ps1 `
  -PlanPath "$fleet\tandem\plan.json" `
  -PlanOnly
```

## Run in tandem

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Invoke-GnhfTandem.ps1 `
  -PlanPath "$fleet\tandem\plan.json"
```

The plan's `maxParallelRepos` limits concurrent repositories. Dependencies run only after their declared upstream lane completes. Failed upstream lanes produce `blocked-by-dependency` results instead of silently launching downstream work.

## Handoff contract

Every lane receives:

```text
handoffs/<lane>/input.json
handoffs/<lane>/result.json
handoffs/<lane>/summary.md
handoffs/<lane>/launcher-stdout.txt
handoffs/<lane>/launcher-stderr.txt
```

Each `input.json` identifies both the original objective and the generated execution objective. The following environment variables point agents and repository-owned tools at the same boundary:

```text
AGENTSWITCHBOARD_HANDOFF_INPUT
AGENTSWITCHBOARD_HANDOFF_RESULT
AGENTSWITCHBOARD_HANDOFF_SUMMARY
```

For OpenCode lanes, the runner merges the exact selected `provider/model` into runtime-only `OPENCODE_CONFIG_CONTENT`, sets both the primary and small model, disables sharing, and preserves any unrelated existing runtime configuration. The result packet records whether that runtime model configuration was applied, along with the repository, agent, exact requested model, activation state, exit code, before/after Git state, launcher summary, logs, and proof level. It never claims behavior-observed proof from a successful launcher exit alone.

## SysAdminSuite boundary

SysAdminSuite remains authoritative for its own mutation gates,, host policy, deployment doctrine, validators, and runtime proof. AgentSwitchboard may assign and supervise a bounded SysAdminSuite coding lane, but it does not authorize workstation mutation, software deployment, AutoLogon changes, package access, or production execution.

The recommended flow is:

1. SysAdminSuite produces or receives a bounded objective/capsule.
2. AgentSwitchboard selects an eligible model and isolated lane.
3. GNHF performs bounded work in its worktree.
4. AgentSwitchboard writes the handoff result.
5. SysAdminSuite validators inspect committed work and decide readiness.
6. Human or repository-specific integration policy decides whether to push, merge, deploy, or reject.

Automatic push, merge, deployment, release, and default-branch mutation remain disabled.
