---
id: public-plan-coordination
version: REPLACE_SKILL_VERSION
status: canonical
---

# Public Plan Coordination

## Trigger

Use for multi-agent, multi-session, multi-wave, cross-PR, sprint-map, launch-pack, or material plan-state coordination.

## Inputs

- repository and current Git evidence
- `plans/plan-registry.json`
- selected public plan
- owned and forbidden scope
- dependencies and collision boundaries
- expected artifacts, validators, and proof target

## Procedure

1. Read repository rules, codebase map, plan registry, selected plan, open PRs, validators, and recent Git history.
2. Reconcile stale plan state with current repository evidence.
3. Select one ready task whose dependencies are satisfied and whose owned files do not collide with another writer.
4. Keep the plan and pull request distinct: the plan coordinates; the branch and PR deliver and review tracked changes.
5. Implement product behavior in deterministic code and contracts, not in plan prose.
6. Update task status, evidence, delivery references, proof, and handoff when coordination changes materially.
7. Validate, commit, push when authorized, and report exact evidence.

## Outputs

- one schema-valid updated public plan
- implementation artifacts owned by the selected task
- validation, commit, PR, proof, and handoff evidence

## Deterministic validation

Run the repository's public-plan validator and every validator named by the selected plan, followed by `git diff --check`.

## Forbidden scope

- secrets, credentials, customer data, private hostnames, local paths, provider state, or raw runtime evidence in public plans
- treating a plan as permission to authenticate, merge, deploy, mutate a target, or perform destructive Git
- using a PR description as the only coordination record
- hiding application behavior solely in plans or prompts
- overwriting another writer's active task or uncommitted work

## Stop and escalate

Stop for unowned dirty work, ownership collisions, stale unresolved dependencies, failed validation, forbidden data, or actions requiring authority the plan does not grant.
