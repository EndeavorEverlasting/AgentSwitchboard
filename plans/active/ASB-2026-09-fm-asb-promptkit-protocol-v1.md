# ASB-2026-09 FirstMate↔ASB↔PromptKit protocol v1

Freeze the three-product boundary as **contract-only** artifacts:

- six schemas (shared envelope + five messages)
- protocol policy with ownership, idempotency, and semantic rules
- context-rollover state machine, events, and user-facing receipts
- focused validators and CI

## Proof ceiling

Contract + synthetic fixtures only. No live FirstMate, Prompt Kit routing API, or automatic rollover.

## Next

After validators pass and the PR is open, the next lane is a FirstMate observation adapter that emits `asb.agent-observation/v1` without becoming a second crew watcher.
