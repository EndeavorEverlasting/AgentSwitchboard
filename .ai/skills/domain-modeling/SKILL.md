---
id: domain-modeling
version: 1.1.0
status: experimental
---

# Domain Modeling

## Source lineage

Salvaged from PR #94; adapted from the pinned donor `domain-modeling/SKILL.md`, `CONTEXT-FORMAT.md`, and `ADR-FORMAT.md`.

## Trigger

Use when work changes ubiquitous language, domain boundaries, or a durable architectural trade-off. Wayfinder grilling may invoke it as terms settle.

## Inputs

- nearest domain context/map and ADRs;
- current code evidence;
- observed human decisions;
- owned tracked-edit surface.

## Procedure

1. Read current domain language and applicable ADRs.
2. Challenge overloaded/conflicting terms with concrete scenarios.
3. Cross-check behavior claims against repository evidence.
4. Update domain context only after terminology actually settles.
5. Create an ADR only for a hard-to-reverse, surprising choice with a real trade-off.
6. Reconcile parallel context edits before other work treats them as authority.

## Outputs

- precise domain terminology;
- bounded context updates;
- ADR only when warranted;
- linked decision pointers.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Forbidden scope

Context files as scratchpads/specs, speculative terminology as settled truth, silent overwrite of concurrent edits, or ceremonial ADRs.

## Stop and escalate

Stop when the domain owner has not resolved a conflict, stated model and code disagree without an owner, or parallel edits collide.
