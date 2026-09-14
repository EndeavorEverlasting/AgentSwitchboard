# FirstMate ↔ AgentSwitchboard ↔ Prompt Kit protocol v1

| Field | Value |
|---|---|
| Decision ID | `ASB-ADR-2026-09-FM-ASB-PROMPTKIT-PROTOCOL-V1` |
| Status | accepted (contract-only) |
| Date | 2026-09-14 |
| Owner plan | `plans/active/ASB-2026-09-fm-asb-promptkit-protocol-v1.plan.json` |
| Related | `docs/architecture/asb-firstmate-runtime-boundary.md`, `docs/harness/context-rollover-ux.md` |

## Product boundary

| Product | Owns | Must not own |
|---|---|---|
| **FirstMate** | agents, tasks, worktrees, backends, sessions, supervision, durable message delivery, task lifecycle, relaunch | prompt ontology, Prompt Kit routing policy |
| **Prompt Kit** | workflow meaning, prompt identity, prompt selection, next-step graph, proof gates, outcome classification, grounding/recovery policy | tmux/session control, agent lifecycle |
| **AgentSwitchboard** | evidence normalization, cross-product translation, automation correlation, context-pressure observation, semantic dispatch loop | another crew scheduler, another prompt taxonomy, direct terminal manipulation |

**Invariant:** Prompt Kit decides what the work means next. AgentSwitchboard correlates evidence and turns that decision into a bounded action request. FirstMate owns delivery, workers, worktrees, lifecycle, supervision, and runtime mechanics.

## Contract stack

Machine-readable authority:

- `.ai/harness/fm-asb-promptkit-protocol.policy.json`
- `.ai/harness/schemas/fm-asb-promptkit/`
- `.ai/harness/fm-asb-promptkit-rollover-state-machine.json`
- `.ai/harness/fixtures/fm-asb-promptkit/`

Six schema files:

1. `protocol-envelope.v1.schema.json` — shared event/correlation/idempotency spine
2. `agent-observation.v1.schema.json` — FirstMate → ASB observation
3. `routing-request.v1.schema.json` — ASB → Prompt Kit (no raw transcript)
4. `routing-decision.v1.schema.json` — Prompt Kit → ASB semantic judgment
5. `prompt-dispatch.v1.schema.json` — ASB → FirstMate durable-inbox delivery
6. `context-transition.v1.schema.json` — ASB ↔ FirstMate rollover coordination

## Closed loop

```text
agent-observation
      ↓ causationId
routing-request
      ↓
routing-decision
      ↓
prompt-dispatch
      ↓
FirstMate execution
      ↓
agent-observation
```

Mission `correlationId` survives prompt switches and context rollovers. `groundingEpisodeId` advances when Prompt Kit authorizes `REGROUND` or `REBOOTSTRAP` and the transition completes.

## Delivery rules

- ASB must not poke terminal panes or send Ctrl+C / slash commands / raw tmux keys.
- Prompt injection uses FirstMate durable inbox (`deliveryPlane: durable-inbox`).
- Lifecycle uses FirstMate control plane only (`interrupt` / `exit` / `relaunch`).
- Preferred prompt delivery is `reference` (`promptId` + registry/prompt SHA + resolved task packet), not full prompt body retransmission.
- Retried `asb.prompt-dispatch/v1` must reuse the same `deliveryId`.

## Idempotency

Canonical key:

```text
idem_ + lowercase_hex(SHA256(identity-components-joined-with-"|"))
```

| Message | Identity components |
|---|---|
| `asb.agent-observation/v1` | schema + taskId + eventKey |
| `prompt-kit.routing-request/v1` | schema + observationEventId + groundingEpisodeId + executionSurface |
| `prompt-kit.routing-decision/v1` | schema + routingRequestEventId + registrySha256 |
| `asb.prompt-dispatch/v1` | schema + routingDecisionEventId + firstMateTaskId + promptSha256 |
| `asb.context-transition/v1` | schema + transitionId + state |

`semanticSha256` is computed over sorted-key canonical JSON after removing `eventId`, `createdAt`, and `idempotency`. Same key + same semantic SHA reuses the prior result; same key + different semantic SHA is `IDEMPOTENCY_KEY_REUSE_MISMATCH`.

## Semantic validator rules

- `KEEP_CURRENT_PROMPT` / `SWITCH_PROMPT` → `primaryPrompt != null`
- `NO_ROUTE` / `BLOCKED` → `primaryPrompt == null`
- `estimated` / `unavailable` context pressure → `transition.automatic` must be false
- `state == COMPLETED` → checkpoint complete, `post` and `verification` present, `error == null`
- completed `REGROUND` / `REBOOTSTRAP` → `post.groundingEpisodeId != semantic.groundingEpisodeId`

## Proof ceiling

This ADR and its validators prove **contract** shape, synthetic fixtures, and semantic rules only. They do **not** prove live FirstMate observation, Prompt Kit routing API execution, durable inbox delivery, automatic rollover, or Admin Box runtime success.

Focused validators:

```text
python3 tests/test_fm_asb_promptkit_protocol_contract.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
```

## Explicit non-goals (this contract freeze)

- Do not implement live adapters or schedulers.
- Do not rewrite the App Output Context Engine ranker in this change.
- Do not expand the child-agent bus into a crew platform.
- Do not authorize automatic primary-session rollover across every harness.

## Next executable owners

1. Phase 1 observation adapter consuming FirstMate task state without becoming a second watcher.
2. Headless Prompt Kit routing API/CLI sharing the browser classifier.
3. Durable prompt injection via `fm-send` for a read-only/scout workflow.
4. Outcome feedback into Prompt Kit outcome-receipt contracts.
5. One harness-specific verified context-pressure observer, then crew-task rollover.
