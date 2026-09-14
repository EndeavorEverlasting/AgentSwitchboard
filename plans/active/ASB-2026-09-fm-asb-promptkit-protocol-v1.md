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

Phase 1 observation adapter (new bounded sprint): emit `asb.agent-observation/v1` from FirstMate task state without becoming a second crew watcher.
