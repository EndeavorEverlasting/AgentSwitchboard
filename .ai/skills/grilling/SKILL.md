---
id: grilling
version: 1.1.0
status: experimental
---

# Grilling

## Source lineage

Salvaged from PR #94; adapted from the pinned donor `grilling/SKILL.md`.

## Trigger

Use to stress-test a destination, plan, or decision through human-owned answers. `wayfinder:grilling` pairs with `domain-modeling`.

## Inputs

- decision tree and settled prerequisites;
- repository evidence;
- human decision-maker;
- Wayfinder pointer when applicable.

## Procedure

1. Build a dependency-aware question tree.
2. Ask only the current frontier.
3. Resolve discoverable facts with tools/research instead of offloading lookup.
4. Separate recommendations from the human's choice.
5. Wait for the actual human answer before settling the decision.
6. Recompute the frontier after each answer.
7. Put detailed answers in the decision owner; maps receive linked gists only.

## Outputs

- observed human decisions;
- newly exposed questions/fog;
- domain-model updates where needed;
- decision pointers.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Forbidden scope

Self-answering the human side, inferring consent, hidden assumptions marked settled, or implementing merely because a recommendation emerged.

## Stop and escalate

Stop when a prerequisite fact is unavailable, the decision belongs to another owner, the human pauses, or the next step is implementation.
