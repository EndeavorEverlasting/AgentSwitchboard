# Multi-product bootstrap charter

**Plan:** `ASB-2026-09-MULTI-PRODUCT-BOOTSTRAP-CHARTER` — `EndeavorEverlasting/AgentSwitchboard` — `active` `high` — depends on `ASB-2026-09-AGENT-BOOTSTRAP-CHILD-BUS`

## Mission

Coordinate the bounded successor program after the charter and accepted FirstMate runtime-boundary ADR: **Pi + OpenCode remain Windows-native**, **FirstMate is the canonical live crew runtime in WSL/Ubuntu with Windows bridge-only**, **GNHF remains a bounded Windows single-agent/fleet launcher rather than a second crew platform**, and **Herdr remains deferred**.

The successor map is canonical in `plans/active/ASB-2026-09-multi-product-bootstrap-charter.plan.json`. One sprint panel goes into one new chat.

## Proven floor

- Multi-product charter/product matrix + Pi Inspect/Apply lifecycle registration integrated by PR #165 / merge `2da80edfc861b1f8ea32305082da029d22ecfc5c`.
- FirstMate convergence contract is on `main` and is bound to accepted ADR `ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME`.
- FirstMate stale PR stack remains unmerged; historical PR #96 pin is provenance only and must be refreshed before runtime claims.
- ASQ-005 OpenCode LSP contract floor is integrated; live TUI proof remains Admin Box 1 runtime work.
- Herdr is deferred. ASB child-bus Pi/OpenCode adapters, ASB fan-out, and ASB nested live runtime remain frozen/retired by ADR.

## Launch waves

### Wave A — launch in parallel

1. **FM-REFRESH-06 — FirstMate Linux/WSL interop foundation refresh.** Re-resolve current FirstMate `main`, salvage only the PR #96 foundation required for current WSL interop, refresh the upstream pin, validate, integrate.
2. **PI-FIELD-07 — Pi Admin Box Inspect/Apply field proof.** Refresh `main`, run Inspect first, Apply only when required/authorized, then Inspect again. Receipts remain local/untracked.
3. **LSP-RUNTIME-08 — ASQ-005 OpenCode fresh-TUI LSP proof.** Continue the existing Admin Box 1 runtime lane; no tracked mutation unless a reproducible defect is proved.
4. **GNHF-NARROW-09 — GNHF ownership boundary.** Encode ADR-linked NARROW semantics without deleting or behaviorally rewriting the existing Windows launchers.

Tracked collision ownership: FirstMate foundation owns its scoped `tooling/firstmate/**` foundation + focused tests; GNHF owns `tooling/gnhf/**` + focused boundary test; Pi and LSP Wave A lanes are runtime-evidence-only unless they expose an independently proven product defect.

### Wave B — after Wave A dependencies

5. **FM-BRIDGE-10 — FirstMate Windows bridge + operational harness reconciliation.** Depends on FM-REFRESH-06. Reconcile the useful PR #98/#99/#100/#101 hardening into current main: explicit Ubuntu, bounded timeouts, CRLF transport, WSL-owned clone, prerequisite gate, empty-stream safety, Windows contract front door, interpreter continuity, scoped workflow/skill/validator/CI.
6. **PI-REMOVE-11 — Real Pi Remove/Unbootstrap.** Depends on PI-FIELD-07. Implement ownership-safe Remove only from observed/contracted managed state; preserve credentials/settings/sessions/project trust/unrelated shared state.

### Wave C — runtime proof after integrated implementations

7. **FM-WSL-12 — Physical FirstMate WSL/Ubuntu floor.** Depends on FM-BRIDGE-10. Run the prerequisite gate and read-only interop probe on an authorized Windows Admin Box; this proves the bridge/floor, not crew dispatch.
8. **PI-ROLLBACK-14 — Pi physical Remove/restoration.** Depends on PI-REMOVE-11 + PI-FIELD-07. Prove Remove → Inspect and, when Pi should remain installed, Apply → final Inspect restoration.

### Wave D — FirstMate crew proof

9. **FM-CREW-13 — One bounded local-only FirstMate crew pilot.** Depends on FM-WSL-12. `local-only`, `yolo` disabled, isolated worktree, no remote writes. Require observed worker spawn, worktree identity, supervision/wake, terminal completion, validation, and clean disposition.

### Final convergence

10. **CONVERGE-15 — Program/PR convergence.** Depends on FM-CREW-13, PI-ROLLBACK-14, GNHF-NARROW-09, and LSP-RUNTIME-08. Refresh provider truth; update plan/matrix/ledger; close or supersede stale PRs only with current-main containment/replacement proof; keep Herdr deferred and ASB child-bus live-runtime work frozen.

## Harness factoring

- **FirstMate skill:** historical `.ai/skills/firstmate-crew-orchestration/SKILL.md` is a salvage candidate, not current-main authority. Keep/rewire it only in FM-BRIDGE-10 after the executable interop floor exists and deterministic routing can name inputs, outputs, preconditions, guardrails, validators, and proof ceiling.
- **FirstMate capabilities/triggers:** do not invent generic crew capability claims before the refreshed harness exists. Route current integration through existing `integration.requested` / `pr-integration` and runtime proof through `runtime-proof` or `end-to-end-runtime-validation`; add FirstMate-specific routing only with the scoped operational harness.
- **Pi fusion:** keep separate from Pi system bootstrap. Do not use Pi fusion/private child launchers as a replacement crew platform.
- **Child-agent bus:** keep schemas/fail-closed policy envelope; no runtime adapter expansion.
- **GNHF:** keep bounded Windows single-agent/fleet operations; add the ownership boundary, not a competing decomposition/supervision layer.
- **Herdr:** no skill/capability/trigger expansion in this program wave.

## Proof ceiling

This plan proves durable factoring, ownership, dependencies, collision boundaries, and required proof transitions. It does **not** prove Pi field mutation/reversal, FirstMate physical WSL or crew execution, OpenCode TUI/LSP behavior, Herdr readiness, or stale-PR containment until their owning successor gates run.
