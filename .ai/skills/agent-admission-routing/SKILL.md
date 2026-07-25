---
id: agent-admission-routing
version: 1.0.0
status: experimental
---

# Agent Admission Routing

## Trigger

Select this skill before delegating implementation or validation when AgentSwitchboard can choose among agents, providers, or models and the requested work has a meaningful proof boundary. It is mandatory before assigning `repository-runtime` or `live-runtime` work to an agent whose current proof-discipline admission is unknown, stale, failed, or identity-mismatched.

Use this skill when:

- the operator asks AgentSwitchboard to choose or employ an implementation agent;
- a cheap/free/weaker model may be useful for bounded implementation but should not be trusted to certify runtime success;
- a requested lane crosses process, terminal, GUI, provider, workstation, game, or external-target boundaries;
- agent prose conflicts with deterministic evidence or converts a not-attempted operation into an environment blocker;
- routing must be based on demonstrated capability rather than agent brand.

## Inputs

- repository and branch or worktree;
- task ID, owned scope, forbidden scope, and validation order;
- requested proof level and requested execution lane;
- candidate agent identities as `agentId`, `provider`, `model`, and `endpointClass`;
- current capability/readiness evidence;
- current admission result for each exact identity when one exists;
- applicable runtime or end-to-end skill when the selected lane crosses runtime boundaries.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `CAPABILITIES.md`, `TRIGGERS.md`, and `tooling/agents/harness/admission/agent-admission.registry.json`.
2. Run task intake. Freeze the required proof before selecting an agent. Do not lower the acceptance boundary because a preferred or cheap agent cannot satisfy it.
3. Separate technical capability from admission. Command presence, adapter readiness, provider reachability, price, reputation, or a prior successful run does not grant runtime-proof eligibility.
4. For `static-build`, an unassessed candidate may be used only for bounded repository implementation and deterministic checks inside the declared scope. The harness or an independently authorized validator owns the success decision.
5. Before `repository-runtime` or `live-runtime`, require a fresh `runtime-proof-discipline/v1` admission result bound to the exact agent/provider/model/endpoint identity.
6. If admission is required and missing, run `agent-admission-evaluation`. The candidate classifies the synthetic cases; deterministic comparison decides whether it passed.
7. Run `agent-route-selection`. Select by eligible lane and current capability, not by brand. If live-runtime proof is required and no candidate is eligible, return `BLOCKED_NO_ELIGIBLE_AGENT` rather than silently assigning a weaker agent or substituting static proof.
8. Before delegation, record actual execution identity. Requested routing is not execution proof.
9. During runtime work, the deterministic owning harness reduces machine facts to proof state. The delegated model may report artifacts but may not self-promote `NOT_ATTEMPTED`, `ACK_ONLY`, `LAUNCHER_BLOCKED`, or `STALE_EVIDENCE` into success.
10. On admission, routing, or proof failure, use `agent-failure-handoff`. Preserve the strongest observed proof, exact blocker, artifact paths, and one actionable continuation step.

## Outputs

- `agent-admission-run-context.json`;
- `agent-admission-eval-result.json` when admission is required;
- `agent-route-decision.json`;
- `agent-execution-identity.json` before delegated execution;
- `agent-proof-ledger.json` when a runtime harness supplies machine facts;
- English operator report;
- `agent-admission-final-handoff.json` on blocked or terminal continuation.

All generated outputs are local-operational and untracked unless deliberately minimized and reviewed as a public fixture.

## Deterministic validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AgentAdmissionHarness.ps1
python tests/test_agent_admission_harness.py
```

For repository-wide regression after focused validation:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-HarnessDoctrineContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-RepositoryFamilyHarness.ps1
```

A passing contract proves only that admission, proof reduction, routing, artifact policy, and handoff rules are coherent. It does not prove an agent was invoked, a model answered, a provider was reachable, or a live application behaved correctly.

## Forbidden scope

- do not modify `AGENTS.md` or invent a competing governance principle;
- do not install, authenticate, or call an agent/provider merely to make the harness pass;
- do not treat a fixture as runtime evidence;
- do not infer live eligibility from command presence, provider reachability, model brand, price, or prior unrelated success;
- do not let the delegated model decide whether its own admission passed;
- do not silently lower required proof when no eligible live agent exists;
- do not persist credentials, raw private prompts, raw model transcripts, customer data, or private hostnames in tracked files;
- do not grant merge, deployment, target mutation, secret, or destructive-Git authority.

## Stop and escalate

Stop the delegated lane and preserve evidence when:

- the required proof or execution lane is ambiguous;
- exact execution identity cannot be recorded;
- the admission suite is missing, stale, identity-mismatched, or failed;
- live-runtime proof is required and no eligible agent exists;
- the deterministic harness reports `NOT_ATTEMPTED`, `LAUNCHER_BLOCKED`, `ACK_ONLY`, `STALE_EVIDENCE`, or another non-pass terminal state;
- an agent claims an environment blocker for an operation the evidence shows was never attempted;
- work would cross forbidden scope, collide with another writer, or require authority not granted by the task.
