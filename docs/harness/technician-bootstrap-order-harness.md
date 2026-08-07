# Technician Bootstrap-Order Operational Harness

This focused harness makes the Windows technician bootstrap-order lane inspectable and repeatable for a fresh agent without changing governance authority or claiming workstation runtime proof.

## What is working

- The focused map identifies canonical intake routing, the operator front door, prerequisite gate, runtime engine, source order contract, validators, skill, workflows, artifacts, report surface, hook, and CI.
- `SKILLS.md` and `TRIGGERS.md` expose the focused skill before an agent is expected to know this harness subtree exists.
- Four workflow specs cover intake, pre-commit validation, failure repair, and handoff.
- Generated validation/status evidence has one local artifact registry and remains untracked.
- A scoped skill and deterministic routing registry select the focused workflow after canonical intake.
- The completeness validator independently pins mandatory owners so deleting a path from the registry cannot silently shrink the harness.
- The status reporter emits component state in English plus JSON/Markdown outside the repository; it deliberately does not call component presence validation readiness.
- The pre-commit helper is opt-in, location-independent, restores caller location, and runs the complete focused validation order for relevant staged paths.

## Source-anchor refactor risk

The existing bootstrap-order contract intentionally anchors source tokens so it can prove ordering and ownership without executing workstation mutation. That creates maintenance coupling: a semantic refactor may move or rename a valid anchor even when behavior remains correct.

This harness makes that coupling explicit rather than pretending it does not exist. `harness.registry.json` registers the three source-owner paths and the coupled contract/validator paths. The repair workflow and scoped skill require a semantic source refactor to update the contract and affected validators in the same change. A correct gate may not be weakened, skipped, or deleted merely to recover green CI.

## Workflow selection

Canonical intake first routes `bootstrap.order-contract-change` through `TRIGGERS.md` to `technician-bootstrap-order-validation` in `SKILLS.md`. The skill then selects:

- New/resumed lane: `workflows/intake.workflow.json`
- Tracked change: `workflows/validate-change.workflow.json`
- Red validator/CI: `workflows/repair-failure.workflow.json`
- Agent/chat/PR boundary: `workflows/handoff.workflow.json`

The focused machine-readable routing table is `skill-routing.registry.json`.

## Validation order

1. `python -m unittest tests.test_technician_bootstrap_order_harness -v`
2. `python -m unittest tests.test_technician_bootstrap_order -v`
3. `pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1 -RootPath . -NoWrite`
4. `pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrder.ps1 -RootPath .`
5. `python -m unittest tests.test_technician_agentswitchboard_ready -v`
6. `pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1 -RootPath .`
7. `pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1 -RootPath . -NoWrite`
8. `git diff --check`

`Test-TechnicianBootstrapOrderHarness.cmd` runs this floor from the repository root regardless of caller working directory and writes the canonical local validation/status artifacts to one run directory.

## Component status versus validation

`Get-TechnicianBootstrapOrderHarnessStatus.ps1` reports only component presence and Git identity. A complete component set is emitted as `components-complete-validation-unproven`. It does not execute validators and must not be cited as a correctness/readiness result. The owning validator sequence and exact-head CI establish repository validation.

## Artifacts

The canonical registry is `artifact-registry.json`. Default local evidence lives under `%LOCALAPPDATA%\AgentSwitchboard\technician-bootstrap-order\runs\<run-id>\`.

The validator writes `bootstrap-order-harness-validation.json`. The component reporter writes `bootstrap-order-harness-status.json` and `bootstrap-order-harness-status.md`. Handoff uses the tracked template and workflow but must not embed credentials, private hosts, raw scrollback, full environment dumps, or unreviewed screenshots.

## Known traps

- Do not let AGY/OpenCode/GNHF/launcher setup leak into the prerequisite gate.
- Do not weaken the order contract to accommodate a source refactor; update the refactor-coupled contract and validators together.
- Do not add a skill only inside the focused subtree; keep canonical `SKILLS.md`/`TRIGGERS.md` routing coherent.
- Do not treat component presence as repository validation.
- Do not install the pre-commit hook implicitly.
- Do not commit generated run evidence.
- Do not use destructive Git or force updates to recover from failed checks.
- Do not promote repository/CI success to workstation runtime success.

## Proof ceiling

This harness can prove tracked component completeness, canonical workflow discoverability, deterministic focused workflow selection, source-contract coupling, parser validity, static ordering contracts, documentation contracts, CI execution, and local report generation. It does not prove WezTerm installation, WSL mutation, tmux session execution, visible terminal windows, provider responses, deployment, or operator acceptance.
