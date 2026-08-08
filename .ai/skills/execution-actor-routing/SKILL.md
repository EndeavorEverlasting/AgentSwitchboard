---
id: execution-actor-routing
status: canonical
owner: tooling/harness/operational/execution-actor-routing
---

# Execution Actor Routing

## Trigger

Use this skill before a repository mutation when the user or task contract names who must perform the action, including `ChatGPT`, `AgentSwitchboard`, or the `operator`.

Also use it when more than one actor can technically perform the same mutation and the identity of the actor changes what the result proves. The operational status reporter consumes the registered `routingNeedles` for explicit actor phrasing before broader environment routing.

## Inputs

- current task text;
- requested actor: `chatgpt`, `agentswitchboard`, `operator`, or `auto`;
- selected actor;
- selection source;
- task summary;
- exact operation;
- output root when continuity evidence must survive a shell or chat boundary.

## Procedure

1. Read the current user instruction literally for actor identity. Do not replace an explicit actor with `auto`.
2. Normalize only the four canonical actor values: `chatgpt`, `agentswitchboard`, `operator`, `auto`. Do not invent aliases.
3. Before mutation, run `Invoke-ExecutionActorRouting.py bind`.
4. Capture the emitted `BINDING_SHA256` and preserve it outside the mutable `execution-actor-binding.json` file, such as in the parent launcher receipt, task transcript, or operator handoff.
5. If the requested actor is explicit, require the selected actor to match exactly. A mismatch is a hard stop.
6. If the requested actor is `auto`, record why the selected actor is appropriate.
7. Perform the operation through the selected actor only.
   - `chatgpt`: the current ChatGPT/tooling surface performs the mutation directly.
   - `agentswitchboard`: launch or instruct the AgentSwitchboard-owned execution path and let that runtime perform the mutation.
   - `operator`: give the operator the exact executable action and do not perform the mutation on their behalf.
8. Capture actor-owned evidence from the operation.
9. Run `Invoke-ExecutionActorRouting.py verify` with `--expected-binding-sha256 <BINDING_SHA256>`, the actual actor, and the evidence reference. Verification validates the complete binding and fails if its digest changed.
10. Continue only when the receipt is `actor-verified` and its `bindingSha256` matches the preserved digest.
11. If the selected actor is unavailable, preserve the binding and report the blocker. Do not silently substitute another actor.

## Outputs

- `execution-actor-binding.json`;
- emitted `BINDING_SHA256`, which must be preserved independently until verification;
- `execution-actor-receipt.json` after execution;
- `execution-actor-operator-report.md`;
- the separate evidence produced by the actor that actually executed the operation.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionActorRoutingHarness.ps1
python tests/test_execution_actor_routing_harness.py
git diff --check
```

## Forbidden scope

- Do not edit `AGENTS.md` from this harness-only skill.
- Do not modify product launchers merely to encode actor preference.
- Do not treat direct GitHub connector evidence as AgentSwitchboard execution proof.
- Do not treat AgentSwitchboard evidence as direct ChatGPT execution proof.
- Do not execute an operator-owned mutation on the operator's behalf.
- Do not change an explicit actor because another path is faster, easier, already authenticated, or already open.
- Do not verify a mutable binding without the independently preserved `--expected-binding-sha256` from its bind step.
- Do not claim actor verification without an actual evidence reference.
- Do not install hooks implicitly.
- Do not use destructive Git.

## Stop and escalate

Stop the mutation when an explicit actor cannot perform the required operation, when the preserved binding digest no longer matches, when actual actor evidence contradicts the binding, when credentials or authority are missing, or when completing the operation would cross owned scope. Preserve the binding, digest, and available evidence and name the exact actor, blocker, dependency, and action required to continue.
