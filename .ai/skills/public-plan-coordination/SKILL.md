---
id: public-plan-coordination
version: 1.1.0
status: canonical
---

# Public Plan Coordination

## Trigger

Use this skill when a user or agent asks to create, update, resume, coordinate, factor, or hand off repository work that spans agents, branches, pull requests, waves, or sessions.

Also use decision-frontier mode when an effort is intentionally larger than one bounded agent session and the route to the destination is not yet clear enough to execute safely. In that mode the plan resolves decisions first; it does not pre-slice unknown work into implementation tasks.

Deterministic triggers:

- `plan.coordination-request`
- a material change to dependencies, ownership, collision boundaries, proof gates, or next-agent handoff for a registered public plan
- a sprint pack that would otherwise exist only in chat
- a large ambiguous effort whose destination is known but whose executable route still contains unresolved decisions or investigations

## Inputs

- current repository and Git evidence
- `plans/plan-registry.json`
- selected public plan
- branch, pull request, worktree, validator, artifact, and CI state
- owned and forbidden scope
- dependencies and safe parallel lanes
- proof target and proof ceiling
- for decision-frontier mode, `tooling/harness/operational/contributions/wayfinder-public-plan.contribution.json`

## Procedure

1. Read repository rules, codebase map, plan registry, selected plan, validators, open pull requests, and recent Git history.
2. Reconcile stale plan fields with current repository evidence. Mark uncertainty rather than guessing.
3. Classify the plan mode before editing:
   - ordinary execution coordination uses the existing public-plan fields and has no `coordinationMode` object;
   - decision-frontier coordination sets `coordinationMode.kind` to `decision-frontier` and follows the bounded rules below.
4. Keep the plan and pull request distinct:
   - the plan coordinates work and survives branch or PR replacement;
   - the branch and PR transport reviewed implementation changes.
5. Select one plan task whose dependencies are satisfied and whose file ownership does not collide with another active writer.
6. Update machine-readable task status, evidence, delivery references, handoff, and timestamps when coordination changes materially. Update the plan in the same branch or PR as the implementation when safe.
7. Keep product behavior in deterministic code, contracts, schemas, validators, and workflows. Do not hide product behavior in plan prose or prompts.
8. Validate the plan and the owned repository change.
9. Commit and push the plan update with the implementation when safe and authorized.
10. Report exact commit, PR, artifact, validation, proof level, proof ceiling, and next command.

## Decision-frontier mode

Decision-frontier mode adapts a small set of planning principles from the pinned external contribution manifest without making that donor repository an AgentSwitchboard runtime dependency or creating a second planning authority.

- **Destination first.** `coordinationMode.destination` states the decision/specification boundary this plan is finding a route toward. The destination is narrower than the repository mission and determines what is merely not-yet-specified versus genuinely out of scope.
- **Decision tasks, not build slices.** While `coordinationMode.kind` is `decision-frontier`, `tasks[]` represent questions, investigations, prototypes, or prerequisites needed to make a decision. They are not pre-allocated implementation slices. `coordinationMode.executionAllowed` is fixed to `false`; execution moves to an ordinary bounded sprint or ordinary execution plan after the route is clear.
- **Single decision owner.** The task is the canonical owner of its decision. Put the question in the task title/acceptance criteria and exact result pointers in `outputs`/`evidence`. Summaries may gist the result but must not become a competing authoritative copy.
- **Frontier is derived, not stored twice.** A frontier task has `status: ready`, all named dependencies completed, and `owner: unassigned`. Claim it before work by changing `owner` to the active writer and `status` to `in-progress` in the owned plan branch. Never add a second `frontier` list that can drift from task state.
- **Fog remains coarse.** `coordinationMode.notYetSpecified` records in-scope questions that cannot yet be stated precisely. When a question becomes precise, remove that fog entry and create a task. Do not pre-slice fog into speculative tasks.
- **Destination scope is not safety scope.** `coordinationMode.outOfScope` records work beyond the destination. `forbiddenScope` remains the stronger repository/safety/authority boundary and must not be repurposed as planning fog.
- **One decision per writer/session.** A writer normally resolves one decision task per session. Independent research tasks may proceed in parallel only through separately owned branches/worktrees and must preserve their evidence independently.
- **Handoff at the execution edge.** When no unresolved decision task or fog remains and the destination is sufficiently specified, update the plan handoff with the exact executable next owner/command. Do not turn the final planning session into unbounded implementation.

The contribution manifest is adoption metadata and provenance only. It is not runtime proof, it does not import the donor's issue-tracker behavior, and it does not grant authority.

## Outputs

- updated `plans/plan-registry.json` when registry membership changes
- one schema-valid public plan
- for decision-frontier mode, one plan whose destination, decision tasks, fog, and destination out-of-scope boundary are represented without duplicate state
- implementation artifacts owned by the selected task when ordinary execution coordination is active
- validation evidence
- commit and PR evidence
- bounded next-agent handoff

## Deterministic validation

Repository-relative validator: `scripts/Test-PublicPlanContracts.ps1`.

Run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-PublicPlanContracts.ps1
```

For the decision-frontier extension also run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-WayfinderPublicPlanContribution.ps1
python .\tests\test_wayfinder_public_plan_contribution.py
```

Then run the validators named by the selected plan and `git diff --check`.

## Forbidden scope

- storing secrets, credentials, customer data, private hostnames, or machine-local runtime evidence in public plans
- claiming task completion from acknowledgment, prose, process start, or exit code alone
- treating a plan as authorization to merge, deploy, mutate a target, authenticate, or perform destructive Git
- using a pull request description as the only coordination record
- putting application behavior exclusively in a plan or prompt
- overwriting another agent's plan task or uncommitted work without an ownership handoff
- copying donor-specific tracker labels, child-issue APIs, local tracker conventions, or donor skill names into AgentSwitchboard as a second authority
- auto-advancing the pinned donor commit because upstream `main` moved; refresh requires a reviewed contribution update

## Stop and escalate

Stop and preserve evidence when:

- the repository is dirty with unowned work;
- two writers claim the same file, schema, workflow, skill, capability, trigger, branch, worktree, or decision task;
- required plan dependencies are not proven;
- the selected plan is stale and current repository evidence cannot resolve it;
- a decision-frontier task has become executable implementation but no bounded execution owner has been established;
- the next action needs secrets, merge, deployment, live-target mutation, or destructive Git without explicit authority;
- validation contradicts the plan;
- donor refresh would change adopted semantics without a new pinned contribution review.
