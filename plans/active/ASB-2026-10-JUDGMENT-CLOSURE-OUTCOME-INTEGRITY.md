# P04 — Judgment Closure + Outcome Integrity

**Plan ID:** ASB-2026-10-JUDGMENT-CLOSURE-OUTCOME-INTEGRITY
**Public canonical owner:** EndeavorEverlasting/AgentSwitchboard — operational harness admission, not Prompt Kit definitions
**Upstream prompt owner:** TokenCorridor Prompt Kit, prompt-invocation-upstream/v1 (P04 factoring, P07 execution, P82 empirical refinement)
**Current execution host:** connected GitHub provider from current chat; hosted CI validates code; Cursor/OpenCode local consumer requires separate runtime proof.
**Status:** implementation being built; CI convergence and real consumer adoption are separate proof gates.

## What the operator recognized

An AI received an implementation-related request and substituted documentation about making software for working software. A sophisticated-looking handoff concealed unresolved design choices and transported the work to a different agent. That is not a problem of prompt length; it is a failure of judgment closure and outcome integrity.

Six detectable defects:
1. Labor transference: delegate architecture instead of bounded implementation.
2. Transport obscurity: handoff hides contract or depends on an inaccessible branch.
3. Open decisions: mechanism, ownership, contingencies and proof are undecided.
4. Abstraction compression: "just implement" hides unresolved engineering choices.
5. Outcome substitution: a plan is portrayed as the implemented deliverable.
6. Ledger without enforcement: completed checkboxes lack admission rules and a validator.

**Goal:** make these failures difficult to misclassify with a publicly usable contract and deterministic evaluator. Neither model verbosity nor a passing structural check proves judgment quality, creative insight, consciousness, empathy, or an actual production result.

## Owner decision

| Surface | Canonical authority |
| --- | --- |
| P04, P07, P82 source and prompt definitions | TokenCorridor upstream Prompt Kit |
| Shared handoff admission and outcome-integrity evaluator | AgentSwitchboard operational harness (this repo) |
| Agent execution and host permissions | Existing Switchboard adapter and receiving repo harness |
| Work Graph, cron, isolate and convergence | AFK Factory / AwayWorks consumer |
| GitHub, cloud schedulers, external providers | Actual provider state |
| User goals and high-risk authorization | Operator |

TokenCorridor is private; a universal public plan stored only there would not be anonymously readable. This public AgentSwitchboard carrier contains no private prompt bodies, secrets, or personal work data. Authorized agents resolve exact prompt content via upstream prompt-invocation-upstream/v1; agents without such access must report an evidence/access blocker rather than invent P04 text.

No competing prompt registry, scheduler, opinion ledger, or agent runner is created.

## Judgment closure, formally

A material architectural decision must be classified as one of three states:

- **CLOSED:** selected mechanism, source-backed rationale, owner and a credible rejected alternative.
- **CONDITIONAL:** reproducible probe, falsifier, at least two distinct observations each mapped to a prescribed action and proof, plus bounded fallback.
- **UNRESOLVED:** non-admissible for READY_HANDOFF/COMPLETE; may be reported honestly as PARTIAL.

Every work unit binds to these decisions, an execution host, named owned/forbidden scope, evidence and proof gate. Work that is both safe and authorized in the current execution runtime must not be passed to Cursor merely because a handoff seems convenient.

**Structural completeness is not semantic correctness.** The evaluator can enforce decision relationships, not determine whether an agent's evidence is true, whether its architecture is wise, or whether completed software works. Independent code reviews, tests, provider readbacks and user-outcome checks remain required.

## Outcome substitution table

| User asks for | Agent delivers | Claim | Expected result |
| --- | --- | --- | --- |
| Plan | Plan | COMPLETE | Structurally admissible with real citations |
| Implementation | Plan | COMPLETE | Reject substitution |
| Implementation | Plan | PARTIAL | Allowed only when safely executable work is not withheld |
| Implementation | Implementation | COMPLETE | Admit structurally only; external implementation proof still needed |
| Deployment | Implementation | COMPLETE | Reject substitution/proof floor |
| Any | Any | READY_HANDOFF with open decisions | Reject |

## Formulaic probes for holistic and creative judgment

Force distinct challenges, not alleged internal emotions:

1. Counterfactual: what fact would reverse this decision?
2. Second-order consequences: what burden follows success?
3. Inversion: how would we deliberately make this solution fail?
4. Authority/privacy: who is affected by an incorrect or unauthorized action?
5. Opportunity cost: which already-owned mechanism makes invention wasteful?

The first three are mandatory fields for implementation/deployment cases. Content quality still requires semantic review. Stakeholder concerns, risk tolerance, future consequences and emotional impact can be modeled as measurable constraints and test scenarios without claiming a machine experiences human emotion.

## P04 execution and parallel ownership

| Gate | Host | Owned surface | Acceptance |
| --- | --- | --- | --- |
| G0 — establish ownership, prompt inputs and dependency graph | CURRENT_CHAT_RUNTIME with GitHub provider | this public plan | exact-source authority and safety boundaries |
| G1 — build versioned contract and evaluator | CURRENT_CHAT_RUNTIME with GitHub provider | tooling/harness/operational/judgment-closure/ | executable admission, explicit errors |
| G2 — build adversarial canaries | CURRENT_CHAT_RUNTIME with GitHub provider | tests/test_judgment_closure.py | negative and positive fixtures |
| G3 — converge registry, CI and proof | CURRENT_CHAT_RUNTIME plus CI_OR_REMOTE_RUNNER | plans/plan-registry.json and .github/workflows/judgment-closure.yml | exact-head check status and original public-plan validator |
| G4 — connect outgoing handoff producer | LOCAL_AGENT_RUNTIME when available | selected existing producer seam | observed admission call and persisted typed receipt |
| G5 — independent semantic/outcome testing | CI_OR_REMOTE_RUNNER / local host | verified real/replayed handoffs | false-admission and operator-correction rates |

G1 and G2 are dependency-ready parallel width two after G0's shared contract. This chat can perform remote file writes, but no independent parallel coding workers were observed. Claiming observed parallelism would be false. G3 is serialized convergence. No private GitHub identifiers or workstation-specific evidence belong in this public plan.

## Required proof

- A long, impressive handoff cannot be called a complete software delivery without implementation proof.
- Authorized current-runtime work left undone is detected as premature delegation.
- Closed decisions contain evidence, selection and rejected alternatives.
- Conditional decisions contain probe, falsifier, two distinct outcome/action/proof branches, and fallback.
- Unresolved decisions fail a claimed ready terminal handoff.
- Missing or fabricated evidence IDs fail closed.
- Honest partial status remains allowed when authority or runtime is truly unavailable.
- Adversarial perspectives are recorded, but their truth is not assumed.
- The original public-plan schema/registry validators continue to pass.
- CI readback, integration readback and local producer use have separate evidence classes.

**Explicit falsifier:** a syntactically complete but semantically foolish architectural choice may pass the structural evaluator. G5 must measure this blind spot with independently labeled counterexamples and actual runtime evidence. Passing this prototype cannot be called "AI now has judgment."

## Integration direction

G4 must insert the evaluator immediately before the existing handoff/terminal completion claim path, not invent a second dispatcher. Use exact P-number upstream resolution where authorized. On failed admission, produce a typed repair obligation for the current agent. Do not make a human manually shuttle the context. No contract, model vote, or successful lint result can grant mutation/deploy/merge permission.

Measure: unresolved decision burden per handoff, docs-as-software misclassification, false-admitted handoffs, safe work unnecessarily delegated, and operator corrections per sprint. Optimize for actual validated implementation outcomes rather than tokens consumed, prompt length or plans produced.

**Current proof ceiling:** public specification and deterministic validator code can be implemented remotely. A live local adapter, autonomous execution, user-visible outcome and model judgment quality remain unproven until separately observed.
