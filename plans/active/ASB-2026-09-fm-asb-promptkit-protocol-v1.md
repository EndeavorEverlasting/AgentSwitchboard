# ASB-2026-09 FirstMate↔ASB↔PromptKit protocol v1

Freeze the three-product boundary as **contract-only** artifacts:

- six schemas (shared envelope + five messages)
- protocol policy with ownership, idempotency, and semantic rules
- context-rollover state machine, events, and user-facing receipts
- focused validators and CI

## Delivery

- Branch: `cursor/fm-asb-promptkit-v1-contracts-4c0f`
- PR: https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/184
- Reconcile floor: `main@c3da20fef02160de66d238b1c9b8eb9c6825588e`
- Prior validated head (historical): `16b4d25bee50702cbc1c108e4113f644216fdf54`

## Proof ceiling

Contract + synthetic fixtures only. No live FirstMate, Prompt Kit routing API, or automatic rollover.

## Validation

```text
python tests/test_fm_asb_promptkit_protocol_contract.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
```

## Next

After mainline integration of PR #184, the next lane is a FirstMate observation adapter that emits `asb.agent-observation/v1` without becoming a second crew watcher.
