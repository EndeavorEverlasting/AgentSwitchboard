---
id: wayfinder
version: 1.0.0
status: experimental
---

# Wayfinder

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, source `skills/engineering/wayfinder/SKILL.md`, blob `e4984ed327e12ba65303f4b5de2eb75c01e99c16`. Exact non-executable snapshot: `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/wayfinder/SKILL.md`.

The donor remains authoritative for the original skill. This file is the ASB authority for the adapted procedure and binds it to ASB's public-plan, evidence, actor, and proof contracts.

## Trigger

Use when the requested destination is too large or ambiguous for one bounded session **and unresolved decisions/investigations prevent a safe executable route**. Use `bounded-sprint` when the route is already clear.

Wayfinder is planning/decision work by default. Its job is to clear fog until the destination can be handed to bounded execution.

## Inputs

- repository rules, Git state, domain context/ADRs, and relevant current code evidence;
- loose destination or existing Wayfinder map reference;
- configured tracker (`github` preferred in ASB; local-Markdown fallback when explicitly selected/unavailable);
- `tooling/harness/wayfinder/manifest.json` and contribution manifest;
- public-plan mirror when cross-session repository coordination already exists;
- human decision-maker availability for HITL tickets;
- owned/forbidden scope and any explicit execution override in map Notes.

## Authority model

- Tracker **map** owns the low-resolution destination/notes/decision-pointer/fog/scope index.
- Tracker child **decision ticket** owns its exact question, blockers, claim, resolution, and asset pointers.
- `plans/` is a repository coordination mirror, not a shadow decision tracker.
- A spec is temporary synthesis after clarity, not primary decision rationale.
- Implementation tickets/bounded sprints are execution work after clarity, not Wayfinder decision tickets.

A decision lives in exactly one primary place. Maps/plans may gist and link it; they must not duplicate the full answer.

## Ticket gates

Ticket type is a fail-closed workflow gate:

| Type | Interaction | Required ASB skill path | Resolution floor |
|---|---|---|---|
| `research` | AFK | `research` | primary-source findings artifact + tracker resolution/context pointer |
| `prototype` | HITL | `prototype` | runnable throwaway artifact + observed human reaction/verdict |
| `grilling` | HITL | `grilling` **and** `domain-modeling` | actual human answers + durable domain updates where needed |
| `task` | AFK or HITL | Wayfinder task gate | prerequisite action actually completed |

For HITL work, **the human speaks for themselves**. Label/body disagreement fails closed in favor of the ticket type label until a human explicitly relabels/overrides it. An agent may not answer the human side of a HITL ticket or infer approval from silence.

## Procedure

### Chart mode

1. Read repository rules, tracker adapter, public-plan rules, domain context/ADRs, and pinned source contribution.
2. Run `grilling` + `domain-modeling` to settle the **destination**. The agent researches facts; the human owns choices.
3. Grill breadth-first to expose the decision tree/frontier. If no meaningful fog exists and the full route fits one bounded session, stop Wayfinder and route to `bounded-sprint` instead.
4. Create the tracker map with Destination, Notes, empty Decisions-so-far, coarse Not-yet-specified fog, and Out-of-scope boundary.
5. Create only tickets whose **question can be stated precisely now**. Create ticket identities first, then wire parent/blocking relationships in a second pass.
6. Verify every ticket label maps to its exact gate.
7. Dispatch independent research tickets in parallel only when an actual authorized subagent/runtime exists; use isolated evidence/throwaway branches and link results back to tickets.
8. Create/update the public-plan coordination mirror without copying ticket questions/answers.
9. **Stop.** Chart mode does not resolve prototype, grilling, or task tickets and does not implement the destination.

### Work mode

1. Load the map only, then query the live frontier: open child decision tickets with no open blockers and no assignee.
2. Use an explicitly named eligible ticket or the first frontier ticket in map order.
3. **Claim before any work.** The tracker assignee/status is the claim.
4. Fetch the claimed ticket body, type label, blockers, needed closed decisions, and map Notes.
5. Execute the exact ticket gate.
6. Resolve at most one non-research ticket per session. Research is the only normal parallel-resolution exception.
7. Post the answer as the tracker resolution comment, close the ticket, and append only a linked one-line gist to map Decisions-so-far.
8. Recompute the map: create newly precise tickets then wire blockers; graduate cleared fog; explicitly re-scope/close/rewire invalidated dependents; move work beyond the destination to Out of scope.
9. Update the public-plan mirror and exact handoff, then stop.

### Specification and implementation edge

The map is clear only when no required decision ticket remains open, `Not yet specified` is empty, every required decision has durable tracker resolution, and no HITL verdict was inferred by the agent.

If the destination is a specification, invoke `to-spec`. If implementation tickets are desired, invoke `to-tickets` **after** clarity. Once implementation is accepted, retire/archive/remove the temporary spec according to tracker policy while retaining the closed decision-ticket history.

## Outputs

- tracker map;
- typed child decision tickets and blocker graph;
- context pointers/assets produced by research/prototype/domain work;
- linked map gists for resolved decisions;
- updated coarse fog/out-of-scope boundary;
- public-plan coordination mirror when needed;
- temporary spec only after readiness;
- exact handoff to the next Wayfinder ticket or post-Wayfinder execution owner.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderHarness.ps1
python tests/test_wayfinder_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-WayfinderPublicPlanContribution.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

Live tracker completion additionally requires readback of labels, parent relationship, blockers, assignee claim, resolution comment, closed state, and map context pointer.

## Proof ceiling

Static/hosted validation proves imported-source identity, ASB workflow mapping, schemas, ticket gates, frontier/spec algorithms, tracker command construction, registration, and fixture behavior. It does not prove live tracker permissions/features, good agent judgment, actual human HITL answers/verdicts, research correctness beyond evidence, prototype usefulness, or destination implementation.

## Forbidden scope

- agent-authored substitute for a human HITL decision;
- implementation slices disguised as decision tickets;
- non-research ticket resolution during chart mode;
- work on an unclaimed ticket;
- full decision answer copied into map/public plan/spec as competing authority;
- prototype promoted to production merely because it ran;
- temporary spec promoted to permanent decision authority;
- destination implementation without a clear route and independent execution authority;
- secrets/private customer data/unsafe live-target evidence in public tracker artifacts;
- automatic donor refresh.

## Stop and escalate

Stop when the tracker/map identity is ambiguous, a ticket label conflicts with the requested workflow, a HITL human is unavailable, a blocker or claim contradicts the frontier, a required fact cannot be grounded, concurrent writers collide, a task requires unauthorized live mutation/credentials, validation fails, or the route becomes clear enough that Wayfinder is no longer the correct owner.
