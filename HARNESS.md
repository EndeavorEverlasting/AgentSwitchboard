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
- Harness component inventory: `tooling/harness/operational/harness-components.registry.json`
- Machine-readable repository contract: `.ai/agent-contract.json`
- Split context/implementation repositories: `.ai/harness/context-workspace-boundary.contract.json` + `docs/governance/context-workspace-boundary.md` — load only when project intent/context and implementation authority are separated across repositories or workspaces.

## Commands that matter

```powershell
Test-ProgressiveDisclosureHarness.cmd
python tooling/harness/operational/Get-OperationalHarnessStatus.py --task "describe the task"
pwsh -NoLogo -NoProfile -File scripts/Test-HarnessInfrastructureCompleteness.ps1
```

These prove context routing, select the operational route, and verify the tracked harness inventory without preloading every catalog.

## Harness infrastructure work

For harness builds/repairs, load `.ai/skills/operational-harness-routing/SKILL.md` and `tooling/harness/operational/harness-components.registry.json`. Reuse registered owners; do not create a parallel harness.

Remote merge is not local adoption. Before using a newly merged local command, load `tooling/harness/operational/workflows/post-integration-local-adoption.workflow.json` and `.ai/skills/post-integration-local-adoption/SKILL.md`; fetch, prove containment, fast-forward only clean behind-only work or use an isolated worktree, then run the tracked command.

## Drill down, one layer at a time

**30k domain:** open `context.routes.json`, select exactly one matching domain, then load only its `defaultLoad` paths. Do not load another domain unless the task crosses that boundary.

**15k workflow:** select one workflow under that domain and load only its workflow `defaultLoad` set. Implementation code, full validator source, schemas, fixtures, reports, PR history, and operator guides remain `onDemand`.

For OpenCode LSP work, the 30k owner is `tooling/harness/context/domains/opencode-lsp.domain.json`; Configure then routes to `tooling/harness/operational/opencode-lsp-setup/workflows/configure.workflow.json`.

## Proof boundary

A green context or harness-infrastructure completeness gate proves routing/inventory integrity, path resolution, tracked component presence, preserved governance authority, and measured context/static contracts. It does **not** prove product behavior, provider/model quality, workstation adoption, live LSP diagnostics, deployment, or user-visible success. Run the selected domain/workflow validator and, when required, the post-integration local-adoption workflow for that proof.
