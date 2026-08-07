# Technician Bootstrap-Order Validation

## Trigger

Use this skill when a task changes or validates the Windows technician bootstrap dependency order, when the bootstrap-order CI is red, when a refactor changes source tokens owned by the ordering contract, or when a fresh agent must continue this lane safely.

## Required inputs

- exact repository root, branch, and HEAD;
- `AGENTS.md` and `CODEBASE_MAP.md`;
- `tooling/profiles/windows/harness/technician-ready/harness.registry.json`;
- `tooling/profiles/windows/harness/technician-ready/bootstrap-order.contract.json`;
- current changed-file set and CI/validator evidence.

## Workflow selection

1. New or resumed work: `technician-bootstrap-order-intake`.
2. Tracked change before commit/push: `technician-bootstrap-order-validate-change`.
3. Red validator or CI: `technician-bootstrap-order-repair-failure`.
4. Session/agent/PR boundary: `technician-bootstrap-order-handoff`.

The machine-readable routes live in `tooling/profiles/windows/harness/technician-ready/skill-routing.registry.json`.

## Procedure

1. Verify exact repository identity and preserve unrelated work.
2. Read the focused map, registry, source contract, and selected workflow.
3. Keep governance changes in P00 and product behavior changes outside a harness-only sprint.
4. When a source-owner semantic refactor moves an anchored token, update the source contract and affected validators in the same change. Never weaken a correct gate solely to retain green CI.
5. Run the validation order from `harness.registry.json` from focused to broad.
6. Generate local validation and status artifacts from `artifact-registry.json`; do not commit generated evidence.
7. Report exact HEAD, validator results, working/broken/missing state, proof ceiling, and one executable next action.

## Expected outputs

- passing focused harness contracts;
- passing existing bootstrap-order contracts;
- local validation JSON and operator status Markdown/JSON when writes are enabled;
- exact Git/PR evidence;
- dependency-aware handoff when work crosses a session boundary.

## Stop conditions

Stop the harness-only lane when the required repair would modify `AGENTS.md`, other governance authority, product implementation, credentials, live targets, or workstation runtime without explicit authorization. Preserve the failing evidence and name the owning lane instead.

## Proof ceiling

This skill can prove tracked harness completeness, deterministic workflow/registry coupling, static ordering contracts, parser validity, CI results, and local report generation. It cannot prove WezTerm installation, WSL mutation, tmux runtime behavior, visible windows, provider behavior, deployment, or operator acceptance.
