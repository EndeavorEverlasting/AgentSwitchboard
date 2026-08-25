---
id: repo-intake
version: 1.1.0
status: canonical
---

# Repository Intake

## Trigger

Use for an unfamiliar repository, stale or placeholder context, uncertain Git state, when repository truth must be recovered before selecting work, or before invention/external research when an existing canonical owner may already contain the needed principle or mechanism.

## Inputs

- repository path or repository identifier;
- current branch and worktree state when available;
- task request and known constraints;
- accessible PR, issue, plan, test, validator, artifact, architecture, ADR/specification, manifest/registry, skill, and relevant history evidence.

## Procedure

1. Run compact Git and PR preflight.
2. Read repository law and ownership/architecture entry points.
3. Search the smallest sufficient canonical surfaces before inventing: architecture/ADRs/specs, manifests/registries/schemas, workflow/context maps, skills, validators/tests, plans/reports, implementation helpers, and relevant history.
4. Build a compact anti-rediscovery record: `question | surfaces searched | canonical owner found | reusable truth | unresolved gap | external search needed`.
5. If an owner or principle already exists, reuse or strengthen it; link equivalent identities instead of restating competing truth.
6. Use repository-family/shared doctrine when the local repository delegates the concern. Search external/Drive-authoritative evidence only for an explicit unresolved gap, and never let recency silently override repository authority.
7. Prefer deterministic hydration hooks/scripts for repeatedly gathered known state when they reduce model/tool turns without broad context dumping.
8. Distinguish fact, inference, and unknown.
9. Rank bounded sprint candidates.
10. Select the smallest safe sprint that unblocks the most later work.
11. Hand off to `bounded-sprint` when a safe tracked change exists.

## Outputs

- compact evidence ledger;
- anti-rediscovery record showing reused truth and unresolved gaps;
- ranked sprint queue;
- selected owned and forbidden scope;
- exact blocker when no safe write is possible.

## Deterministic validation

Use repository-native validators plus Git status, diff, branch, and PR evidence. Verify that any claimed new abstraction or external research lane names the unresolved local gap that justified it. Do not persist a census document unless downstream workflows require it.

## Forbidden scope

Do not crawl vendored/generated dependencies without cause. Do not mutate live targets, rewrite history, create speculative architecture as a substitute for evidence, re-derive repository-owned principles from model memory, or search outward merely because local discovery was skipped.

## Stop and escalate

Stop when repository state is unsafe to modify, required canonical evidence is inaccessible, ownership remains genuinely ambiguous after bounded discovery, or the next action requires unauthorized destructive or live-target behavior.
