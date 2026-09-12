# OpenCode Free Model Ranking History

This file records dated operational ranking snapshots for free models surfaced through OpenCode. It is an append-only decision ledger for repository-agent work, not a permanent claim that one model is universally better than another.

## Recording contract

- Preserve prior snapshots exactly; add a new dated snapshot when the ranking changes.
- Record the exact model display name and tier shown by OpenCode at the time.
- State the workload being ranked. A coding-agent ranking does not automatically transfer to chat, writing, research, or other workloads.
- Separate operator observations from broader benchmark/vendor evidence when both exist.
- Treat availability, pricing, preview status, context limits, and provider behavior as time-sensitive.
- A later snapshot supersedes the current recommendation for new work without deleting the historical record.

## Snapshot — 2026-08-23 02:31 EDT

**Snapshot ID:** `2026-08-23T02:31:00-04:00-opencode-free`

**Workload:** agentic repository engineering in OpenCode: repository investigation, implementation, multi-file changes, debugging, tests, refactors, harness-heavy work, architecture review, and bounded procedural execution.

**Selection context:** Big Pickle was not included in the top four after an operator-observed stall of roughly 45 minutes while the UI remained around 10% token/context usage and produced no useful progress. That is an operational observation from this session, not a general benchmark result.

| Rank | Model | Tier | Preferred use in this snapshot | Record note |
| ---: | --- | --- | --- | --- |
| 1 | 0x Alpha | Free | Primary repo agent; large-context investigation, implementation, multi-file changes, harness-heavy work | Strongest current default for this workload; preview/fast-moving status means this placement should be rechecked frequently. |
| 2 | Muse Spark 1.2 | Free | Serious coding, debugging, tests, refactors | Strong evidence-backed coding option and the safest fallback when the leading preview model is unavailable or unstable. |
| 3 | Hy3 | Free | Reliable executor for explicit procedural instructions | Favored for bounded execution discipline and instruction-following when a sprint already has a strong plan/contract. |
| 4 | Nemotron 3 Ultra | Free | Architecture, difficult diagnosis, second-opinion work | Useful reasoning/review model; retained behind the first three for primary implementation work in this snapshot. |

### Operational routing order

For new repository-agent work at this snapshot:

`0x Alpha Free -> Muse Spark 1.2 Free -> Hy3 Free -> Nemotron 3 Ultra Free`

### Models immediately outside the top four

- `MiMo V2.5 Free` — next candidate to revisit if one of the top four degrades or disappears.
- `Nemotron 3.5 Lightning Free` — better treated as a lighter/high-volume worker or subagent than the first choice for the hardest planning and repository-wide reasoning.
- `Big Pickle` — session-specific reliability concern recorded above; reassess rather than permanently excluding it.

## Future snapshot template

Append, do not rewrite history:

```text
## Snapshot — YYYY-MM-DD HH:MM TZ

Snapshot ID: YYYY-MM-DDTHH:MM:SS±HH:MM-opencode-free
Workload: <bounded workload being ranked>
Selection context: <availability, incidents, provider changes, or evidence changes>

| Rank | Model | Tier | Preferred use in this snapshot | Record note |
| ---: | --- | --- | --- | --- |
| 1 | ... | ... | ... | ... |
| 2 | ... | ... | ... | ... |
| 3 | ... | ... | ... | ... |
| 4 | ... | ... | ... | ... |
```

When practical, future updates should mention what changed from the preceding snapshot so model movement can be analyzed over time rather than only observed as isolated rankings.
