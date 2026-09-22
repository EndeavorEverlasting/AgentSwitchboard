# Token Corridor Competitive Decision-Control Plane

**Plan ID:** `ASB-2026-09-TOKEN-CORRIDOR-COMPETITIVE-ARCHITECTURE`
**Status:** Proposed
**Priority:** High
**Pull request:** #346 (draft)
**Planning floor:** AgentSwitchboard `main@d90e5ed457c0657b6016c3ead0c976bf679a8de1`
**Local evidence floor:** NodeWeaver `main@add0fd24cb213afdad4cb082db9ba8af947cc228`; Prompt Kit/Triage `main@c97718247e7b14544d198035dd3cdc07725545a8`
**Working name only:** **Token Corridor** is an architectural/product hypothesis in this plan. This plan does not create or reserve a standalone repository.

## Competitive question

TypeSafe publicly introduced Jev on 2026-09-15 as a System One model: unstructured program state enters; typed probabilistic decisions leave. The competitive question is therefore not “can AgentSwitchboard train a Jev clone faster?” It is:

> What software-factory layer remains distinctive and valuable when fast typed probabilistic judgment is available as a commodity/provider primitive?

This plan answers: **the durable decision-control plane around the primitive**.

## Product boundary

| Surface | Canonical role in the target factory | Explicit non-role |
|---|---|---|
| **Prompt Kit / Evidence Spine** | semantic/workflow policy; acceptance/proof contracts; continuation requirements; reusable prompt/workflow meaning | not live worker runtime; not probabilistic model provider |
| **Token Corridor** *(working name)* | bounded judgment compilation and control: state→typed questions→engine selection→calibrated decision→authority check→decision receipt | not a foundation model; not a scheduler; not an execution runtime; cannot create authorization |
| **AgentSwitchboard** | factory/execution control plane: readiness, execution-adapter selection, dispatch, evidence normalization, durable public coordination | not a second FirstMate crew runtime |
| **FirstMate** | canonical live multi-agent crew/session runtime | not Prompt Kit semantic owner; not Token Corridor decision semantics |
| **NodeWeaver** | candidate semantic-state/topic/recurrence feature provider if refreshed evidence proves unique value | not the universal factory decision engine by assumption |
| **Deterministic code** | calculations, exact policy, permissions, schemas, validators, state transitions, merge/deploy gates | must not be replaced by probabilistic judgment when code can decide exactly |

## Reference matrix

Evidence date: 2026-09-22. Status labels describe the inspected scope only.

| Reference | Relevant mechanism | Evidence state | Disposition |
|---|---|---|---|
| **TypeSafe Jev** — https://typesafe.ai/blog/introducing-system-one-models-and-jev | Typed Choice/Score/Noul-style probabilistic decisions over unstructured state; no text generation; parallel outputs; calibrated confidence intended for software branching | **DOCUMENTED_UNVERIFIED for our workload** — official product docs; no local benchmark yet | **ADAPT** as one decision backend/API shape; **REJECT** racing TypeSafe by training a competing model as the near-term factory strategy |
| **Brainwires/jevwire** — https://github.com/Brainwires/jevwire | Provider-facing DecisionModel abstraction, pure run functions, thresholds, harness hooks, deterministic prefilters; critically, probabilistic judgment cannot emit permission “allow” by default | **OBSERVED_IMPLEMENTED from published repo/spec surfaces** | **ADOPT mechanism**: engine interface, code-before-model, advisory/block/escalate semantics, “model cannot mint authority” invariant |
| **Open-Jev reconstructions** — e.g. https://github.com/kyegomez/open-jev | Shared state encoding + batched typed readout heads; demonstrates Jev-like interface can be reproduced independently without proprietary TypeSafe weights/data | **OBSERVED_IMPLEMENTED / research preview**; not TypeSafe-equivalent | **ADAPT for local/open fallback experiments**, not a production assumption |
| **Agent-Field/SWE-AF** — https://github.com/Agent-Field/SWE-AF | Issue DAG, parallel isolated worktrees, coder/QA/reviewer passes, inner retry loop, issue advisor, outer replanner, integration verifier, runtime/model selection | **OBSERVED/DOCUMENTED_IMPLEMENTED on current public repo surfaces** | **ADAPT** factory-control loops and tiered intelligence; do not duplicate FirstMate crew scheduling |
| **Erik-Koning/agentfactory** — https://github.com/Erik-Koning/agentfactory | Work-order lifecycle, provider abstraction, isolated worktrees, Redis workers, heartbeat/inactivity, crash resume, QA/acceptance stations, cost tracking | **DOCUMENTED_IMPLEMENTED from current public repo** | **ADAPT** recovery/cost/accounting patterns where ASB lacks them; reject mandatory tracker/Redis coupling |
| **OpenHands automation + software-agent-sdk** — https://github.com/OpenHands/automation and https://github.com/OpenHands/software-agent-sdk | Strong ownership split: automation owns **when** (schedule/webhook/run history/dispatch/sandbox lifecycle); Agent Server/SDK owns **what** executes (agents/tools/workspaces/events/API) | **OBSERVED_IMPLEMENTED from current repository boundaries and service docs** | **ADOPT boundary principle**: scheduling, decision, and execution are different owners |
| **Pydantic AI durable execution** — https://pydantic.dev/docs/ai/capabilities/durable_execution/overview/ | Durable runs survive API/application failure and restart; multiple workflow backends; explicitly separates durable run continuation from ordinary conversation storage | **OBSERVED/DOCUMENTED current docs** | **ADAPT** durable transition/resume/idempotency contract; do not build a workflow engine if an existing backend fits |
| **Pydantic AI TypeSafe/Jev provider surface** — https://pydantic.dev/docs/ai/models/typesafe/ | Jev is already exposed through a general agent framework's model/provider layer, with guidance around confidence/threshold usage | **OBSERVED current integration documentation** | **ADOPT strategic signal**: keep Token Corridor provider-neutral; Jev integration should be an adapter, not the product identity |

## What external systems already solve

### Available to emulate externally

- Cheap typed probabilistic judgment over messy state.
- Provider-neutral decision interfaces.
- Confidence thresholds and explicit abstain/escalate policies.
- Factory issue/DAG decomposition and adaptive retry/replan loops.
- Isolated worker worktrees and staged QA/review/verification.
- Scheduler/runtime ownership separation.
- Durable crash/restart continuation.
- Provider/model selection by role or task class.

These are **not** a moat by themselves.

## What AgentSwitchboard already solves internally

- A documented agentic-software-factory architecture with engineer / agent / deterministic-code boundaries.
- Prompt Kit machine inputs, continuation/evidence semantics, and no-human-scheduler policy.
- Triage→ASB consumer and dispatch contracts.
- Provider-neutral execution adapter request/receipt/registry/runner floor.
- FirstMate boundary: ASB deliberately does not become a second live crew scheduler.
- Deterministic validation/test/merge proof surfaces.
- Public machine-readable plans and execution evidence.
- P143 Repository Convergence Planner now exists as an open Prompt Kit implementation lane for multi-repo A+B→C planning.

Therefore the competitive response must reuse those owners rather than launch another orchestration framework.

## Project-specific gap: judgment compilation

The missing product seam is a **decision compiler/control plane** between evidence and execution.

Target flow:

```text
repository/runtime evidence
        ↓
deterministic prefilters / exact policy
        ↓
bounded unresolved judgment
        ↓
Token Corridor decision request
        ↓
engine selection
(rule | Jev | open/local system-one | structured LLM | specialist signal service)
        ↓
typed probability / abstain / escalation
        ↓
AUTHORITY CHECK  ← separate typed grants/policy only
        ↓
deterministic workflow transition
        ↓
AgentSwitchboard execution adapter
        ↓
FirstMate / single-agent / deterministic job
        ↓
typed execution + validation receipt
        ↓
Prompt Kit Evidence Spine continuation
```

### Non-negotiable invariant

**Probability is evidence, not permission.**

A decision engine may recommend, rank, classify, block, abstain, or escalate. It may never manufacture:

- user authorization;
- destructive authority;
- repository merge authority;
- deployment/release authority;
- credential scope;
- external publication/spend authority.

This directly prevents the known defect family where an inferred value becomes an operator-frozen or executable decision merely because a downstream step needs a concrete value.

## Competitive moat hypothesis

If TC-01 through TC-05 prove out, Token Corridor's differentiated value is not “typed output.” It is:

1. **Judgment compilation** — convert large messy factory state into the smallest decision questions needed now.
2. **Intelligence routing** — choose deterministic code, cheap System-One judgment, structured LLM, specialist classifier, or expensive agent according to risk/cost/latency/proof needs.
3. **Authority-aware decisions** — evidence/confidence and permission are independent contracts.
4. **Receipt-linked continuation** — every judgment is correlated with the action/proof it influenced; no giant prose handoff.
5. **Adaptive control loops** — retry/replan/split/escalate can use cheap bounded judgments instead of another full agent turn.
6. **Durable AFK state** — crash/restart/user-only gates resume from stable transition identity without the human reconstructing context.
7. **Provider portability** — Jev can improve the factory without owning the factory.

That is compatible with Jev succeeding commercially.

## NodeWeaver disposition

Current provider truth is `NodeWeaver main@add0fd24cb213afdad4cb082db9ba8af947cc228`. Its README still describes a RAG classifier/topic-emergence product. Historical gap analysis documents substantial unimplemented intelligence work at that point, while later learning docs add correction/training behavior. That does **not** currently establish NodeWeaver as a Jev-equivalent decision model.

**Provisional disposition: NARROW + EVALUATE.**

Do not race Jev by expanding NodeWeaver into a foundation decision model. Instead test whether NodeWeaver contributes **unique semantic features** to factory decisions:

- topic/recurrence clustering;
- similarity/neighborhood evidence;
- long-horizon semantic state;
- correction-derived feature signals.

If those signals do not improve TC-02 benchmark outcomes versus simpler baselines, retire that factory integration idea without harming NodeWeaver's independent product identity.

## Development sequence

### TC-01 — Decision protocol floor
Build the provider-neutral request/receipt and engine interface. Negative fixture: a model confidently says an action is safe/allowed, but no authority grant exists; dispatch must remain forbidden.

### TC-02 — Competitive benchmark
Use real sanitized factory decisions. Compare deterministic rules, structured generative baseline, and Jev-compatible backend where available. Measure correctness, calibration, latency, cost, false-autonomy, and unnecessary-escalation.

### TC-03 — Vertical factory-router slice
Use the decision plane to choose one reviewed ADW/next owner from real ASB/Prompt Kit evidence, then hand execution to existing ASB adapters.

### TC-04 — Adaptive control loops
Insert cheap bounded judgment into ambiguous retry/replan/split/escalate points. Keep exact validator failures deterministic.

### TC-05 — Durable AFK continuation
Prove decision → dispatch → receipt → continuation survives restart and user-only gates without human context shuttling.

### TC-06 — NodeWeaver integration scout
Prototype only semantic-signal value; KEEP/NARROW/ADAPT/RETIRE from measured evidence.

### TC-07 — Product extraction gate
Only then decide whether Token Corridor should become its own repository/product boundary.

## Standalone repository gate

Do **not** create TokenCorridor yet.

Extract from ASB only when one of these is proven:

1. at least two independent real consumers need the same stable decision protocol; **or**
2. it has an independent deployment/runtime/release/security boundary that makes ASB ownership harmful.

Then use Prompt Kit P143 Repository Convergence Planner for any donor→destination migration plan.

## What would invalidate this strategy

Revisit the thesis if:

- factory benchmarks show bounded decisions do not materially reduce cost/latency/agent turns at acceptable error rates;
- calibration under our real distribution is too unstable to set useful thresholds;
- existing ASB deterministic routing already resolves nearly all target decisions;
- a mature external system provides the entire authority-aware decision→execution→receipt→continuation seam with acceptable ownership and portability;
- Token Corridor requires duplicating FirstMate or ASB execution rather than remaining a thin decision plane.

## Proof ceiling

This artifact is a **TRACKED competitive architecture proposal** once committed. It does not prove:

- Jev performance on our factory corpus;
- Token Corridor implementation or runtime value;
- independent commercial differentiation;
- NodeWeaver usefulness to factory decisions;
- live AFK software-factory execution;
- that Token Corridor warrants a separate repository.

Those are the explicit gates in TC-01 through TC-07.
