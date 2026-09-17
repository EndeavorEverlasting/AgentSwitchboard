# Product-pass posture plan

**Plan ID:** `ASB-2026-09-PRODUCT-PASS-POSTURE`
**Repo:** EndeavorEverlasting/AgentSwitchboard
**Floor:** `main@e999602` (ASQ-020 Prove-MergeGateLocal landed)
**Status:** completed
**Updated:** 2026-09-17T20:47:16Z

## Mission

Make **product function + no harness flags** the primary agent pass standard. GitHub mergeability is optional forge hygiene for landing on `main`, not the product verdict. Agents must not idle-wait on Actions/CodeRabbit/`mergeable_state` when the owning prove already PASS and flags are clean.

## Waves

1. **PPP-01 / PPP-02** — durable plan + registry + ASQ-021 ledger (this PR).
2. **PPP-03** — AGENTS.md / governance doctrine.
3. **PPP-04** — bounded-sprint + pr-integration skill rewires.
4. **PPP-05** — optional `Prove-ProductPassLocal` alias.
5. **PPP-06** — ASQ-016 ledger stale next-action cleanup.
6. **ASQ-017** — Admin Box physical floor (host-isolated; parallel-safe if it does not write shared doctrine files).

## Product pass definition

- Run owning prove(s) on a capable host (`Prove-AutomatedTestFloorLocal`, `Prove-MergeGateLocal` when path-activated, domain proves when those paths change).
- Report PROVEN / UNPROVEN / BLOCKED_HOST / FLAGGED.
- No open FAIL / FAIL_CLOSED / hygiene flags (`git diff --check origin/main...HEAD`, ledger verbs, zero-test fail-closed).
- Forge merge is an optional next step when the operator wants `main` updated — never the primary accept gate.

## Proof ceiling

Coordination and doctrine planning only. Does not prove product runtime, Admin Box physical floor, GitHub mergeability, provider delivery, merge, release, or deployment.

## Adapter note

`scripts/prompt_parallel_dispatch.py` and `harness/contracts/prompt-parallel-dispatch.v1.json` are **absent** on this repository. Dispatch uses ASB public plans + Cursor CloudAgent/Task. See `dispatch-manifest.json` companion.
