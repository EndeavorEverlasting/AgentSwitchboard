---
id: wayfinder
version: 1.1.0
status: experimental
---

# Wayfinder

## Source lineage

Salvaged from closed-unmerged PR #94 and adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`. The immutable donor snapshot lives under `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/`. AgentSwitchboard owns the adapted procedure; donor material is provenance, not runtime authority.

## Trigger

Use when a requested destination is too large or ambiguous for one bounded sprint because unresolved decisions or investigations prevent safe execution. If the route is already clear, use `bounded-sprint` instead.

## Inputs

- current repository rules and evidence;
- destination or existing decision-map identity;
- `tooling/harness/wayfinder/wayfinder_contract.py`, `github_tracker.py`, schemas, and fixtures;
- pinned donor snapshot;
- human decision-maker availability for HITL tickets;
- public-plan pointer when coordination must survive sessions.

## Ticket gates

| Type | Interaction | Required skill | Resolution floor |
| --- | --- | --- | --- |
| research | AFK | `research` | primary-source findings artifact + tracker resolution pointer |
| prototype | HITL | `prototype` | runnable throwaway + observed human verdict |
| grilling | HITL | `grilling` + `domain-modeling` | actual human answer + durable context where needed |
| task | AFK/HITL | Wayfinder task gate | prerequisite actually completed |

The human speaks for themselves. An agent must not manufacture a HITL answer, infer approval from silence, or treat a label/body disagreement as permission to continue.

## Procedure

### Chart mode

1. Read current repository authority and the Wayfinder core.
2. Settle the destination with human-owned choices and grounded facts.
3. Create only decision tickets whose questions are precise now.
4. Create ticket identities before wiring blockers.
5. Dispatch independent research only through an actually available authorized runtime.
6. Mirror coordination in the public plan when needed without duplicating full decision answers.
7. Stop before resolving prototype, grilling, or task tickets.

### Work mode

1. Query the frontier: open, unassigned tickets with all blockers resolved.
2. Claim before work.
3. Execute exactly the ticket-type gate.
4. Resolve at most one non-research ticket per session.
5. Put the detailed answer on the tracker and only a linked one-line gist on the map.
6. Recompute fog, blockers, and out-of-scope state.

### Specification edge

A map is clear only when required decision tickets are resolved and `Not yet specified` is empty. Use `to-spec` or `to-tickets` only after that gate. Temporary specifications do not replace decision history.

## Outputs

- decision map and typed child tickets;
- blocker/frontier state;
- linked evidence and decision pointers;
- optional public-plan mirror;
- exact post-Wayfinder execution handoff.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Proof ceiling

Static/synthetic validation proves ticket/HITL gates, frontier/spec algorithms, tracker command construction, fixture shape, and pinned lineage. It does not prove GitHub issue permissions, live tracker mutation, human participation, research correctness, prototype usefulness, destination implementation, deployment, or operator acceptance.

## Forbidden scope

- agent-authored substitute for HITL decisions;
- implementation disguised as decision work;
- work on an unclaimed ticket;
- non-research resolution during chart mode;
- duplicate full answers across tracker/map/plan/spec;
- automatic donor refresh;
- secrets or private runtime evidence in public artifacts.

## Stop and escalate

Stop on ambiguous map identity, conflicting labels/blockers/claims, unavailable HITL owner, unavailable authoritative evidence, unsafe live mutation, concurrent ownership collision, failed validation, or once the route is clear enough for bounded execution.
