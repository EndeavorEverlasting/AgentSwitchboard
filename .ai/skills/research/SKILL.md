---
id: research
version: 1.0.0
status: canonical
---

# Research

## Source lineage

Adapted from `mattpocock/skills@84fdeffd12f2ee307994d1eb6feb48173b6e0502`, `skills/engineering/research/SKILL.md`, blob `0ba594a07f306479baa67104381f48e209ab6aae`. Snapshot: `third_party/mattpocock-skills/84fdeffd12f2ee307994d1eb6feb48173b6e0502/research/SKILL.md`.

## Trigger

Use when a decision depends on facts outside the current working tree: official docs/specifications, source repositories, first-party APIs, connected knowledge bases, or other authoritative evidence. `wayfinder:research` selects this AFK gate.

## Inputs

- exact research question;
- source-authority hierarchy;
- repository/public-vs-private evidence boundary;
- output location/branch convention;
- Wayfinder ticket/map pointer when invoked from Wayfinder.

## Procedure

1. State the exact question and what source owns the answer.
2. Prefer primary sources. Secondary material may locate primary evidence but cannot silently replace it.
3. Delegate to a real authorized subagent when available; otherwise research in the current bounded session. Never claim background execution that did not occur.
4. Write one Markdown findings artifact following repository convention; use a durable public path only for public-safe evidence.
5. Cite material claims and mark fact/inference/uncertainty/recommendation distinctly.
6. For Wayfinder, preserve work on an isolated `research/<name>` branch or equivalent non-conflicting evidence surface and link the artifact/commit from the decision ticket.
7. Post a concise resolution/context pointer; do not copy the full research artifact into the map.

## Outputs

- one findings artifact;
- primary-source references;
- explicit unknowns/staleness risks;
- Wayfinder context pointer when applicable.

## Deterministic validation

Wayfinder validation requires a non-empty artifact pointer, at least one primary-source reference, correct `research` skill invocation evidence, and no duplicated full findings in the map. Run `python tests/test_wayfinder_harness.py` and `scripts/Test-WayfinderHarness.ps1` when this skill changes.

## Forbidden scope

- invented citations;
- secondary summary presented as primary authority when primary evidence exists;
- asking the human to find facts available to safe tools;
- public commit of secrets/private runtime/customer evidence;
- converting a research fact into a human-owned product decision without the appropriate HITL gate.

## Stop and escalate

Stop when authoritative evidence is unavailable/contradictory, access would require unauthorized credentials/private data, the question has changed materially, or the next step is a human decision rather than research.
