---
id: prototype
version: 1.1.0
status: experimental
---

# Prototype

## Source lineage

Salvaged from PR #94; adapted from the pinned donor `prototype/SKILL.md`, `prototype/LOGIC.md`, and `prototype/UI.md`.

## Trigger

Use when prose is too low-fidelity to decide behavior, state, layout, or information hierarchy. `wayfinder:prototype` is HITL.

## Inputs

- one precise decision question;
- existing project/runtime conventions;
- throwaway evidence surface;
- exact run method;
- human reviewer.

## Procedure

1. Bind the prototype to one question.
2. Use donor LOGIC guidance for state/data uncertainty and donor UI guidance for visual/layout uncertainty.
3. Build the cheapest concrete throwaway artifact that answers the question.
4. Keep it outside production authority and make it trivial to run.
5. Expose relevant state/variant so behavior is observable.
6. Capture the human's actual verdict. Running successfully is not approval.
7. Record the decision separately; implementation uses normal sprint/test/review gates.

## Outputs

- runnable throwaway;
- run command and source pointer;
- observed human verdict;
- linked decision pointer.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Forbidden scope

Production promotion by copy/paste, inferred approval, prototype without a precise question, broad unrelated infrastructure, or production secrets/data.

## Stop and escalate

Stop if the artifact cannot run safely, the question changes, the human verdict is unavailable, or the next work is production implementation.
