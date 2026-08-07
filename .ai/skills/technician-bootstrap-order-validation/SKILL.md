---
id: technician-bootstrap-order-validation
version: 1.0.0
status: canonical
---

# Technician Bootstrap-Order Validation

## Trigger

Use this skill when a task changes or validates the Windows technician bootstrap dependency order, when the bootstrap-order CI is red, when a semantic refactor changes source tokens owned by the ordering contract, or when a fresh agent must continue this focused lane safely.

Canonical discovery begins in `SKILLS.md` and `TRIGGERS.md`; the focused machine-readable routes then live in `tooling/profiles/windows/harness/technician-ready/skill-routing.registry.json`.

## Inputs

- exact repository root, branch, and HEAD;
- `AGENTS.md`, `CODEBASE_MAP.md`, `SKILLS.md`, and `TRIGGERS.md`;
- `tooling/profiles/windows/harness/technician-ready/harness.registry.json`;
- `tooling/profiles/windows/harness/technician-ready/bootstrap-order.contract.json`;
- current changed-file set and CI/validator evidence.

## Procedure

1. Verify exact repository identity and preserve unrelated work.
2. Read the focused map, registry, source contract, and canonical routing surfaces.
3. Select exactly one focused workflow: intake for new/resumed work, validate-change for tracked changes, repair-failure for red validation, or handoff at an agent/chat/PR boundary.
4. Keep governance changes in P00 and product behavior changes outside a harness-only sprint.
5. When a source-owner semantic refactor moves an anchored token, update the source contract and affected validators in the same change. Never weaken a correct gate solely to retain green CI.
6. Run the validation order from `harness.registry.json` from focused to broad.
7. Generate local validation and component-status artifacts from `artifact-registry.json`; do not commit generated evidence.
8. Report exact HEAD, validator results, working/broken/missing state, proof ceiling, and one executable next action.

## Outputs

- passing focused harness contracts;
- passing existing bootstrap-order and technician-readiness contracts;
- passing agent documentation contract for canonical routing changes;
- local validation JSON and component-status Markdown/JSON when writes are enabled;
- exact Git/PR evidence;
- dependency-aware handoff when work crosses a session boundary.

## Deterministic validation

```powershell
python -m unittest tests.test_technician_bootstrap_order_harness -v
python -m unittest tests.test_technician_bootstrap_order -v
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1 -RootPath . -NoWrite
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrder.ps1 -RootPath .
python -m unittest tests.test_technician_agentswitchboard_ready -v
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1 -RootPath .
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1 -RootPath . -NoWrite
git diff --check
```

## Forbidden scope

- modifying `AGENTS.md` or another governance authority in this harness-only lane;
- changing product bootstrap/runtime behavior merely to satisfy harness infrastructure work;
- secrets, provider credentials, deployment, live target mutation, destructive Git, or force updates;
- weakening a valid source-order gate to make tests pass;
- claiming component presence or CI success proves workstation/runtime acceptance.

## Stop and escalate

Stop this harness-only lane when the required repair belongs to governance/P00, product implementation, credentials, a protected/live runtime, or another writer's owned surface. Preserve the exact failing evidence and name the owning lane rather than crossing scope.

## Proof ceiling

This skill can prove tracked harness completeness, canonical discoverability, deterministic workflow/registry coupling, static ordering contracts, parser validity, CI results, and local report generation. It cannot prove WezTerm installation, WSL mutation, tmux runtime behavior, visible windows, provider behavior, deployment, or operator acceptance.
