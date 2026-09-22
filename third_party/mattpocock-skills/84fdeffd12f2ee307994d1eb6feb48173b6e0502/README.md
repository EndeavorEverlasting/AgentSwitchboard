# Imported Matt Pocock Wayfinder sources

This directory contains immutable source snapshots imported from `mattpocock/skills` at commit `84fdeffd12f2ee307994d1eb6feb48173b6e0502`.

Purpose: prevent semantic drift and AI reinterpretation when AgentSwitchboard adapts Wayfinder. These files are **reference evidence, not AgentSwitchboard runtime authority**. The donor repository and pinned commit remain authoritative for the original behavior; AgentSwitchboard owns its adapted skills, schemas, tracker adapters, validators, and lifecycle rules.

Imported source set:

- `wayfinder/SKILL.md`
- `research/SKILL.md`
- `prototype/SKILL.md`
- `prototype/LOGIC.md`
- `prototype/UI.md`
- `grilling/SKILL.md`
- `domain-modeling/SKILL.md`
- `domain-modeling/CONTEXT-FORMAT.md`
- `domain-modeling/ADR-FORMAT.md`
- `to-spec/SKILL.md`
- `to-tickets/SKILL.md`
- `issue-tracker-github.md`
- `issue-tracker-local.md`
- `LICENSE`

The companion files are deliberately included because the donor skills reference them as part of their procedure. A snapshot retaining only `SKILL.md` would still force future agents to reconstruct prototype and domain-model behavior from memory.

Do not edit imported snapshots in place. A donor refresh must pin a new commit, import a new sibling snapshot directory, compare semantics, update the contribution manifest, and rerun the owning validators. Never silently follow donor `main`.
