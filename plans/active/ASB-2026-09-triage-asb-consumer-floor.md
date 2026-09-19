# P07: Triage→ASB Durable Consumer Contract Floor

**Plan ID**: ASB-2026-09-TRIAGE-ASB-CONSUMER-FLOOR
**Status**: Active
**Priority**: High
**Created**: 2026-09-19

## Mission

Close AUTONOMY_GAP by implementing AgentSwitchboard's durable consumer for Triage prompt-parallel-dispatch manifests and panel/lane-prompt transport artifacts. Enforce `human_scheduler_allowed:false` and `panel_ingest_required:true`.

## Operator Correction (Binding)

- **Triage copy/portability panels ARE agent-consumable lane-prompt TRANSPORT.** ASB must machine-ingest panels + parallel-dispatch manifests and dispatch lanes into the workflow.
- **Do NOT design to delete panels.** Humans pasting is incidental compatibility only.
- **AUTONOMY_GAP = lanes unexecuted because no adapter consumes panels/manifest.** Closing gap = Switchboard ingests and runs them.
- **human_scheduler_allowed:false STILL STANDS.** Add `panel_ingest_required:true` (or equivalent) on the consumer policy.

## Upstream Contracts (READ-ONLY)

From **web-excel-repair-triage** (https://github.com/EndeavorEverlasting/web-excel-repair-triage):

- `harness/contracts/prompt-parallel-dispatch.v1.json`
- `harness/contracts/pr-merge-gate.v1.json`
- `harness/contracts/repository-local-proof-continuity.v1.json`
- `harness/conversation-continuity/checkpoint.schema.v1.json`
- `harness/contracts/prompt-kit-portability.v1.json`
- Triage panel/portability contracts and `docs/prompts.json` ladder naming AgentSwitchboard as executor

**Do NOT** copy `scripts/prompt_parallel_dispatch.py` into ASB.

## Consumer Requirements

1. **Ingest** Triage-shaped parallel-dispatch manifests AND panel/lane-prompt transport artifacts as first-class machine inputs
2. **Enforce** `human_scheduler_allowed:false` and `panel_ingest_required:true`
3. **Classify** AUTONOMY_GAP when panels/manifests exist but no adapter would execute lanes
4. **Map** ready lanes to ASB descriptors (public-plan / cursor-cloud-agent / local argv) without requiring live launches in this PR
5. **Apply merge-gate**: degraded provider limits + local_proof ⇒ CONTINUE; true blockers stay BLOCKED
6. **Accept** continue-map checkpoint → `first_unproven_gate` structurally

## Owned Scope

- `tooling/harness/triage-consumer/**` (policy with `panel_ingest_required` + `human_scheduler_allowed:false`, schemas, fixtures, Python ingest/classify/map)
- `scripts/Test-TriageAsbConsumerContract.ps1`
- `tests/test_triage_asb_consumer_contract.py`
- Optional `CODEBASE_MAP.md` + `.github/workflows/triage-asb-consumer.yml`
- `plans/active/ASB-2026-09-triage-asb-consumer-floor.plan.json` + `.md` + plan-registry membership

## Forbidden Scope

- `tooling/evals/p67-opencode-adapter/**` (Voyager ADP-02)
- technician/#319 surfaces
- Deleting or forbidding panels as design goal
- Triage mutation; claiming live runtime PASS; happy-path that REQUIRES a human to paste/proceed (panel presence is OK; human-required paste is NOT)

## Deliverables

### Policy

`tooling/harness/triage-consumer/consumer.policy.json` with:
- `human_scheduler_allowed: false`
- `panel_ingest_required: true`
- `autonomy_gap_classification_required: true`
- `manifest_and_panels_are_machine_inputs: true`
- `panel_deletion_forbidden: true`

### Schemas

- `triage-manifest.schema.json` — ASB consumer schema for Triage prompt-parallel-dispatch.v1 manifests
- `triage-panel.schema.json` — Panel/lane-prompt transport artifacts (portability fallback)
- `triage-checkpoint.schema.json` — Triage checkpoint.schema.v1 (live-thread-p02-checkpoint/v1)
- `lane-mapping.schema.json` — Maps Triage lane to ASB execution descriptor
- `autonomy-gap.schema.json` — AUTONOMY_GAP classification

### Fixtures

- `example-manifest.json`
- `example-panel.json`
- `example-checkpoint.json`
- `example-lane-mapping.json`
- `example-autonomy-gap.json`

### Python Module

`tooling/harness/triage-consumer/triage_consumer.py`:
- `TriageConsumer` class with policy enforcement
- `ingest_manifest()` — Ingest Triage manifests as first-class machine inputs
- `ingest_panel()` — Ingest Triage panels as first-class machine inputs
- `classify_autonomy_gap()` — Classify AUTONOMY_GAP when panels/manifests exist but no adapter executes lanes
- `map_lane_to_asb_descriptor()` — Map ready lanes to ASB descriptors structurally
- `apply_merge_gate_classification()` — Apply merge-gate: degraded + local_proof ⇒ CONTINUE
- `extract_first_unproven_gate()` — Accept checkpoint → first_unproven_gate structurally

### Validators

- `scripts/Test-TriageAsbConsumerContract.ps1` — PowerShell validator
- `tests/test_triage_asb_consumer_contract.py` — Pytest test suite

## Validation Order

1. `pwsh -NoLogo -NoProfile -File scripts/Test-TriageAsbConsumerContract.ps1`
2. `python3 -m pytest tests/test_triage_asb_consumer_contract.py -v`
3. `git diff --check`

## Proof Ceiling

**Contract proof** (schemas validate, fixtures pass, policy enforces `human_scheduler_allowed:false` and `panel_ingest_required:true`).

**Static test proof** (ingest/classify/map code parses manifests/panels, classifies AUTONOMY_GAP, maps lanes to ASB descriptors structurally, applies merge-gate rules).

Does **NOT** prove live lane dispatch, runtime execution, or Cursor Cloud Agent launch.

## Dependencies

None — this is the floor contract.

## Next Phase

Live lane dispatch adapter (separate plan after consumer floor merges).

## PR Expectation

Open PR from main tip, merge when gates permit. Report PR URL, merge SHA, validation, next command.
