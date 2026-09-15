# ASB-2026-09 FirstMate↔ASB↔PromptKit protocol v1

Freeze the three-product boundary as **contract-only** artifacts:

- six schemas (shared envelope + five messages)
- protocol policy with ownership, idempotency, and semantic rules
- context-rollover state machine, events, and user-facing receipts
- focused validators and CI

## Delivery

- Branch: `cursor/fm-asb-promptkit-v1-contracts-4c0f`
- PR: https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/184 (**merged**)
- Merge commit: `6c80be9c00ccad45bb0177ad88f2ffdb2e782b46`
- Reconcile floor: `main@c3da20fef02160de66d238b1c9b8eb9c6825588e`
- Integration candidate head: `b58274232f4078a415b0c7615ae7ff22be23aa29`

## Proof ceiling

Contract + synthetic fixtures only. No live FirstMate, Prompt Kit routing API, or automatic rollover.

## Validation (post-merge on main)

```text
python tests/test_fm_asb_promptkit_protocol_contract.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
```

## Next

Observation-adapter phase map moved to `plans/active/ASB-2026-09-fm-asb-observation-adapter.md` (plan id `ASB-2026-09-FM-ASB-OBSERVATION-ADAPTER`).

- Phase 2 adapter implementation: **INTEGRATED** via PR #204 (`5187195382584787bf30c7043660d74327549cd7`).
- Disposable-home Admin Box live emitter→adapter: **OBSERVED** (local receipt only; not operator-crew).
- Remaining: operator/crew live observation, then Phase 3 Prompt Kit routing adapter.
