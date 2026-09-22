---
id: research
version: 1.1.0
status: experimental
---

# Research

## Source lineage

Salvaged from PR #94; adapted from the pinned donor snapshot at `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/research/SKILL.md`.

## Trigger

Use when a decision depends on facts outside the current working tree. `wayfinder:research` selects this AFK gate.

## Inputs

- exact question and source authority;
- public/private evidence boundary;
- durable findings location;
- Wayfinder ticket pointer when applicable.

## Procedure

1. State the exact question and primary source owner.
2. Prefer primary sources; use secondary sources only to locate or contextualize them.
3. Use a real authorized subagent only when one actually exists; otherwise work in the current bounded session.
4. Produce one findings artifact with facts, inferences, uncertainty, and citations separated.
5. Link the artifact from the decision ticket; do not duplicate the full findings in the map.

## Outputs

- findings artifact;
- primary-source references;
- explicit unknowns/staleness;
- decision pointer when applicable.

## Deterministic validation

Run:

```powershell
python tests/test_wayfinder_core.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

This proves only the salvaged static/synthetic contract. Live tracker operations require separate authorized runtime proof.

## Forbidden scope

Invented citations, public secrets/private data, asking the human to perform safe factual lookup, or converting researched facts into a human-owned product choice.

## Stop and escalate

Stop when authoritative evidence is unavailable or contradictory, access is unauthorized, the question materially changes, or the next gate is a human decision.
