# Execution Actor Routing Harness

This harness prevents a specific class of false completion: the requested end state is achieved, but by the wrong actor.

## Why it exists

`ChatGPT`, `AgentSwitchboard`, and the human `operator` can sometimes reach the same Git or GitHub end state. They are not interchangeable evidence.

If the user says **"have AgentSwitchboard merge it"**, a direct ChatGPT/API merge is the wrong execution path even if the resulting commit is technically correct. Conversely, if the user asks ChatGPT to perform the work, forcing the operation through AgentSwitchboard adds the wrong dependency.

The actor therefore belongs in the task contract. `Get-OperationalHarnessStatus.py` consumes actor-specific `routingNeedles` from the workflow registry so explicit actor phrasing reaches this skill through the operational front door.

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

The command writes `execution-actor-binding.json`, prints `BINDING_SHA256=<sha256>`, and writes an English-language operator report under a temporary run directory.

**Preserve that printed digest outside the mutable binding file before execution.** A parent launcher receipt, task transcript, or handoff artifact is suitable. An explicit actor mismatch exits nonzero and is not executable work.

## Execute through the bound actor

Do not change the execution path after binding because another credential, API, terminal, or agent happens to be convenient.

The operation itself remains owned by its existing repository workflow. This harness does not grant merge, deployment, credential, provider, or live-target authority.

## Verify after mutation

```powershell
python tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py verify `
  --binding "<run-root>\execution-actor-binding.json" `
  --expected-binding-sha256 "<BINDING_SHA256 captured at bind>" `
  --actual-actor agentswitchboard `
  --evidence "<AgentSwitchboard-owned receipt, log, PR comment, or other concrete evidence>"
```

Verification validates the complete binding shape and actor relationship, recomputes its canonical SHA-256, compares it to the independently preserved digest, and only then evaluates actual actor identity. A changed binding fails closed without producing an `actor-verified` receipt.

## Failure modes

- **Explicit mismatch:** stop before mutation.
- **Binding digest mismatch:** stop verification and re-bind from the authoritative task; do not trust the changed local binding.
- **Selected actor unavailable:** preserve the binding and digest and report the dependency; do not silently substitute.
- **Evidence missing:** the operation may have happened, but actor identity is unproved.
- **Actual actor mismatch:** preserve the receipt as failure evidence and do not claim the requested actor performed the operation.

## Trust model

The pinned digest detects binding drift or replacement relative to the digest preserved outside the file. It is not a cryptographic signature and does not defend against a hostile process that can rewrite both the binding and every out-of-band copy of the digest. This harness intentionally does not introduce secrets or signing credentials.

## Operator report

`execution-actor-operator-report.md` states what routing is working, what is broken, what proof is missing, the next actionable step, the binding digest when available, and the proof ceiling.

## Validation

```powershell
python tests/test_execution_actor_routing_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionActorRoutingHarness.ps1
python tests/test_operational_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
git diff --check
```

## Proof ceiling

A green actor-routing harness proves deterministic actor selection, front-door routing, binding-digest continuity checks, and fail-closed mismatch behavior. It does not prove that AgentSwitchboard, ChatGPT, or the operator actually completed a particular repository mutation until that operation's actor-owned evidence is supplied, and it does not provide hostile-host tamper resistance.
