---
id: public-plan-coordination
version: 1.0.2
status: canonical
---

# Public Plan Coordination

## Trigger

Use this skill when a user or agent asks to create, update, resume, coordinate, factor, or hand off repository work that spans agents, branches, pull requests, waves, or sessions.

Deterministic triggers:

- `plan.coordination-request`
- a material change to dependencies, ownership, collision boundaries, proof gates, or next-agent handoff for a registered public plan
- a sprint pack that would otherwise exist only in chat

## Inputs

- current repository and Git evidence
- `plans/plan-registry.json`
- selected public plan
- branch, pull request, worktree, validator, artifact, and CI state
- owned and forbidden scope
- dependencies and safe parallel lanes
- proof target and proof ceiling

## Procedure

1. Read repository rules, codebase map, plan registry, selected plan, validators, open pull requests, and recent Git history.
2. Reconcile stale plan fields with current repository evidence. Mark uncertainty rather than guessing.
3. Keep the plan and pull request distinct:
   - the plan coordinates work and survives branch or PR replacement;
   - the branch and PR transport reviewed implementation changes.
4. Select one plan task whose dependencies are satisfied and whose file ownership does not collide with another active writer.
5. Update machine-readable task status, evidence, delivery references, handoff, and timestamps when coordination changes materially. Update the plan in the same branch or PR as the implementation when safe.
6. Keep product behavior in deterministic code, contracts, schemas, validators, and workflows. Do not hide product behavior in plan prose or prompts.
7. Validate the plan and the owned repository change.
8. Commit and push the plan update with the implementation when safe and authorized.
9. Report exact commit, PR, artifact, validation, proof level, proof ceiling, and next command.

## Outputs

- updated `plans/plan-registry.json` when registry membership changes
- one schema-valid public plan
- implementation artifacts owned by the selected task
- validation evidence
- commit and PR evidence
- bounded next-agent handoff

## Deterministic validation

Repository-relative validator: `scripts/Test-PublicPlanContracts.ps1`.

Run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-PublicPlanContracts.ps1
```

Then run the validators named by the selected plan and `git diff --check`.

## Forbidden scope

- storing secrets, credentials, customer data, private hostnames, or machine-local runtime evidence in public plans
- claiming task completion from acknowledgment, prose, process start, or exit code alone
- treating a plan as authorization to merge, deploy, mutate a target, authenticate, or perform destructive Git
- using a pull request description as the only coordination record
- putting application behavior exclusively in a plan or prompt
- overwriting another agent's plan task or uncommitted work without an ownership handoff

## Stop and escalate

Stop and preserve evidence when:

- the repository is dirty with unowned work;
- two writers claim the same file, schema, workflow, skill, capability, trigger, branch, or worktree;
- required plan dependencies are not proven;
- the selected plan is stale and current repository evidence cannot resolve it;
- the next action needs secrets, merge, deployment, live-target mutation, or destructive Git without explicit authority;
- validation contradicts the plan.
