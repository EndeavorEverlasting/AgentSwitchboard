# Technician Bootstrap-Order Operational Harness

This focused harness makes the Windows technician bootstrap-order lane inspectable and repeatable for a fresh agent without changing governance authority or claiming workstation runtime proof.

## What is working

- The focused map identifies the operator front door, prerequisite gate, runtime engine, source order contract, validators, skill, workflows, artifacts, report surface, hook, and CI.
- Four workflow specs cover intake, pre-commit validation, failure repair, and handoff.
- Generated validation/status evidence has one local artifact registry and remains untracked.
- A scoped skill and deterministic routing registry tell a fresh agent which workflow applies.
- The completeness validator proves all registered harness files exist, JSON parses, workflows are routed, the hook and CI run the focused floor, and PowerShell harness scripts parse.
- The status reporter emits English plus JSON/Markdown state outside the repository.
- The pre-commit helper is opt-in and runs only when relevant staged paths are present.

## Source-anchor refactor risk

The existing bootstrap-order contract intentionally anchors source tokens so it can prove ordering and ownership without executing workstation mutation. That creates a maintenance coupling: a semantic refactor may move or rename a valid anchor even when behavior remains correct.

This harness makes that coupling explicit rather than pretending it does not exist. `harness.registry.json` registers the three source-owner paths and the coupled contract/validator paths. The repair workflow and scoped skill require a semantic source refactor to update the contract and affected validators in the same change. A correct gate may not be weakened, skipped, or deleted merely to recover green CI.

## Workflow selection

- New/resumed lane: `workflows/intake.workflow.json`
- Tracked change: `workflows/validate-change.workflow.json`
- Red validator/CI: `workflows/repair-failure.workflow.json`
- Agent/chat/PR boundary: `workflows/handoff.workflow.json`

The canonical routing table is `skill-routing.registry.json`.

## Validation order

1. `python -m unittest tests.test_technician_bootstrap_order_harness -v`
2. `python -m unittest tests.test_technician_bootstrap_order -v`
3. `pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1 -RootPath . -NoWrite`
4. `pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrder.ps1 -RootPath .`
5. `python -m unittest tests.test_technician_agentswitchboard_ready -v`
6. `pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1 -RootPath . -NoWrite`
7. `git diff --check`

`Test-TechnicianBootstrapOrderHarness.cmd` runs the focused floor and writes the canonical local validation/status artifacts to one run directory.

## Artifacts

The canonical registry is `artifact-registry.json`. Default local evidence lives under `%LOCALAPPDATA%\AgentSwitchboard\technician-bootstrap-order\runs\<run-id>\`.

The validator writes `bootstrap-order-harness-validation.json`. The status reporter writes `bootstrap-order-harness-status.json` and `bootstrap-order-harness-status.md`. Handoff uses the tracked template and workflow but must not embed credentials, private hosts, raw scrollback, full environment dumps, or unreviewed screenshots.

## Known traps

- Do not let AGY/OpenCode/GNHF/launcher setup leak into the prerequisite gate.
- Do not weaken the order contract to accommodate a source refactor; update the refactor-coupled contract and validators together.
- Do not install the pre-commit hook implicitly.
- Do not commit generated run evidence.
- Do not use destructive Git or force updates to recover from failed checks.
- Do not promote repository/CI success to workstation runtime success.

## Proof ceiling

This harness can prove tracked component completeness, deterministic workflow selection, source-contract coupling, parser validity, static ordering contracts, CI execution, and local report generation. It does not prove WezTerm installation, WSL mutation, tmux session execution, visible terminal windows, provider responses, deployment, or operator acceptance.
