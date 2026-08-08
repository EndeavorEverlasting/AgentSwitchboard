# Imported Matt Pocock Wayfinder sources

This directory contains immutable source snapshots imported from `mattpocock/skills` at commit `84fdeffd12f2ee307994d1eb6feb48173b6e0502`.

Purpose: prevent semantic drift and AI reinterpretation when AgentSwitchboard adapts Wayfinder. These files are **reference evidence, not AgentSwitchboard runtime authority**. The donor repository and pinned commit remain authoritative for the original behavior; AgentSwitchboard owns its adapted skills, schemas, tracker adapters, validators, and lifecycle rules.

Imported source set:

- `wayfinder/SKILL.md`
- `research/SKILL.md`
- `prototype/SKILL.md`
- `grilling/SKILL.md`
- `domain-modeling/SKILL.md`
- `to-spec/SKILL.md`
- `to-tickets/SKILL.md`
- `issue-tracker-github.md`
- `issue-tracker-local.md`
- `LICENSE`

Do not edit imported snapshots in place. A donor refresh must pin a new commit, import a new sibling snapshot directory, compare semantics, update the contribution manifest, and rerun the owning validators. Never silently follow donor `main`.
