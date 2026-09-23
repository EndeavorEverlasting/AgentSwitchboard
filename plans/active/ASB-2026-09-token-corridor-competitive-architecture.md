# Token Corridor Competitive Decision-Control Plane — OSS-First Revision

**Plan ID:** `ASB-2026-09-TOKEN-CORRIDOR-COMPETITIVE-ARCHITECTURE`
**Status:** Proposed
**Priority:** High
**Pull request:** #346 (draft)
**Planning floor:** AgentSwitchboard `main@d90e5ed457c0657b6016c3ead0c976bf679a8de1`
**Local evidence floor:** NodeWeaver `main@add0fd24cb213afdad4cb082db9ba8af947cc228`; Prompt Kit/Triage `main@c97718247e7b14544d198035dd3cdc07725545a8`
**Working name only:** **Token Corridor** remains a product/architecture hypothesis. This plan does not create or reserve a standalone repository.

## Reconciliation: the first research pass was incomplete

The first revision of this plan correctly separated bounded judgment from execution authority, but it made a material research error: it treated TypeSafe Jev as the primary decision primitive and surveyed only a few factory-level references. That was insufficient for an OSS-first software-factory decision.

This revision supersedes that baseline.

Before Token Corridor implements commodity infrastructure, the project must compare **open/self-hosted implementations and managed/private comparators at every relevant layer**:

1. typed probabilistic decision engines;
2. model/intelligence routing and gateways;
3. structured generation and constrained decoding;
4. durable workflow / crash-resume execution;
5. agent runtime and software-factory orchestration;
6. sandbox / workspace execution;
7. evaluation, calibration, observability, and tracing.

### OSS-first dependency rule

**A commercial component may be a benchmark comparator or optional adapter, but it must not become required infrastructure unless an exact workload benchmark proves that adequately licensed open/self-hosted candidates fail a named acceptance gate.**

“Provider-neutral” alone is not sufficient. A provider-neutral abstraction can still hide an unnecessarily paid default.

License class must remain explicit:

- **OPEN-PERMISSIVE** — e.g. Apache-2.0, MIT;
- **OPEN-COPYLEFT** — e.g. AGPL;
- **SOURCE-AVAILABLE** — code visible but not OSI open source, e.g. ELv2 or BSL;
- **CLOSED/MANAGED** — proprietary service/runtime.

## Competitive question

TypeSafe introduced Jev publicly on 2026-09-15 after roughly two years in stealth. Jev is a System One decision model: structured/unstructured state plus typed questions in; Choice/Score/Noul probabilities out; all outputs scored in parallel rather than text generated token-by-token.

That release matters. It does **not** establish that TypeSafe is the only available implementation, nor that a paid decision API is necessary.

The corrected question is:

> Which layers of an AFK software factory are already available as credible open/self-hosted infrastructure, which managed systems merely package those layers, and what remaining integration/control seam is genuinely worth building?

## Cross-repository convergence binding

This AgentSwitchboard plan now participates in shared convergence identity:

`AFK-FACTORY-CONVERGENCE-2026-09-22`

- **Canonical convergence owner:** `EndeavorEverlasting/TokenCorridor`, TokenCorridor PR #1, `plans/active/AFK-FACTORY-CONVERGENCE.plan.json`.
- **Prompt Kit interface owner:** `EndeavorEverlasting/web-excel-repair-triage`, Prompt Kit PR #633, `docs/plans/AFK_FACTORY_INTERFACE_CONVERGENCE_SPRINT_MAP.md`.
- **AgentSwitchboard execution owner:** this plan / PR #346.

### Ownership correction

Prompt Kit is the **human↔AFK interface foundation**. AgentSwitchboard must not bypass it by inventing a competing operator-facing workflow language. ASB consumes machine-addressable interface/continuation state and owns execution readiness, adapter selection, dispatch, receipts, validation/integration evidence, and proof ceilings.

TokenCorridor owns the typed cross-repository bounded-decision/successor-transition seam. It does not replace ASB execution ownership.

### Parallel closeout

PR #346 may close independently of Prompt Kit's current P55/P66/P143/routing convergence. After each repository integrates its local closeout, TokenCorridor refreshes exact main SHAs and begins the first cross-repository tracer slice.

### Factory Topology successor

The visual frontier is not a new dashboard. It extends Prompt Kit's already-integrated Prompt Topology doctrine:

`renderer-neutral semantic truth → deterministic projection → immersive read-only presentation`

Factory Topology will project:

- Prompt Kit **interface** state;
- TokenCorridor **decision/transition** state;
- AgentSwitchboard **execution** state;
- shared **proof** state.

Stable correlation identity joins the planes. Coordinates, color, proximity, camera position, and visual grouping never create authorization, execution state, or proof.


## Corrected architecture boundary

| Surface | Canonical role | Must not become |
|---|---|---|
| **Prompt Kit / Evidence Spine** | semantic/workflow policy; acceptance/proof contracts; continuation requirements | model runtime or crew scheduler |
| **Token Corridor** *(working name)* | compile unresolved state into bounded judgments; select a decision/router backend; apply thresholds and authority rules; emit typed decision receipts | a Jev clone, generic gateway, workflow engine, sandbox service, or permission oracle |
| **AgentSwitchboard** | readiness, provider/execution-adapter selection, dispatch, public plans, evidence normalization, integration governance | a second FirstMate crew runtime or a duplicate generic orchestration platform |
| **FirstMate** | live crew/session runtime and multi-agent execution | semantic policy or decision-model owner |
| **NodeWeaver** | optional semantic recurrence/topic/similarity signal source if benchmarked value exists | universal decision model by assumption |
| **Open substrates** | routing, constrained decoding, durable execution, sandboxing, evaluation/observability where adequate | hidden proprietary dependencies |
| **Deterministic code** | permission, schemas, exact policy, tests, arithmetic, state transitions, merge/deploy gates | probabilistic guesswork |

## Layer 1 — typed probabilistic decision engines

### Closed comparator: TypeSafe Jev

**TypeSafe Jev**
- Source: https://typesafe.ai/blog/introducing-system-one-models-and-jev
- License/deployment: **CLOSED/MANAGED**
- Shape: one request contains program state plus multiple Choice/Score/Noul questions; outputs are typed probability distributions.
- Claimed price at launch: $0.042 / MTok input; output too cheap to meter.
- Claimed advantages: parallel outputs, calibrated probabilities, low latency, no schema/type errors.
- Important caveat: TypeSafe's workflow evaluations and calibration claims are vendor-produced until reproduced on our corpus.

**Disposition:** COMPARE, OPTIONAL ADAPTER. Never a prerequisite.

### Open candidate: Laya

**Laya — artificial-intelligence-works/laya-jev**
- Source: https://github.com/artificial-intelligence-works/laya-jev
- License: **OPEN-PERMISSIVE — Apache-2.0**
- Architecture: non-autoregressive encoder decision engine; Choice/Score/Noul.
- Published checkpoints include ModernBERT-large and multilingual mmBERT variants; local/self-hosted.
- Built-in router selects language/checkpoint before inference.
- Important self-reported finding: the base checkpoints are weak zero-shot on the typed-decisions benchmark; the specialized fine-tuned checkpoint is materially better. Treat specialization as part of the deployment design, not a footnote.
- The repo publishes a fine-tuning notebook and calibration workflow.

**Disposition:** ADOPT AS FIRST OSS GENERAL CANDIDATE FOR BAKEOFF, not automatic production winner.

### Open candidate: Mapika/decider

**decider**
- Source: https://github.com/Mapika/decider
- License/model card: **OPEN-PERMISSIVE — Apache-2.0**
- Models: ~0.8B, 2B, 35B-A3B plus vision variant.
- Main 2B path: state/JSON up to 32k tokens, Choice with up to 255 options, Score, Noul, abstention, TypeSafe-compatible `/v1/systemone`.
- Uses one-pass readouts instead of text generation and includes calibration-aware training/RL experiments.
- Its own JevBench table shows an important limitation: the 2B model is strong on some routing/trap families but weak on long policy, multihop, and temporal/numeric reasoning; hard-tier calibration is also imperfect.

**Disposition:** ADOPT AS BROADER/HEAVIER OPEN CHALLENGER. Useful when Laya's context/task limits matter.

### Open candidate: OpenDecision

**OpenDecision**
- Source: https://github.com/deepanwadhwa/OpenDecision
- License: **OPEN-PERMISSIVE — Apache-2.0**
- Default backend: ModernBERT large zero-shot NLI/classification; local, no text generation.
- Supports Choice/Noul/Score plus Relation; can retrieve evidence passages from documents.
- Provides Python, FastAPI, and TypeSafe-compatible `/v1/systemone`.
- Explicit repo caveat: current model scores are **uncalibrated** and thresholds must be validated on the user's own data.

**Disposition:** ADOPT AS LOW-COMPLEXITY NLI/EVIDENCE BASELINE. Do not promote its raw scores to calibrated automation confidence.

### Open candidate: Shalimov04/open-jev

**open-jev — task distillation**
- Source: https://github.com/Shalimov04/open-jev
- License: **OPEN-PERMISSIVE — MIT**
- Mechanism: define one stable decision task; a local teacher produces soft labels; distill into ~140M mmBERT-small; fit temperature/bias calibration on held-out rows; serve a TypeSafe-compatible endpoint.
- This is a fundamentally different strategy from one universal Jev: **compile a recurring prompt/decision into a tiny classifier**.

**Disposition:** HIGH-VALUE ADAPT for stable repeated factory decisions such as known route families, defect classification, or evidence-sufficiency gates. Not a universal dynamic-question replacement.

### Open candidate: Verdict / OpenJev

**Verdict-open-jev**
- Source: https://github.com/Heman10x-NGU/Verdict-open-jev
- License: **OPEN-PERMISSIVE — Apache-2.0**
- Architecture: ~151M ModernBERT/GLiClass family, non-autoregressive typed decisions, local/browser WebGPU surfaces, calibration artifacts and tests.
- Published accuracy/calibration/latency numbers are author-produced and must be reproduced before they can drive an autonomy threshold.

**Disposition:** ADOPT AS LOW-FOOTPRINT CHALLENGER.

### Open compatibility baseline: openjev-sglang

**openjev-sglang**
- Source: https://github.com/ekzhang/openjev-sglang
- Shape: TypeSafe/Jev HTTP surface over a large open Qwen model using prefill/candidate scoring.
- Default example is GPU-heavy (B200-class in its Modal deployment) and is not a cheap-local default.
- Useful because it demonstrates that a Jev-shaped API does not imply Jev-specific weights or training.

**Disposition:** ADAPT AS API/ARCHITECTURE REFERENCE; REJECT as initial low-cost deployment default.

### Structured local LLM baseline

A local open model can be constrained to finite/typed output without a closed structured-output API:

- **XGrammar** — https://github.com/mlc-ai/xgrammar — open constrained decoding for JSON, regex, CFG; integrated into vLLM/SGLang/MLC/TensorRT-LLM.
- **Outlines** — https://github.com/dottxt-ai/outlines — provider-independent structured generation including local vLLM/MLX paths.
- **Guidance** — https://github.com/guidance-ai/guidance — regex/CFG constraints and finite `select()`.
- **Instructor** — schema/validation/retry wrapper useful at the application edge.

These solve **output admissibility**, not calibrated epistemic confidence. They are a baseline/challenger, not equivalent evidence to a calibrated decision model.

### Existing independent evidence

**sysone-bench**
- Source: https://github.com/instax-dutta/sysone-bench
- Current evidence uses byte-identical states/questions across Laya and Jev.
- Results are mixed by task family: Jev leads several triage/moderation/multi-class/multilingual sets; Laya leads AG News and MNLI; some score tasks remain weak/miscalibrated for both.
- This independently demonstrates why “Jev wins” and “open wins” are both too coarse.

**Token Corridor rule:** benchmark on our exact factory decisions.

## Layer 2 — model / intelligence routing

### Open routing mechanisms

| Project | License / posture | Mechanism | Token Corridor disposition |
|---|---|---|---|
| **Semantic Router** — https://github.com/aurelio-labs/semantic-router | MIT; can run fully local | embedding/vector semantic routes; optional local HuggingFace + llama.cpp | **ADOPT/ADAPT** for cheap high-confidence intent/tool routes |
| **RouteLLM** — https://github.com/lm-sys/RouteLLM | Apache-2.0 | learned strong-vs-weak routing; OpenAI-compatible server; evaluation framework | **ADAPT** for model-tier routing experiments |
| **UIUC LLMRouter** — https://github.com/ulab-uiuc/LLMRouter | MIT | 16+ router families: KNN/SVM/MLP/MF/Elo/graph/BERT/hybrid, plus benchmark/training pipeline | **ADOPT AS ROUTER RESEARCH/EVAL SUBSTRATE**, not reimplement its research stack |
| **LiteLLM Router** — https://github.com/BerriAI/litellm | open gateway ecosystem | weighted, cost, latency, usage, least-busy, retries/fallbacks, session affinity | **ADAPT AS GATEWAY/RELIABILITY MECHANICS**; not the semantic decision owner |

### Managed comparators

**Not Diamond**
- https://www.notdiamond.ai/
- https://www.notdiamond.ai/pricing
- **CLOSED/MANAGED**
- Focuses directly on coding-agent model selection using payload semantics, session outcomes, cache/compaction/subagent signals; current list price is a fixed router fee per routed token volume.
- Useful comparator for the specific “which coding model/reasoning effort now?” problem.

**OpenRouter Auto Router**
- https://openrouter.ai/blog/announcements/introducing-the-new-auto-router/
- **CLOSED/MANAGED SERVICE**
- Current 2026 Auto Router uses recent OpenRouter market/spend behavior and task classification to choose models.
- Useful as a market-driven baseline, not a canonical policy owner.

### Routing conclusion

Do **not** build a router research framework inside Token Corridor.

Token Corridor should own the policy question and typed route receipt. It may call a deterministic route, Semantic Router, RouteLLM/LLMRouter model, or a managed router. AgentSwitchboard remains the execution-adapter owner.

## Layer 3 — durable execution and crash/restart continuation

The first plan incorrectly treated “durable AFK continuation” as mostly a local architecture problem. Mature open infrastructure exists.

| Project | License / posture | Useful mechanism | Disposition |
|---|---|---|---|
| **DBOS** — https://github.com/dbos-inc/dbos-transact-py | MIT | lightweight Python durable workflows/queues backed by Postgres; checkpoint/recovery without separate orchestration service | **FIRST EVALUATION TARGET** for ASB because Python + Postgres is a low-infrastructure fit |
| **Hatchet** — https://github.com/hatchet-dev/hatchet | MIT | Postgres-backed durable task/agent orchestration, retries, queues, DAGs, events, monitoring | **ESCALATION CANDIDATE** when distributed worker scheduling is needed |
| **Temporal** — https://github.com/temporalio/temporal | MIT | mature durable workflow/service model, retries/event history/workers/task queues | **ESCALATION CANDIDATE** for stronger distributed durability at higher operational cost |
| **Trigger.dev** — https://github.com/triggerdotdev/trigger.dev | open/self-hosted platform | long-running AI tasks, retries, queues, pause/resume, tracing | **ADAPT** if TS/application deployment posture fits |
| **Inngest** — https://github.com/inngest/inngest | open/self-host path | event/cron/webhook durable functions and step orchestration | **ADAPT/DEFER** |
| **LangGraph checkpoints** | OSS libraries | per-superstep persistence, pending-write recovery, durability modes | **ADAPT** only if graph runtime becomes a chosen application owner |
| **Restate** — https://github.com/restatedev/restate | **SOURCE-AVAILABLE BSL 1.1**, not OSI open source | durable RPC/state/workflows | **COMPARE**, do not label OSS |

**Rule:** Token Corridor/ASB should define idempotency, correlation, and proof contracts; the persistence/replay engine should be an adopted substrate unless a concrete incompatibility is proven.

## Layer 4 — agent execution, factory orchestration, and worker control

### Open systems already occupying the “software factory” lane

**SWE-AF**
- https://github.com/Agent-Field/SWE-AF
- Issue DAG rather than agent DAG; parallel work by dependency level; coder → QA/reviewer → synthesizer; inner retry, middle advisor/split, outer replanning; crash resume endpoint.
- **ADAPT the adaptive-control mechanisms.** Do not duplicate FirstMate crew execution.

**AgentFactory**
- https://github.com/Erik-Koning/agentfactory
- MIT.
- Backlog → development → QA → acceptance; distributed worker pool; Git worktrees; heartbeat/inactivity; crash recovery/session resume; per-session cost.
- **ADAPT fleet accounting/recovery patterns; do not rebuild the whole product inside ASB.**

**OpenHands**
- https://github.com/OpenHands/OpenHands
- Self-hostable agent/canvas/runtime ecosystem.
- Strong architectural precedent for separating automation/scheduling from agent server/runtime.
- **ADOPT boundary principle.**

**SWE-agent / SWE-ReX**
- SWE-agent focuses the coding worker; SWE-ReX abstracts the execution environment.
- **ADOPT separation of agent logic from runtime infrastructure.**

**goose / Aider**
- Useful open worker implementations/provider abstractions, not software-factory control planes.
- **KEEP AS PLUGGABLE WORKER OPTIONS**, not local reinvention targets.

### Managed/private comparators

**Factory**
- https://factory.ai/product/software-factory
- Explicitly sells model-independent full-SDLC software-factory automation: triage, planning, execution, review, release, model routing.

**Cursor Cloud Agents**
- https://cursor.com/docs/cloud-agent
- Isolated cloud VMs/branches, parallel agents, multi-repo environments, event/schedule subscriptions, PR babysitting, environment builds/snapshots.

**GitHub Copilot cloud/third-party coding agents**
- GitHub-native asynchronous issue/prompt → branch/PR workers in protected cloud environments.

These are meaningful competitive products, but their headline mechanics — parallel workers, isolated branches, cloud environments, PR iteration — already have open analogues.

**Token Corridor moat cannot be “we run multiple coding agents.”**

## Layer 5 — sandbox / workspace infrastructure

### Open/self-hosted

**SWE-ReX**
- https://github.com/SWE-agent/SWE-ReX
- MIT.
- One runtime interface across local shell, Docker, AWS/Fargate, Modal and other environments; many parallel sessions.
- **ADOPT/ADAPT as runtime abstraction reference.**

**E2B runtime**
- https://github.com/e2b-dev/runtime
- Apache-2.0.
- Firecracker microVM runtime/control-plane stack; public cloud, enterprise deployment, and self-host/single-machine runtime share the open implementation.
- **ADOPT/ADAPT if microVM isolation is required.**

**Existing FirstMate/worktrees**
- Already own a lighter isolation path for many repository-writing tasks.
- Do not introduce a VM merely because one is available.

### Managed/source-history comparators

**Vercel Sandbox**
- Managed Firecracker microVM service; SDK/CLI available, infrastructure managed.
- **OPTIONAL COMPARATOR**, not required.

**Daytona**
- Current core development moved private in June 2026.
- Historical AGPL code remains public; community fork **Nightona** continues that last open line.
- This is a concrete vendor-governance risk to consider when choosing foundational infrastructure.

## Layer 6 — evaluation, calibration, tracing, and observability

### Open/self-hosted candidates

**Opik**
- https://github.com/comet-ml/opik
- Apache-2.0 full platform.
- Traces, datasets, experiments, code/LLM evaluation, production monitoring; self-hostable backend/UI.
- **FIRST FULL-OPEN EVAL/TRACE CANDIDATE.**

**Langfuse**
- https://github.com/langfuse/langfuse
- MIT core; explicit commercially licensed `ee/` modules.
- Tracing, datasets, experiments, evaluations, prompt management; self-hostable core.
- **ADOPT/ADAPT** if its core feature split fits.

**Phoenix**
- https://github.com/Arize-ai/phoenix
- Current license is **Elastic License 2.0 — SOURCE-AVAILABLE, not OSI open source**.
- Strong tracing/eval/dataset/experiment implementation, but license class matters.
- **COMPARE/ADAPT only with explicit license acceptance.**

### Managed comparator

**LangSmith**
- Managed commercial platform; self-host/hybrid is an Enterprise-tier capability.
- Strong benchmark for polished tracing/evaluation/deployment UX.
- **COMPARE**, not required.

### Observability ownership rule

Token Corridor owns **decision/evidence semantics and receipts**. An observability platform stores/displays traces and experiments. It must never become the only source of proof or workflow authority.

## Full stack: open-first default vs managed comparator

| Layer | Open/self-hosted default evaluation set | Managed/private comparator | Current plan |
|---|---|---|---|
| typed decision | Laya; OpenDecision; decider; task-distilled open-jev; Verdict; constrained local LLM | TypeSafe Jev | **open bakeoff first** |
| semantic/model routing | Semantic Router; RouteLLM; LLMRouter; LiteLLM mechanics | Not Diamond; OpenRouter Auto | **do not build router research from scratch** |
| structured output | XGrammar; Outlines; Guidance; Instructor validation | vendor structured-output APIs | **reuse open constraints** |
| durable continuation | DBOS first; Hatchet/Temporal escalation; Trigger/Inngest/LangGraph as fit warrants | managed workflow clouds | **adopt substrate** |
| coding/factory | SWE-AF; AgentFactory; OpenHands; FirstMate; worker adapters | Factory; Cursor; GitHub cloud agents | **ASB/FirstMate integrate, do not clone** |
| sandbox | worktrees; SWE-ReX; E2B | Vercel Sandbox; current Daytona | **reuse open runtime abstraction** |
| eval/observability | Opik; Langfuse core | LangSmith; enterprise platforms | **open self-host first** |

## What is actually left to build

After subtracting the open ecosystem, Token Corridor becomes **smaller and more defensible**.

### Project-specific gap: evidence/authority-aware judgment composition

The likely unique seam is not the classifier, router, workflow engine, sandbox, or dashboard.

It is the compiled control contract connecting them:

```text
repository/runtime evidence
        ↓
exact deterministic policy
        ↓
identify the smallest unresolved judgment
        ↓
decision request + state/action fingerprint
        ↓
select engine by measured policy
  ├─ deterministic rule
  ├─ semantic router / NLI
  ├─ Laya / decider / Verdict / distilled task model
  ├─ constrained local LLM
  ├─ optional managed Jev/router
  └─ expensive reasoning agent
        ↓
typed probability / abstain / recommendation
        ↓
AUTHORITY CHECK — independent evidence only
        ↓
durable workflow transition
        ↓
AgentSwitchboard execution adapter
        ↓
FirstMate / worker / deterministic process
        ↓
execution + validator receipts
        ↓
Prompt Kit Evidence Spine continuation
```

### Non-negotiable invariant

**Probability is evidence, not permission.**

No open or closed model can manufacture:
- user authorization;
- destructive authority;
- merge authority;
- deployment/release authority;
- credential scope;
- spend/publication authority.

A probability can influence a policy that already has authority. It cannot create that authority.

## Revised competitive moat hypothesis

If the implementation proves useful, Token Corridor's defensible value is the combination of:

1. **Judgment compilation** — automatically identify the minimum fuzzy questions remaining after deterministic evidence is exhausted.
2. **Evidence-aware engine selection** — choose rule/NLI/tiny specialized model/System-One/router/frontier model based on measured task family, cost, latency, privacy, hardware, and proof requirements.
3. **Authority separation** — confidence and permission are orthogonal contracts.
4. **Receipt-linked composition** — each decision records state/action fingerprint, model/version, calibration provenance, and the downstream transition it influenced.
5. **Factory-specific adaptive control** — use cheap judgment at retry/replan/split/escalate and proof-sufficiency boundaries without another giant agent turn.
6. **Durable AFK continuation** — selected open durability substrate resumes the exact workflow without operator context shuttling.
7. **Backend commoditization as an advantage** — Laya/decider/Jev/router vendors can improve without changing the surrounding factory contract.
8. **Regression-backed autonomy policy** — autonomy thresholds are derived from versioned factory corpora and negative authorization fixtures, not vibes.

## NodeWeaver: narrower question

Do not turn NodeWeaver into a Jev clone.

Evaluate whether it contributes factory-specific signals that the open decision candidates do not cheaply recover:
- recurrence/topic-cluster state;
- semantic neighborhood history;
- cross-run drift/emergence signals;
- correction-derived long-horizon features.

If those features do not improve the Token Corridor benchmark, keep NodeWeaver independent.

## Revised execution sequence

### TC-00 — full reference floor — COMPLETED
Open and managed alternatives are now mapped across all major layers. The prior Jev-centric research floor is superseded.

### TC-00A — OSS decision-engine compatibility spike — READY
Create a small versioned factory-decision corpus. Run byte-identical fixtures through:
1. deterministic baseline;
2. Laya;
3. OpenDecision;
4. at least one of decider or Verdict;
5. task-distilled open-jev for one stable decision family;
6. constrained local LLM baseline.

Jev is optional only if a credential already exists.

Collect:
- accuracy/agreement;
- Brier/ECE where probabilities are meaningful;
- abstention/coverage;
- p50/p95;
- model/load memory and hardware;
- cold-start;
- failure cases;
- exact model/revision/config.

### TC-00B — open support-substrate selection — READY
Do targeted compatibility spikes instead of building commodity infrastructure:
- routing: Semantic Router / RouteLLM / LLMRouter / LiteLLM mechanics;
- durability: DBOS baseline, Hatchet/Temporal escalation;
- runtime: SWE-ReX abstraction + current FirstMate/worktree path; E2B only if VM isolation is required;
- eval/trace: Opik or Langfuse core.

### TC-01 — decision protocol floor
Only after TC-00A/B evidence. The first proven backend must be open/local. A Jev adapter may exist but cannot be required.

### TC-02 — workload-specific competitive benchmark
Expand the same corpus. Managed backends may enter only as comparators. Select per-decision-family winners, not one global “best model.”

### TC-03 — vertical factory-router slice
Evidence → deterministic prefilter → open bounded judgment → authority gate → existing ASB dispatch → execution receipt.

### TC-04 — adaptive control loops
Apply bounded judgment to ambiguous retry/replan/split/escalate/next-owner transitions while keeping deterministic failures deterministic.

### TC-05 — durable AFK continuation
Use the selected open durability substrate. Prove interruption/restart and user-only quiescence without reconstructing context.

### TC-06 — NodeWeaver signal scout
Measure whether its semantic-history features improve TC-02 results.

### TC-07 — standalone product extraction gate
Only extract Token Corridor from ASB after two independent real consumers or a genuinely independent runtime/release/security boundary proves the separation.

## What we explicitly will not build unless evidence reverses the decision

- another generic semantic router;
- another LLM gateway;
- another grammar-constrained JSON engine;
- another durable workflow runtime;
- another sandbox platform;
- another generic coding agent;
- another multi-agent crew scheduler;
- another LLM observability dashboard;
- a general System-One foundation model merely because Jev exists.

Those are solved or crowded layers.

## What would invalidate the current Token Corridor thesis

Revisit the plan if:
- open decision engines and constrained local models already provide the full evidence→authority→transition contract with no meaningful local seam;
- the factory decision corpus shows nearly all useful routing is deterministic;
- bounded judgments do not materially reduce expensive model calls or human interventions;
- calibration is unstable enough that confidence-based automation is unsafe;
- existing AgentSwitchboard/Prompt Kit contracts already encode the proposed “decision compiler” without a missing executable owner;
- a mature open project implements the entire seam more cleanly and can be adopted instead.

## Proof ceiling

This document is a **TRACKED OSS-first competitive architecture proposal**.

It proves:
- the prior Jev-centric research pass was corrected;
- credible open alternatives exist in every major software-factory substrate layer;
- paid Jev and managed software-factory services are not architectural prerequisites;
- specific adoption/bakeoff work is defined before local reinvention.

It does **not** prove:
- any open engine wins our factory corpus;
- Jev loses our factory corpus;
- a selected router/durable engine/sandbox/eval stack is production-ready on our hardware;
- Token Corridor runtime value;
- NodeWeaver integration value;
- live AFK operation;
- a standalone Token Corridor repository boundary.


## FrontierAgent runtime substrate — clone/fork and wrap first

**Pinned donor:** `ApodexAI/FrontierAgent@9e533db6f6c34d16037ee5ec964c479d0eb51cde`
**License:** Apache-2.0
**Disposition:** ADAPT as an AgentSwitchboard execution runtime; keep it independently pinned/forked until evidence justifies selective extraction.

FrontierAgent already supplies several pieces that AgentSwitchboard should stop trying to reinvent: workflow graphs (`PipelineSpec`), a domain-neutral ReAct loop, observer/intervention hooks, explicit tool registration, AgentBus, bounded Agent Team fan-out through `SpawnGuard`, sandboxed inputs/workspace/outputs, checkpoint/trace/resume/revert, a task board, and a usable TUI.

### Ownership boundary

- **AgentSwitchboard remains outer control plane:** admission, adapter choice, authority, cross-run worker/token/time budgets, tool/capability eligibility, normalized receipts, integration/proof state.
- **FrontierAgent becomes an inner execution runtime:** one admitted run may use ReAct or Agent Team and may schedule bounded sub-agents inside the ASB envelope.
- **TokenCorridor remains decision/transition owner:** FrontierAgent does not decide whether an action is permitted.
- **Prompt Kit remains semantic/UI owner:** FrontierAgent task-board/TUI state may be projected, but it does not replace P66/work-ledger or Evidence Spine truth.

### Integration order

1. **TC-FA0 — source/license boundary (tracked; integration pending).** Pin the exact upstream commit and preserve Apache-2.0 obligations; no source copy. Mark complete only after the owning plan is integrated.
2. **TC-FA1 — vanilla runtime proof.** Clone/fork the pin, run frozen install + upstream pytest/ruff, then one ReAct and one Agent Team smoke and retain checkpoint/trace/output identities.
3. **TC-FAC — execution-contract extension.** The current v1 request/receipt carries neither worker/token ceilings nor an action fingerprint. Add a versioned authority-binding + execution-envelope contract with compatibility and fail-closed negative fixtures before the FrontierAgent adapter can claim either invariant.
4. **TC-FA2 — ASB adapter.** Prefer the stable `frontier_agent` import/plugin seam for long-term integration; use CLI/TUI black-box execution first where that shortens proof. Add observer bridges for authority/boundary/receipt shaping, explicit tool mapping, and ASB→SpawnGuard budgets.
5. **TC-FA3 — correlated tracer.** Dispatch one TokenCorridor successor through ASB into FrontierAgent and normalize the result back into factory proof/continuation.
6. **Prompt Kit binding.** Keep backend-specific details diagnostic; present generic execution/proof state and later project run/task data into Factory Topology.

### Hard guards

- `--yes` is **not** blanket AFK authority. Typed ASB authority + action fingerprint must still match.
- Never let both ASB and FrontierAgent independently multiply worker fan-out without a shared declared budget.
- FrontierAgent tool-module presence does not imply admission; map only explicit ASB capabilities.
- Preserve fail-closed sandboxing; do not fall back to unisolated host execution.
- Do not solve Git/GitHub access by exposing the operator's entire home/SSH/config tree to the runtime.
- Keep benchmark/eval code optional; production runtime must not depend on benchmark packages.

### Extraction rule

The target is one **product experience**, not necessarily one physical codebase on day one. Keep the fork/wrapper boundary while it works. Extract or upstream-modify only the specific runtime surfaces that measured latency, packaging, observability, or UX evidence proves cannot be handled through adapters/plugins.

### Proof ceiling

This update proves the source pin, licensing posture, and planned runtime boundary only. It does not prove a local FrontierAgent runtime, adapter compatibility, or end-to-end AFK execution.
