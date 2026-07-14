# Trigger and Routing Contract

Triggers convert repository evidence or explicit requests into a reviewed skill or AI Developer Workflow. A trigger selects procedure; it does not grant authority.

## Trigger precedence

1. explicit owner instruction;
2. repository safety state;
3. active PR/review and failing validation;
4. repository-local routing rules;
5. canonical fallback mapping below.

Safety triggers may narrow or stop work even when a feature trigger is present.

## Canonical trigger map

| Trigger | Evidence | Route |
|---|---|---|
| `repo.new-or-unknown` | unfamiliar repo, placeholder path, stale handoff, uncertain branch | `repo-intake` |
| `repo.dirty-or-conflicted` | unowned changes, conflict markers, detached or unsafe state | preserve/isolate; then `repo-intake` |
| `sprint.execute` | scoped request with safe owned files | `bounded-sprint` |
| `review.findings` | unresolved PR comments or deterministic failures | `evidence-validation` |
| `validation.requested` | proof gap, skipped checks, contract drift | `evidence-validation` |
| `integration.requested` | stacked PRs, consumed commits, branch convergence | `pr-integration` |
| `runtime.requested` | launcher, installer, behavior, harness, or environment proof | `runtime-proof` |
| `docs.contract-change` | AGENTS, skills, capabilities, triggers, schemas | `bounded-sprint` plus documentation-contract validator |
| `tool.missing-or-unhealthy` | command absent or bounded probe fails | reuse, repair, install, skip, or block according to scope |
| `scope.collision` | two writers own overlapping paths | stop one lane or create a new isolation boundary |
| `secret-or-personal-data` | credentials, tokens, customer data, private evidence | stop, sanitize, and escalate |
| `live-target-mutation` | external machine, service, deployment, save, or customer target | require explicit authority and runtime-proof boundary |
| `repeated-repair-failure` | bounded retries exhausted | checkpoint and escalate |

## Trigger payload

A routed workflow should receive:

- repository and branch;
- trigger ID and evidence;
- owned and forbidden scope;
- acceptance criteria;
- available capabilities and blockers;
- selected skill or ADW;
- iteration, token, time, and mutation limits;
- required evidence and completion gate.

## Automatic stop triggers

Stop or escalate when:

- the task would overwrite unowned dirty work;
- a required capability is unknown or blocked;
- a path crosses forbidden scope;
- a deterministic gate exposes a security or data-loss risk;
- the next step requires merge, deployment, secrets, destructive Git, or live mutation without explicit authority;
- repeated repair attempts exceed the workflow limit;
- evidence contradicts the plan.

## No implicit authority

The presence of a trigger never authorizes installation, push, merge, release, deployment, target mutation, secret access, or destructive cleanup unless the task and repository contract explicitly allow it.
