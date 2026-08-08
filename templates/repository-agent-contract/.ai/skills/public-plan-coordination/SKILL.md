---
id: public-plan-coordination
version: REPLACE_SKILL_VERSION
status: canonical
---

# Public Plan Coordination

## Trigger

Use for multi-agent, multi-session, multi-wave, cross-PR, sprint-map, launch-pack, material plan-state coordination, or a large ambiguous effort whose destination is known but whose executable route still contains unresolved decisions.

## Inputs

- repository and current Git evidence
- `plans/plan-registry.json`
- selected public plan
- owned and forbidden scope
- dependencies and collision boundaries
- expected artifacts, validators, and proof target
- when decision-frontier mode is used, the repository's pinned contribution/adoption manifest for that mode

## Procedure

1. Read repository rules, codebase map, plan registry, selected plan, open PRs, validators, and recent Git history.
2. Reconcile stale plan state with current repository evidence.
3. Classify the plan mode before editing. Ordinary plans omit `coordinationMode`; decision-frontier plans set `coordinationMode.kind` to `decision-frontier`.
4. Select one ready task whose dependencies are satisfied and whose owned files do not collide with another writer.
5. Keep the plan and pull request distinct: the plan coordinates; the branch and PR deliver and review tracked changes.
6. For decision-frontier mode, treat tasks as decision tickets rather than implementation slices, derive the frontier from task state instead of storing it twice, keep coarse unresolved fog in `coordinationMode.notYetSpecified`, keep destination-scope exclusions in `coordinationMode.outOfScope`, and keep `coordinationMode.executionAllowed` false until handoff to bounded execution.
7. Implement product behavior in deterministic code and contracts, not in plan prose.
8. Update task status, evidence, delivery references, proof, and handoff when coordination changes materially.
9. Validate, commit, push when authorized, and report exact evidence.

## Outputs

- one schema-valid updated public plan
- in decision-frontier mode, one non-duplicated destination/decision/fog/out-of-scope coordination surface
- implementation artifacts owned by the selected task when ordinary execution coordination is active
- validation, commit, PR, proof, and handoff evidence

## Deterministic validation

Run the repository's public-plan validator and every validator named by the selected plan, followed by `git diff --check`. If the repository adopts a decision-frontier contribution, run its dedicated consumer validator too.

## Forbidden scope

- secrets, credentials, customer data, private hostnames, local paths, provider state, or raw runtime evidence in public plans
- treating a plan as permission to authenticate, merge, deploy, mutate a target, or perform destructive Git
- using a PR description as the only coordination record
- hiding application behavior solely in plans or prompts
- overwriting another writer's active task or uncommitted work
- copying donor-specific tracker behavior or skill names into the consumer as a competing planning authority
- auto-advancing a pinned donor reference without a reviewed contribution refresh

## Stop and escalate

Stop for unowned dirty work, ownership collisions, stale unresolved dependencies, failed validation, forbidden data, a decision task that crosses into implementation without an execution owner, or actions requiring authority the plan does not grant.
