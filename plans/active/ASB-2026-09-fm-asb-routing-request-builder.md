# ASB-2026-09 FirstMate→ASB routing-request builder (Phase 3 seam)

Bounded successor to the observation adapter's `OBS-05` handoff. Translates a
correlated `asb.agent-observation/v1` into a `prompt-kit.routing-request/v1`
without selecting prompts, consulting a registry, dispatching, rolling over, or
scheduling crew. This is ASB `cross-product-translation` ownership only.

## Delivered

| Task | Result | Evidence |
|---|---|---|
| RRB-01 builder | **VALIDATED (contract/static)** | `tooling/firstmate/harness/routing/build_routing_request.py` — read-only `build_routing_request()` + CLI |
| RRB-02 fixture pin | **VALIDATED (contract/static)** | Round-trip reproduces frozen `semanticSha256 2c483f5f…` and key `idem_7e63eb…` in the protocol contract test |

## What the builder copies vs. requires

- **Copied from the observation only after validation:** `correlationId`, `causationId`/`observationEventId` (= `eventId`), `task.firstMateTaskId` (= `source.taskId`), schema-valid `task.repository`, `mission.groundingEpisodeId`, schema-valid `currentPrompt`, and schema-valid `evidence` → `constraints.evidenceRefs`; source and output timestamps must be RFC3339.
- **Caller-supplied routing intent:** `mission.summary`, `executionSurface`, `evidenceState`, `signals`, `correctionEvents`, `constraints.forbiddenScopes`, `routingPolicy.maxCandidates`.
- **Fixed invariants:** `constraints.rawTranscriptIncluded=false`, `routingPolicy.crossSurfaceFallbackAllowed=false`, `routingPolicy.requireCurrentRegistry=true`, `producer.component="prompt-router-client"`.

## Owned / forbidden

- **Owned:** `tooling/firstmate/harness/routing/**`, routing-request builder assertions in the existing protocol contract test, this phase map, and its registry membership.
- **Forbidden:** routing-decision consumer, prompt dispatch, context rollover/automatic transition, prompt selection or registry consultation, crew scheduler/watcher, `fm-send`/`fm-control`/terminal manipulation, live dispatch, credential automation, upstream FirstMate mutation or pin bump, committing machine-local receipts/secrets.

## Proof ceiling

**Reached:** `INTEGRATED_CONTRACT_STATIC` — the frozen valid path is preserved, nested repository/evidence/timestamp/prompt inputs fail closed, and the exact candidate passed protocol/interoperability/public-plan/harness/runtime/device-profile plus Windows+Ubuntu automated-floor proof and merged to main as `320998d7c1519370fbecb0cf5da56d4c729be247`.
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

RRB-03 is blocked from consuming stale Prompt Kit PR #450 directly; that route-control-plane donor must be salvaged onto current Prompt Kit main with its unresolved security/correctness findings repaired first.
