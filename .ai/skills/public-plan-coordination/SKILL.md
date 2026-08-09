---
id: public-plan-coordination
version: 1.2.0
status: canonical
---

# Public Plan Coordination

## Trigger

Use when repository work must stay coordinated across agents, branches, pull requests, waves, worktrees, or sessions. This skill owns the **repository coordination mirror**: delivery state, ownership, collision boundaries, proof, and handoff.

When the destination itself is wrapped in unresolved multi-session ambiguity, route ambiguity resolution through `wayfinder`. Public-plan coordination may mirror that map for repository coordination, but it does not replace the tracker map or its decision tickets.

Deterministic triggers:

- `plan.coordination-request`
- a material change to dependencies, ownership, collision boundaries, proof gates, delivery references, or next-agent handoff for a registered public plan
- a sprint map/launch pack that would otherwise exist only in chat
- a Wayfinder map whose tracker state must be mirrored into repository coordination without duplicating ticket decisions

## Inputs

- current repository and Git evidence
- `plans/plan-registry.json`
- selected public plan
- branch, PR, worktree, validator, artifact, and CI state
- owned and forbidden scope
- dependencies and safe parallel lanes
- proof target and proof ceiling
- when `coordinationMode.kind` is `decision-frontier`: the tracker map reference and `tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json`

## Procedure

1. Read repository rules, codebase map, plan registry, selected plan, validators, open pull requests, and recent Git history.
2. Reconcile stale coordination fields with current repository evidence. Mark uncertainty instead of guessing.
3. **Keep the plan and pull request distinct**:
   - the public plan coordinates repository work;
   - the branch/PR transports and reviews tracked changes;
   - a Wayfinder tracker map indexes ambiguity-resolution decisions;
   - Wayfinder child tickets own their exact questions and resolutions;
   - bounded-sprint / implementation tickets own execution after the route is clear.
4. For ordinary plans, select one ready coordination task whose dependencies are satisfied and whose file ownership does not collide with another writer.
5. For a Wayfinder mirror, do **not** copy decision-ticket questions, answers, transcripts, prototype bodies, or research findings into `tasks[]`. Mirror only tracker identity, destination, fog, out-of-scope boundary, temporary-spec lifecycle, proof, delivery/collision state, and exact handoff.
6. Update machine-readable plan state in the **same branch or PR** as the owned implementation/coordination change when safe. Tracker state remains primary for Wayfinder ticket claim/block/resolution facts.
7. Keep **product behavior in deterministic code** and contracts, schemas, validators, and workflows; do not hide it in plan prose or prompts.
8. Validate the plan and owned repository change.
9. Commit/push the plan update with the implementation when safe and authorized.
10. Report exact commit, PR, artifact, validation, proof level, proof ceiling, and next command.

## Wayfinder mirror mode

`coordinationMode.kind: decision-frontier` is an **adapter surface**, not the Wayfinder engine.

- `destination` mirrors the tracker map destination.
- `tracker` points to the canonical map and declares `decisionAuthority: tracker-child-tickets`.
- `notYetSpecified` mirrors coarse in-scope fog only.
- `outOfScope` mirrors the destination boundary only.
- `spec` records temporary specification state/reference; it is never the decision authority.
- `executionAllowed` remains `false` while the plan represents ambiguity resolution.
- `tasks[]` remain repository coordination tasks. They are not a shadow issue tracker.

The live frontier is derived from the tracker: open child decision tickets with no open blockers and no assignee. Do not create a second frontier list in the public plan.

The stale-source policy is `pin-until-reviewed`: donor movement is an update signal, not permission to reinterpret or auto-update ASB behavior.

## Outputs

- updated `plans/plan-registry.json` when registry membership changes
- one schema-valid public coordination plan
- for Wayfinder: a low-resolution tracker mirror with no duplicated decision body
- implementation/coordination artifacts owned by the selected task where applicable
- validation evidence
- commit/PR evidence
- bounded next-agent handoff

## Deterministic validation

Repository-relative validator: `scripts/Test-PublicPlanContracts.ps1`.

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-PublicPlanContracts.ps1
```

For Wayfinder-backed mirrors also run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-WayfinderHarness.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-WayfinderPublicPlanContribution.ps1
python .\tests\test_wayfinder_harness.py
python .\tests\test_wayfinder_public_plan_contribution.py
```

Then run the selected plan's owning validators and `git diff --check`.

## Proof ceiling

A valid public-plan mirror proves coordination shape and referenced state only. It does not prove the tracker operation occurred, the human made a HITL decision, a prototype was accepted, research is correct, or destination implementation succeeded.

## Forbidden scope

- storing secrets, credentials, customer data, private hostnames, or raw machine/runtime evidence in public plans
- treating a plan as authorization to merge, deploy, authenticate, mutate a target, or perform destructive Git
- **using a pull request description as the only coordination record**
- application behavior hidden solely in plan prose/prompts
- overwriting another writer's active coordination state without handoff
- copying a Wayfinder ticket's detailed answer into the plan
- using `tasks[]` as a parallel Wayfinder issue tracker
- auto-advancing the donor pin

## Stop and escalate

Stop for unowned dirty work, writer/path collisions, stale unresolved dependencies, a missing/unreadable tracker map, contradictory tracker-vs-plan state, failed validation, forbidden data, or actions requiring authority the plan does not grant.
