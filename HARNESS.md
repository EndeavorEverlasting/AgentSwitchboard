# AgentSwitchboard — 50k Entry

AgentSwitchboard is a Windows-first control surface for installing, configuring, routing, smoke-testing, and validating coding agents and their workstation/runtime integrations.

**Default load rule:** after `AGENTS.md`, read only this file. Do not preload root catalogs, every skill, schemas, reports, plans, history, or implementation code.

## Major subsystems

- **Operational harness** — repository intake, validation, failure recovery, integration/handoff.
- **OpenCode / GNHF** — prompt handoff, LSP workstation setup, bounded agent execution.
- **Windows profiles** — terminal/profile launch modes, technician bootstrap, workstation contracts.
- **Android / Termux** — mobile/SSH/tmux operational profile.
- **Pi orchestration** — bounded multi-agent/fusion experiments and validation.
- **App/runtime contracts** — app composition, output context, runtime events, device launchers.
- **Governance** — precedence and safety in `AGENTS.md`; deep governance is trigger-loaded, not startup context.

## Canonical entrypoints

- Progressive router: `tooling/harness/context/context.routes.json`
- Agent glossary: `tooling/harness/context/glossary.json` — load only for an unclear term.
- Generic operational router: `tooling/harness/operational/workflow-registry.json`
- Machine-readable repository contract: `.ai/agent-contract.json`

## Commands that matter

```powershell
Test-ProgressiveDisclosureHarness.cmd
python tooling/harness/operational/Get-OperationalHarnessStatus.py --task "describe the task"
```

The first command proves context budgets/routing. The second selects the operational workflow and specialized skill without requiring every catalog to be read.

## Drill down, one layer at a time

**30k domain:** open `context.routes.json`, select exactly one matching domain, then load only its `defaultLoad` paths. Do not load another domain unless the task crosses that boundary.

**15k workflow:** select one workflow under that domain and load only its workflow `defaultLoad` set. Implementation code, full validator source, schemas, fixtures, reports, PR history, and operator guides remain `onDemand`.

For OpenCode LSP work, the 30k owner is `tooling/harness/context/domains/opencode-lsp.domain.json`; Configure then routes to `tooling/harness/operational/opencode-lsp-setup/workflows/configure.workflow.json`.

## Proof boundary

A green context harness proves routing integrity, path resolution, preserved governance authority, and measured context ceilings. It does **not** prove product behavior, provider/model quality, workstation state, live LSP diagnostics, deployment, or user-visible success. Run the selected domain/workflow validator for that proof.
