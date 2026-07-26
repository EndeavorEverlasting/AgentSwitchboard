---
id: typed-cascade-validation
version: 1.0.0
status: experimental
---

# Typed Cascade Validation

## Trigger

Select this skill when an operation, tool call, event handler, agent action, or workflow result must pass a strict input contract before execution and a semantic/domain contract before its result may propagate to the next event.

Typical signals include: cascading events, pre-tool validation, post-tool validation, Pydantic-style input gates, ontology/OWL/SHACL-style result rules, typed event envelopes, semantic result validation, or a request to prevent agent prose from overriding machine-enforced constraints.

## Inputs

- repository and exact branch/worktree;
- requested operation and proof level;
- declared input contract/schema;
- declared ontology/domain profile;
- runId, actionId, and correlationId;
- explicit action authority and forbidden scope;
- deterministic action-result observation when the pre-gate passes;
- artifact root outside the repository.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, the runtime event contract, and `tooling/cascade/harness/typed-gates/codebase-map.json`.
2. Freeze the run/action/correlation identity and select the input contract plus ontology profile before execution.
3. Run the pre-action gate. Validate required fields, types, ranges, enums, closed fields where declared, and authority prerequisites.
4. If the pre-gate rejects, stop. Emit/record the typed rejection and do not invoke the action boundary.
5. If the pre-gate passes, invoke only the repository-owned deterministic action boundary authorized by the owning workflow. The agent remains proposal/selection logic; it does not become an untracked side-effect channel.
6. Capture a fresh action observation tied to the same run, action, and correlation identity.
7. Run the post-action gate. Validate freshness, functional cardinality, disjointness, closed enumerations, domain/range compatibility, required references, and world-state coherence.
8. If the post-gate rejects, preserve the action observation but stop success propagation.
9. If both gates pass, emit one immutable successor event with a new event ID, inherited correlation ID, immediate-parent causation ID, and advanced sequence.
10. Record the successor in the evidence sink and hand off the strongest actually proven state. Synthetic evidence never promotes itself to live runtime proof.

## Outputs

- `cascade-run-context.json`;
- `cascade-pre-gate-result.json`;
- `cascade-action-observation.json` when execution was actually observed;
- `cascade-post-gate-result.json`;
- `cascade-successor-event.json` only for an accepted chain;
- `cascade-proof-ledger.json`;
- `cascade-operator-report.md`;
- `cascade-final-handoff.json`.

## Deterministic validation

Run, in order:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-TypedCascadeHarness.ps1
python tests/test_typed_cascade_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-RuntimeEventContract.ps1
git diff --check
```

The one-command offline entrypoint is `Test-TypedCascadeHarness.cmd`.

## Proof boundaries

A passing pre-gate proves request structure and declared prerequisites only. A passing post-gate proves declared domain coherence for one fresh result only. A synthetic successor proves contract causality only. None of those prove that a product dispatcher, Pydantic runtime, OWL reasoner, SHACL engine, external target, or live event cascade executed.

## Forbidden scope

- Do not modify `AGENTS.md` from this skill.
- Do not let an agent bypass either deterministic gate.
- Do not permit an input rejection to execute anyway.
- Do not emit a success successor after post-gate rejection.
- Do not count stale or cross-run evidence.
- Do not persist secrets, raw customer payloads, or chain-of-thought.
- Do not claim Pydantic/OWL/SHACL runtime support from contract files alone.
- Do not mutate product runtime code unless a separate implementation sprint explicitly owns it.

## Stop and escalate

Stop when the input contract or ontology profile is missing or ambiguous, the action authority is absent, the deterministic action boundary is not identified, the result cannot be tied to the same run/action/correlation identity, ontology rules contradict one another, a required reference cannot be resolved, a success and rejection state coexist, or the requested proof exceeds the observed evidence.

The handoff must name the exact terminal classification, failed gate/rule, strongest observed proof, evidence artifacts, owner of the repair, and one executable next command.
