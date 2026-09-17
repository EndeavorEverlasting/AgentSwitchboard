# ASB-2026-09 FirstMate→ASB routing-request builder (Phase 3 seam)

Bounded successor to the observation adapter's `OBS-05` handoff. Translates a
correlated `asb.agent-observation/v1` into a `prompt-kit.routing-request/v1`
without selecting prompts, consulting a registry, dispatching, rolling over, or
scheduling crew. This is ASB `cross-product-translation` ownership only.

## Delivered

| Task | Result | Evidence |
|---|---|---|
| RRB-01 builder | **INTEGRATED (contract)** | `tooling/firstmate/harness/routing/build_routing_request.py` — read-only `build_routing_request()` + CLI |
| RRB-02 fixture pin | **PROVEN (static)** | Round-trip reproduces frozen `semanticSha256 2c483f5f…` and key `idem_7e63eb…` in the protocol contract test |

## What the builder copies vs. requires

- **Copied from the observation:** `correlationId`, `causationId`/`observationEventId` (= `eventId`), `task.firstMateTaskId` (= `source.taskId`), `task.repository`, `mission.groundingEpisodeId`, `currentPrompt`, and normalized `evidence` → `constraints.evidenceRefs`.
- **Caller-supplied routing intent:** `mission.summary`, `executionSurface`, `evidenceState`, `signals`, `correctionEvents`, `constraints.forbiddenScopes`, `routingPolicy.maxCandidates`.
- **Fixed invariants:** `constraints.rawTranscriptIncluded=false`, `routingPolicy.crossSurfaceFallbackAllowed=false`, `routingPolicy.requireCurrentRegistry=true`, `producer.component="prompt-router-client"`.

## Owned / forbidden

- **Owned:** `tooling/firstmate/harness/routing/**`, routing-request builder assertions in the existing protocol contract test, this phase map, and its registry membership.
- **Forbidden:** routing-decision consumer, prompt dispatch, context rollover/automatic transition, prompt selection or registry consultation, crew scheduler/watcher, `fm-send`/`fm-control`/terminal manipulation, live dispatch, credential automation, upstream FirstMate mutation or pin bump, committing machine-local receipts/secrets.

## Proof ceiling

**Reached:** `CONTRACT_STATIC` — deterministic round-trip behind the frozen fixture; fail-closed on invalid contract state.
**Not reached:** runtime, routing-decision/dispatch/rollover, live prompt dispatch. Prompt selection and registry binding remain owned by Prompt Kit.

## Validation

```text
python tests/test_fm_asb_promptkit_protocol_contract.py
python tests/test_public_plan_contracts.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
git diff --check
```

## Successor (RRB-03)

Phase 3 routing-decision consumer and prompt-dispatch require a new bounded
sprint declaration; they are out of this seam's mutation scope.
