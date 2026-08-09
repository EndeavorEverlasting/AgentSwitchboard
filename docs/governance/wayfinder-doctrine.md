# Wayfinder Doctrine

Wayfinder is AgentSwitchboard's governed ambiguity-resolution procedure for work whose **destination is meaningful, but whose safe route cannot yet be stated within one bounded session**.

This doctrine exists to reduce reliance on transient model context and discretionary AI reconstruction. It moves unresolved decisions into typed, tracker-backed artifacts and makes the transition from uncertainty to execution explicit.

## Canonical ownership

AgentSwitchboard owns its adapted Wayfinder behavior through:

- `.ai/skills/wayfinder/SKILL.md` — procedure;
- `.ai/harness/wayfinder-doctrine.policy.json` — machine-readable invariants;
- `tooling/harness/wayfinder/manifest.json` — harness registration;
- `tooling/harness/wayfinder/wayfinder_contract.py` — deterministic ticket/frontier/spec state transitions;
- `tooling/harness/wayfinder/github_tracker.py` — GitHub tracker adapter;
- `tooling/harness/wayfinder/schemas/` — closed evidence contracts;
- `scripts/Test-WayfinderHarness.ps1` and `tests/test_wayfinder_harness.py` — owning validators.

The imported source snapshots under `third_party/mattpocock-skills/<pinned-commit>/` are immutable provenance evidence, not executable ASB authority. The donor repository remains authoritative for the original skills.

## Selection doctrine

Select Wayfinder only when **both** are true:

1. reaching the destination spans more than one bounded agent session or context window; and
2. unresolved decisions, investigations, prototypes, or prerequisites prevent the safe route from being specified now.

A large implementation with a clear route is not Wayfinder work. Route it to public-plan coordination and bounded execution instead.

If a breadth-first Wayfinder charting pass reveals no meaningful fog and the route fits one bounded session, exit Wayfinder rather than manufacturing a map.

## Map and decision authority

A Wayfinder map is a **low-resolution index**, not a detailed store.

The map owns:

- destination;
- standing notes;
- one-line linked gists of resolved decisions;
- coarse `Not yet specified` fog;
- destination-level `Out of scope`.

Each child **decision ticket** owns exactly one precise question and its detailed resolution. The ticket also owns its tracker identity, type, blockers, claim, resolution comment, and asset pointers.

A detailed decision must not be copied into the map, public plan, and specification as competing authorities. Those surfaces may summarize and link the ticket.

## Decision tickets are not implementation tickets

Wayfinder tickets resolve uncertainty. They are not preallocated build slices.

Implementation tickets are produced only after the required decision route is clear, normally through `to-spec` followed by `to-tickets` or through a bounded sprint when no specification artifact is needed.

The four Wayfinder decision-ticket types are mandatory workflow gates:

| Type | Interaction | Required procedure | Required completion evidence |
|---|---|---|---|
| `research` | AFK | `research` | primary-source findings artifact and tracker resolution |
| `prototype` | HITL | `prototype` | runnable throwaway artifact and observed human verdict |
| `grilling` | HITL | `grilling` + `domain-modeling` | actual human answers and any required domain-context updates |
| `task` | AFK or HITL | prerequisite action | proof the prerequisite action actually completed |

Ticket type cannot be treated as decorative metadata. Label/type mismatch fails closed until a human explicitly corrects the tracker state.

## Human-in-the-loop doctrine

For HITL work, **the human speaks for themselves**.

The agent may:

- research facts;
- surface contradictions;
- recommend answers;
- construct prototypes;
- explain trade-offs;
- summarize the human's recorded answer.

The agent must not:

- answer its own grilling questions;
- infer a prototype verdict from silence;
- convert a recommendation into approval;
- manufacture human-response evidence;
- close a HITL ticket without observed human participation.

If the required human is unavailable, the ticket remains open or blocked.

## Frontier and concurrency doctrine

The live frontier is **derived from tracker state**, not stored as a second list.

An eligible frontier ticket is:

- a child of the map;
- open;
- unclaimed/unassigned;
- free of open blockers.

Claiming is the first write of a decision-working session. A session must not begin research, questioning, prototyping, or prerequisite mutation on an unclaimed non-research ticket.

Normally one session resolves at most one non-research decision ticket. Independent research tickets may run in parallel when their evidence surfaces and branches/worktrees do not collide.

A blocker is cleared only by a valid resolution or an explicit re-scope/rewire of dependent tickets. Ruling a blocker out of scope does not silently make its dependents eligible.

## Fog doctrine

`Not yet specified` is in-scope fog whose **question cannot yet be stated precisely**.

A question becomes a ticket as soon as it can be stated precisely, even if it is blocked and cannot yet be answered.

Do not pre-slice vague fog into speculative tickets. One fog patch may later become several tickets or none.

`Out of scope` is different: it lies beyond the destination and never graduates unless the destination is explicitly redrawn.

## Chart-mode stop doctrine

Charting performs:

1. destination definition through grilling/domain modeling;
2. breadth-first ambiguity discovery;
3. map creation;
4. creation of currently precise tickets;
5. a second pass to wire parent/blocking relationships;
6. dispatch of independently safe research work;
7. repository coordination mirror update.

Then charting **stops**.

Chart mode does not hand-resolve prototype, grilling, or task tickets and does not begin destination implementation.

## Specification lifecycle doctrine

A Wayfinder specification is a **temporary synthesis artifact**.

It can be created only when:

- all decision tickets required by the destination are resolved or explicitly removed from the route;
- `Not yet specified` is empty;
- required HITL verdicts have real human evidence;
- the decision-ticket links needed to explain the route are preserved.

The specification links the map and decision sources. It does not replace them as the durable rationale.

After implementation is accepted, the temporary specification is retired, archived, or removed according to tracker/repository policy. Closed decision tickets remain durable history.

## Public-plan boundary

`plans/` owns repository coordination: branch/PR delivery, writers, collision boundaries, proof, artifacts, and handoff.

A public plan may mirror a Wayfinder map's tracker identity, destination, fog, out-of-scope boundary, and temporary-spec state. It must not use `tasks[]` as a second copy of Wayfinder decision tickets.

## Donor refresh doctrine

The adopted donor sources are pinned by commit and Git blob identity.

The stale-reference policy is `pin-until-reviewed`:

- upstream movement is a signal to review, not an instruction to update;
- imported snapshots are never edited in place;
- a refresh creates a new pinned source snapshot and explicit semantic comparison;
- consumer behavior changes only through a reviewed ASB contribution and passing consumer validators.

## Proof ceiling

Static and hosted validation may prove source identity, schemas, routing, state-transition invariants, fixtures, tracker command construction, and compatibility with ASB contracts.

They cannot prove a live GitHub repository supports/permits the requested tracker operations, that a human supplied a valid decision, that research is substantively correct beyond its cited evidence, that a prototype is useful, or that the destination implementation works. Those require their owning live/runtime artifacts.
