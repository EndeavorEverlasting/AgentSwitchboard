# Execution Actor Routing Harness

This harness prevents a specific class of false completion: the requested end state is achieved, but by the wrong actor.

## Why it exists

`ChatGPT`, `AgentSwitchboard`, and the human `operator` can sometimes reach the same Git or GitHub end state. They are not interchangeable evidence.

If the user says **"have AgentSwitchboard merge it"**, a direct ChatGPT/API merge is the wrong execution path even if the resulting commit is technically correct. Conversely, if the user says **"merge it"** and wants ChatGPT to perform the work, forcing the operation through AgentSwitchboard would add an unnecessary dependency.

The actor therefore belongs in the task contract.

## Canonical actors

| Value | Meaning |
| --- | --- |
| `chatgpt` | The current ChatGPT session and its connected tooling perform the operation. |
| `agentswitchboard` | The AgentSwitchboard runtime performs the operation and produces its own evidence. |
| `operator` | The human operator performs the operation from an exact command or UI action. |
| `auto` | No actor was explicitly requested; the current agent must select one and record the reason. |

## Bind before mutation

```powershell
python tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py bind `
  --requested-actor agentswitchboard `
  --selected-actor agentswitchboard `
  --selection-source user-explicit `
  --task "Complete validated PR integration" `
  --operation "Merge PR #123 at exact head <sha>"
```

The command writes `execution-actor-binding.json` and an English-language operator report under a temporary run directory.

An explicit actor mismatch exits nonzero and is not executable work.

## Execute through the bound actor

Do not change the execution path after binding because another credential, API, terminal, or agent happens to be convenient.

The operation itself remains owned by its existing repository workflow. This harness does not grant merge, deployment, credential, provider, or live-target authority.

## Verify after mutation

```powershell
python tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py verify `
  --binding "<run-root>\execution-actor-binding.json" `
  --actual-actor agentswitchboard `
  --evidence "<AgentSwitchboard-owned receipt, log, PR comment, or other concrete evidence>"
```

Verification fails when `actual-actor` differs from the bound selected actor.

## Failure modes

- **Explicit mismatch:** stop before mutation.
- **Selected actor unavailable:** preserve the binding and report the dependency; do not silently substitute.
- **Evidence missing:** the operation may have happened, but actor identity is unproved.
- **Actual actor mismatch:** preserve the receipt as failure evidence and do not claim the requested actor performed the operation.

## Operator report

`execution-actor-operator-report.md` always states:

- what routing is working;
- what is broken;
- what proof is missing;
- the next actionable step;
- the proof ceiling.

## Validation

```powershell
python tests/test_execution_actor_routing_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionActorRoutingHarness.ps1
python tests/test_operational_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
git diff --check
```

## Proof ceiling

A green actor-routing harness proves that the tracked repository has a deterministic actor-selection contract and that its binding/verification tool fails closed on mismatches. It does not prove that AgentSwitchboard, ChatGPT, or the operator actually completed a particular repository mutation until that operation's actor-owned evidence is supplied.
