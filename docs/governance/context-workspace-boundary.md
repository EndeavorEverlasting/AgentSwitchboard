# Context Workspace Boundary

Machine-readable authority: `.ai/harness/context-workspace-boundary.contract.json`.

## Why this contract exists

Agentic engineering can make implementation syntax cheap while making intent, architecture, conventions, evidence, and coordination comparatively more valuable. Some projects therefore benefit from separating a **context/intent workspace** from the **implementation repository**. The separation is useful only when it reduces noise without creating two competing sources of truth.

This contract owns only that cross-repository seam. Existing AgentSwitchboard owners remain authoritative for:

- repository-local knowledge reuse: `.ai/harness/harness-doctrine.policy.json#knowledgeReuse`;
- progressive disclosure and context loading: `tooling/harness/context/context.routes.json`;
- repository work-state semantics: `.ai/harness/repository-work-ledger.policy.json`.

Do not restate those contracts here or in a consumer repository.

## Authority model

A context authority may own durable intent such as epics, specifications, ADRs, conventions, coordination logs, and structured lessons. It does **not** prove that code exists, tests pass, runtime works, or deployment succeeded.

An implementation authority owns source, tests, build/deploy logic, runtime configuration, and implementation-derived state. It should reference rather than duplicate the canonical project intent, roadmap, or cross-project decision history when those live in a separate context workspace.

A single repository may hold both roles. If the roles are split, every consumer must declare the paired repositories and the concern-by-concern authority map.

## Derived state beats authored optimism

Context documents may describe intended status, but implementation-derived evidence is stronger for implementation claims. A specification marked `complete` cannot override an implementation repository showing missing work, failing tests, an absent artifact, or an unmerged change.

Cross-repository conflicts are not resolved by timestamp alone. Preserve both truths, identify the owning concern, and either apply an explicit precedence rule or mark the mapping stale/conflicted.

## Operator and agent projections

Human and agent views may differ in density without becoming separate authorities.

- **Operator mode** should summarize active epics/specs, current proof, blockers, and the next decision.
- **Agent mode** may expose machine-parseable IDs, dependencies, ownership, proof pointers, unresolved gaps, and routing metadata.

Both views must be derived from the same registered artifact graph. Do not maintain a human dashboard and a second agent index by hand when they encode the same state.

## Session-start hydration

A session-start hook may deterministically assemble a bounded context packet from registered artifacts. It should normally include only the current repository identity, active work unit, linked specification/decision context, applicable conventions, recent bounded evidence, and unresolved gaps.

The hook must not dump the whole repository, smuggle secrets into prompts, override governance, or treat a large context payload as inherently better. It composes with progressive disclosure: hydrate stable known state cheaply, then demand-load deeper evidence as the task requires it.

## Lessons and feedback memory

Structured lessons are useful when they prevent repeated failures, but they are evidence, not self-authorizing policy mutation. A lesson entry should carry provenance, scope, owner, and the failure or observation that justified it. Lessons may propose changes to skills, conventions, or validators; they do not silently rewrite those canonical owners.

## Portable versus source-specific ideas

The user-supplied 2026-08-25 breakdown attributed to Alex Lieberman, a 10X engineering director, and David Ondrej contains several patterns compatible with this contract: context repositories, written-first machine-readable blueprints, operator/agent projections, session-start hydration, SDLC linting, Git-versioned shared skills, and feedback memory. Those claims are treated as user-supplied source influence rather than independently verified fact.

The following source-specific details are **not** promoted into universal AgentSwitchboard law:

- the 10X business model, Bell Labs analogy, or consulting posture;
- specific `con-*.md` filenames;
- a particular `10x context` or `10x validate` CLI;
- Notion, Slack, Gmail, Linear, Reddit, Hacker News, X, or any specific content pipeline;
- named interview-panel personas or a fixed review-score threshold;
- the claim that context repositories should always be physically separate from code repositories.

Consumers may adopt equivalent local mechanisms after repository-local owner discovery. The portable rule is the authority boundary and projection/validation contract, not a copy of another team's tool names.

## Consumer adoption

A consumer adoption manifest must record:

- AgentSwitchboard donor repository and pinned donor commit;
- this contract path and version;
- context repository identity and implementation repository identity;
- authority map by concern;
- stable reference/mapping strategy;
- stale-reference behavior;
- consumer-local validator and tests;
- proof ceiling;
- explicitly rejected duplicated behavior.

A contribution manifest is an adoption proposal and compatibility record. It does not prove the consumer implementation or runtime.
